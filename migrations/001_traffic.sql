-- =====================================================================================
-- VehiTrack · migrations/004_tenant.sql
-- Multi-tenant basico: separacion por fila (tenant_id) + RLS.
--
-- Depende de 002_traffic.sql y 003_telemetry.sql.
-- Aplicar manualmente:  psql "$POSTGRES_DSN" -f migrations/004_tenant.sql
--
-- -------------------------------------------------------------------------------------
-- QUE SE SEPARA Y QUE NO (la decision de fondo)
-- -------------------------------------------------------------------------------------
-- SE SEPARA (lleva tenant_id + RLS): lo que pertenece a alguien.
--   device.account, device.device, device.obd_session,
--   tracking.ingest_batch, tracking.trip, tracking.position,
--   traffic.observation
--
-- NO SE SEPARA (global, compartido): lo que vale justamente por ser de todos.
--   geo.grid_cell, geo.street_segment, geo.place, geo.street
--   traffic.link, traffic.live_state, traffic.profile
--   public.* (diccionarios), offline.* (paquetes de region)
--
-- Por que: el trafico colaborativo se muere si lo particionas por tenant. Una flota de
-- 20 carros sola no hace un mapa de trafico; 20 flotas + 500 personales, si. Los
-- agregados no llevan device_id y exigen min_device_count, asi que compartirlos no
-- expone a nadie. Lo que si se separa es el crudo: traffic.observation lleva tenant_id
-- para poder purgar, auditar y bloquear por cliente.
--
-- Modelo de aislamiento: UN tenant por cliente, SIEMPRE. Un usuario personal tambien es
-- un tenant (de una persona). Asi hay una sola regla de filtrado en todo el sistema y
-- cero casos especiales del tipo "si es personal filtra por device, si es flota por
-- empresa" — que es donde se cuelan las fugas de datos.
--
-- Se agrega AHORA y no despues porque hoy las tablas estan vacias: un ALTER sobre
-- tracking.position con 80 millones de filas es otra conversacion.
-- =====================================================================================

BEGIN;

SET LOCAL client_min_messages = WARNING;

-- =====================================================================================
-- 1. DICCIONARIO Y TABLA DE TENANT
-- =====================================================================================

CREATE TABLE IF NOT EXISTS public.tenant_kind (
    id         text     PRIMARY KEY,
    name       text     NOT NULL,
    sort_order smallint NOT NULL
);
COMMENT ON TABLE public.tenant_kind IS 'Tipo de tenant. Cambia el plan y los limites, no la forma de filtrar.';

INSERT INTO public.tenant_kind (id, name, sort_order) VALUES
  ('personal','Usuario personal',1),
  ('fleet','Empresa con flota',2),
  ('reseller','Integrador o revendedor',3),
  ('internal','Interno de Devitech',9)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.tenant (
    id             uuid        PRIMARY KEY,
    slug           text        NOT NULL UNIQUE,
    name           text        NOT NULL,
    tenant_kind_id text        NOT NULL REFERENCES public.tenant_kind(id),
    max_device     int,
    is_active      boolean     NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.tenant IS
    'Unidad de aislamiento. Un usuario personal tambien tiene su tenant: una sola regla de filtrado en todo el sistema.';
COMMENT ON COLUMN public.tenant.max_device IS 'NULL = sin limite. Se valida en prc_register_device.';

-- tenant de arranque: dueno de todo lo que ya exista y de los usuarios personales sueltos
INSERT INTO public.tenant (id, slug, name, tenant_kind_id)
VALUES ('00000000-0000-0000-0000-000000000001', 'devitech', 'Devitech (interno)', 'internal')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS device.account (
    id           uuid        PRIMARY KEY,
    tenant_id    uuid        NOT NULL REFERENCES public.tenant(id),
    email        text,
    display_name text,
    is_active    boolean     NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now(),
    deleted_at   timestamptz,
    UNIQUE (tenant_id, email)
);
COMMENT ON TABLE device.account IS
    'Cuenta de usuario dentro de un tenant. Sigue sin usarse hasta que implementes login; existe para no alterar despues.';

-- =====================================================================================
-- 2. tenant_id EN LAS TABLAS QUE PERTENECEN A ALGUIEN
-- =====================================================================================

DO $$
DECLARE
    t         text;
    v_default uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
    FOREACH t IN ARRAY ARRAY['device.device','device.obd_session','tracking.ingest_batch',
                             'tracking.trip','tracking.position','traffic.observation']
    LOOP
        IF to_regclass(t) IS NULL THEN CONTINUE; END IF;

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                       WHERE table_schema = split_part(t,'.',1)
                         AND table_name   = split_part(t,'.',2)
                         AND column_name  = 'tenant_id') THEN
            EXECUTE format('ALTER TABLE %s ADD COLUMN tenant_id uuid', t);
        END IF;

        -- backfill: el tenant sale del device dueno; si no hay device, el tenant de arranque
        IF t <> 'device.device' THEN
            EXECUTE format(
                'UPDATE %s x SET tenant_id = d.tenant_id FROM device.device d
                  WHERE d.id = x.device_id AND x.tenant_id IS NULL', t);
        END IF;
        EXECUTE format('UPDATE %s SET tenant_id = %L WHERE tenant_id IS NULL', t, v_default);

        EXECUTE format('ALTER TABLE %s ALTER COLUMN tenant_id SET NOT NULL', t);

        IF NOT EXISTS (SELECT 1 FROM pg_constraint
                       WHERE conname = 'fk_' || replace(t,'.','_') || '_tenant') THEN
            EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (tenant_id)
                            REFERENCES public.tenant(id)', t, 'fk_' || replace(t,'.','_') || '_tenant');
        END IF;
    END LOOP;
END $$;

CREATE INDEX IF NOT EXISTS ix_device_tenant       ON device.device (tenant_id) WHERE NOT is_blocked;
CREATE INDEX IF NOT EXISTS ix_obd_session_tenant  ON device.obd_session (tenant_id, started_at DESC);
CREATE INDEX IF NOT EXISTS ix_ingest_batch_tenant ON tracking.ingest_batch (tenant_id, received_at DESC);
CREATE INDEX IF NOT EXISTS ix_trip_tenant         ON tracking.trip (tenant_id, started_at DESC);

COMMENT ON COLUMN tracking.position.tenant_id IS
    'Desnormalizado a proposito: el filtro de RLS en la tabla mas grande no puede depender de un join a device.';

-- =====================================================================================
-- 3. RLS — el filtro que el ms no puede olvidar
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_current_tenant
-- Proposito : Tenant de la transaccion actual, leido del GUC app.tenant_id que setea el ms.
-- Parametros: ninguno
-- Retorna   : uuid, o NULL si no se seteo
-- Errores   : ninguno (falla cerrado: sin GUC, las politicas no dejan ver nada)
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_current_tenant()
RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['device.account','device.device','device.obd_session',
                             'tracking.ingest_batch','tracking.trip','tracking.position',
                             'traffic.observation']
    LOOP
        IF to_regclass(t) IS NULL THEN CONTINUE; END IF;
        EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('DROP POLICY IF EXISTS pol_tenant_isolation ON %s', t);
        EXECUTE format(
            'CREATE POLICY pol_tenant_isolation ON %s
                 USING (tenant_id = public.fnc_current_tenant())
                 WITH CHECK (tenant_id = public.fnc_current_tenant())', t);
    END LOOP;
END $$;

COMMENT ON FUNCTION public.fnc_current_tenant IS
    'El dueno de las tablas NO tiene FORCE ROW LEVEL SECURITY: los rollups y el cron (que
     corren como dueno) siguen viendo todo, que es lo que necesitan para agregar trafico.
     El rol vehitrack_app si esta sujeto a las politicas.';

-- =====================================================================================
-- 4. RUTINAS DE ADMINISTRACION DE TENANT
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.prc_upsert_tenant
-- Proposito : Registra o actualiza un tenant.
-- Parametros: p_tenant_id, p_slug, p_name, p_kind, p_max_device, p_is_active
--             p_result INOUT  {tenant_id, slug, created}
-- Errores   : VT020 tipo de tenant invalido
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE public.prc_upsert_tenant(
    p_tenant_id  uuid,
    p_slug       text,
    p_name       text,
    p_kind       text DEFAULT 'personal',
    p_max_device int  DEFAULT NULL,
    p_is_active  boolean DEFAULT true,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_created boolean;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.tenant_kind WHERE id = p_kind) THEN
        RAISE EXCEPTION 'tenant_kind % invalido', p_kind USING ERRCODE = 'VT020';
    END IF;

    INSERT INTO public.tenant (id, slug, name, tenant_kind_id, max_device, is_active, updated_at)
    VALUES (p_tenant_id, lower(p_slug), p_name, p_kind, p_max_device, p_is_active, now())
    ON CONFLICT (id) DO UPDATE SET
        slug           = EXCLUDED.slug,
        name           = EXCLUDED.name,
        tenant_kind_id = EXCLUDED.tenant_kind_id,
        max_device     = EXCLUDED.max_device,
        is_active      = EXCLUDED.is_active,
        updated_at     = now()
    RETURNING (xmax = 0) INTO v_created;

    p_result := jsonb_build_object('tenant_id', p_tenant_id, 'slug', lower(p_slug), 'created', v_created);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_register_device
-- Proposito : Registra o actualiza un dispositivo dentro de un tenant. Es el unico camino
--             para que exista un device, porque es donde se decide el aislamiento.
-- Parametros: p_device_id, p_tenant_id, p_install_id, p_platform, p_account_id
--             p_result INOUT  {device_id, tenant_id, created}
-- Errores   : VT021 tenant inexistente o inactivo · VT022 cupo de dispositivos agotado
--             VT023 el device ya pertenece a otro tenant
-- Nota      : Un device NO se muda de tenant en caliente. Mover historial entre clientes
--             es una operacion administrativa, no un efecto secundario de un registro.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_register_device(
    p_device_id  uuid,
    p_tenant_id  uuid,
    p_install_id text DEFAULT NULL,
    p_platform   text DEFAULT NULL,
    p_account_id uuid DEFAULT NULL,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_max     int;
    v_count   int;
    v_owner   uuid;
    v_created boolean;
BEGIN
    SELECT max_device INTO v_max FROM public.tenant WHERE id = p_tenant_id AND is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'tenant % inexistente o inactivo', p_tenant_id USING ERRCODE = 'VT021';
    END IF;

    SELECT tenant_id INTO v_owner FROM device.device WHERE id = p_device_id;
    IF FOUND AND v_owner <> p_tenant_id THEN
        RAISE EXCEPTION 'device % ya pertenece a otro tenant', p_device_id USING ERRCODE = 'VT023';
    END IF;

    IF v_owner IS NULL AND v_max IS NOT NULL THEN
        SELECT count(*) INTO v_count FROM device.device WHERE tenant_id = p_tenant_id;
        IF v_count >= v_max THEN
            RAISE EXCEPTION 'tenant % agoto su cupo de % dispositivos', p_tenant_id, v_max
                USING ERRCODE = 'VT022';
        END IF;
    END IF;

    INSERT INTO device.device (id, tenant_id, install_id, platform, registered_at, last_seen_at)
    VALUES (p_device_id, p_tenant_id, p_install_id, p_platform, now(), now())
    ON CONFLICT (id) DO UPDATE SET
        install_id   = COALESCE(EXCLUDED.install_id, device.install_id),
        platform     = COALESCE(EXCLUDED.platform,   device.platform),
        last_seen_at = now()
    RETURNING (xmax = 0) INTO v_created;

    p_result := jsonb_build_object(
        'device_id', p_device_id, 'tenant_id', p_tenant_id, 'created', v_created);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.fnc_tenant_of_device
-- Proposito : Tenant dueno de un device. Lo usan las ingestas para estampar tenant_id.
-- Parametros: p_device_id
-- Retorna   : uuid o NULL
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION device.fnc_tenant_of_device(p_device_id uuid)
RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT tenant_id FROM device.device WHERE id = p_device_id;
$$;

-- =====================================================================================
-- 5. INDICES POR TENANT EN LAS PARTICIONES (bump de las funciones de particion)
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- tracking.fnc_ensure_position_partition
-- Proposito : Crea (si falta) la particion mensual de tracking.position y sus indices.
-- Parametros: p_month
-- Retorna   : text nombre de la particion
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.1.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
--             1.1.0  2026-08-01  Lucho  Indice (tenant_id, recorded_at) para el filtro de RLS.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tracking.fnc_ensure_position_partition(p_month date)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_from date := date_trunc('month', p_month)::date;
    v_to   date := (date_trunc('month', p_month) + interval '1 month')::date;
    v_name text := 'position_' || to_char(v_from, 'YYYYMM');
BEGIN
    IF to_regclass('tracking.' || v_name) IS NOT NULL THEN RETURN v_name; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('tracking.' || v_name));
    IF to_regclass('tracking.' || v_name) IS NOT NULL THEN RETURN v_name; END IF;

    EXECUTE format(
        'CREATE TABLE tracking.%I PARTITION OF tracking.position FOR VALUES FROM (%L) TO (%L)',
        v_name, v_from, v_to);
    EXECUTE format('CREATE INDEX %I ON tracking.%I USING brin (recorded_at)', 'brin_'||v_name, v_name);
    EXECUTE format('CREATE INDEX %I ON tracking.%I (trip_id, recorded_at)', 'ix_'||v_name||'_trip', v_name);
    EXECUTE format('CREATE INDEX %I ON tracking.%I (tenant_id, recorded_at)', 'ix_'||v_name||'_tenant', v_name);
    EXECUTE format('CREATE INDEX %I ON tracking.%I USING gist (geom)', 'gist_'||v_name, v_name);
    RETURN v_name;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.fnc_ensure_observation_partition
-- Proposito : Crea (si falta) la particion mensual de traffic.observation y sus indices.
-- Parametros: p_month
-- Retorna   : text nombre de la particion
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.1.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
--             1.1.0  2026-08-01  Lucho  Indice (tenant_id, observed_at) para purga y auditoria por cliente.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION traffic.fnc_ensure_observation_partition(p_month date)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_from date := date_trunc('month', p_month)::date;
    v_to   date := (date_trunc('month', p_month) + interval '1 month')::date;
    v_name text := 'observation_' || to_char(v_from, 'YYYYMM');
BEGIN
    IF to_regclass('traffic.' || v_name) IS NOT NULL THEN RETURN v_name; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('traffic.' || v_name));
    IF to_regclass('traffic.' || v_name) IS NOT NULL THEN RETURN v_name; END IF;

    EXECUTE format(
        'CREATE TABLE traffic.%I PARTITION OF traffic.observation FOR VALUES FROM (%L) TO (%L)',
        v_name, v_from, v_to);
    EXECUTE format('CREATE INDEX %I ON traffic.%I USING brin (observed_at)', 'brin_'||v_name, v_name);
    EXECUTE format('CREATE INDEX %I ON traffic.%I (traffic_link_id, observed_at)', 'ix_'||v_name||'_link', v_name);
    EXECUTE format('CREATE INDEX %I ON traffic.%I (device_id, observed_at)', 'ix_'||v_name||'_device', v_name);
    EXECUTE format('CREATE INDEX %I ON traffic.%I (tenant_id, observed_at)', 'ix_'||v_name||'_tenant', v_name);
    RETURN v_name;
END $$;

-- indices por tenant en las particiones que ya existian
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT n.nspname AS sch, c.relname AS rel
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE (n.nspname='tracking' AND c.relname ~ '^position_[0-9]{6}$')
           OR (n.nspname='traffic'  AND c.relname ~ '^observation_[0-9]{6}$')
    LOOP
        IF to_regclass(format('%I.%I', r.sch, 'ix_'||r.rel||'_tenant')) IS NULL THEN
            EXECUTE format('CREATE INDEX %I ON %I.%I (tenant_id, %I)',
                'ix_'||r.rel||'_tenant', r.sch, r.rel,
                CASE WHEN r.sch='tracking' THEN 'recorded_at' ELSE 'observed_at' END);
        END IF;
    END LOOP;
END $$;

-- =====================================================================================
-- 6. INGESTAS — estampan tenant_id (bump a 1.1.0)
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- tracking.prc_ingest_telemetry
-- Proposito : Unico endpoint de escritura de telemetria: upsert de tracking.position,
--             derivacion a traffic.observation y contadores de lote y sesion OBD.
-- Parametros: (ver 003_telemetry.sql)
-- Errores   : VT001 device inexistente · VT002 device bloqueado · VT003 lote de otro device
-- Autor     : Lucho · Devitech
-- Version   : 1.1.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
--             1.1.0  2026-08-01  Lucho  Estampa tenant_id (del device) en batch, position
--                                        y observation. Sin esto, RLS rechaza el insert.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE tracking.prc_ingest_telemetry(
    p_device_id         uuid,
    p_batch_id          uuid,
    p_samples           jsonb,
    p_client_created_at timestamptz DEFAULT NULL,
    INOUT p_result      jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_blocked    boolean;
    v_tenant     uuid;
    v_owner      uuid;
    v_existing   record;
    v_pos_acc    numeric  := public.fnc_setting_num('tracking.max_accuracy_m');
    v_max_alt    numeric  := public.fnc_setting_num('tracking.max_altitude_m');
    v_tr_acc     numeric  := public.fnc_setting_num('traffic.max_accuracy_m');
    v_max_speed  numeric  := public.fnc_setting_num('traffic.max_speed_kmh');
    v_min_rpm    numeric  := public.fnc_setting_num('obd.min_rpm');
    v_max_rpm    numeric  := public.fnc_setting_num('obd.max_rpm');
    v_min_temp   numeric  := public.fnc_setting_num('obd.min_coolant_temp_c');
    v_max_temp   numeric  := public.fnc_setting_num('obd.max_coolant_temp_c');
    v_skew       interval := (public.fnc_setting_num('traffic.max_future_skew_minutes') || ' minute')::interval;
    v_past       interval := (public.fnc_setting_num('traffic.max_past_days') || ' day')::interval;
    v_tz         text     := public.fnc_setting_text('locale.timezone');
    v_total      int := 0;
    v_inserted   int := 0;
    v_updated    int := 0;
    v_traffic    int := 0;
    m            date;
BEGIN
    SELECT is_blocked, tenant_id INTO v_blocked, v_tenant
      FROM device.device WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device % no registrado', p_device_id USING ERRCODE = 'VT001';
    END IF;
    IF v_blocked THEN
        RAISE EXCEPTION 'device % bloqueado', p_device_id USING ERRCODE = 'VT002';
    END IF;

    SELECT device_id INTO v_owner FROM tracking.ingest_batch WHERE id = p_batch_id;
    IF FOUND THEN
        IF v_owner <> p_device_id THEN
            RAISE EXCEPTION 'batch % pertenece a otro device', p_batch_id USING ERRCODE = 'VT003';
        END IF;
        SELECT item_count, accepted_count, rejected_count INTO v_existing
          FROM tracking.ingest_batch WHERE id = p_batch_id;
        p_result := jsonb_build_object(
            'batch_id', p_batch_id, 'duplicate', true,
            'received', v_existing.item_count,
            'accepted', v_existing.accepted_count,
            'rejected', v_existing.rejected_count);
        RETURN;
    END IF;

    v_total := COALESCE(jsonb_array_length(p_samples), 0);

    INSERT INTO tracking.ingest_batch (id, tenant_id, device_id, payload_kind, item_count, client_created_at)
    VALUES (p_batch_id, v_tenant, p_device_id, 'telemetry', v_total, p_client_created_at);

    FOR m IN
        SELECT DISTINCT date_trunc('month', (s ->> 'recorded_at')::timestamptz)::date
        FROM jsonb_array_elements(COALESCE(p_samples, '[]'::jsonb)) s
        WHERE (s ->> 'recorded_at') IS NOT NULL
    LOOP
        PERFORM tracking.fnc_ensure_position_partition(m);
        PERFORM traffic.fnc_ensure_observation_partition(m);
    END LOOP;

    DROP TABLE IF EXISTS _tele;
    CREATE TEMP TABLE _tele ON COMMIT DROP AS
    WITH raw AS (
        SELECT *
        FROM jsonb_to_recordset(COALESCE(p_samples, '[]'::jsonb)) AS s(
            lat            double precision,
            lon            double precision,
            recorded_at    timestamptz,
            speed_gps_kmh  numeric,
            speed_obd_kmh  numeric,
            bearing_deg    numeric,
            accuracy_m     numeric,
            altitude_m     numeric,
            rpm            numeric,
            coolant_temp_c numeric,
            fuel_level_pct numeric,
            trip_id        uuid,
            obd_session_id uuid,
            source         text
        )
    ),
    valid AS (
        SELECT r.*, ST_SetSRID(ST_MakePoint(r.lon, r.lat), 4326) AS geom
        FROM raw r
        WHERE r.lat BETWEEN -90 AND 90
          AND r.lon BETWEEN -180 AND 180
          AND r.recorded_at IS NOT NULL
          AND r.recorded_at <= now() + v_skew
          AND r.recorded_at >= now() - v_past
          AND (r.accuracy_m IS NULL OR r.accuracy_m <= v_pos_acc)
    )
    SELECT
        v.geom,
        v.recorded_at,
        (SELECT t.id FROM tracking.trip t WHERE t.id = v.trip_id)             AS trip_id,
        (SELECT o.id FROM device.obd_session o WHERE o.id = v.obd_session_id) AS obd_session_id,
        CASE WHEN v.speed_gps_kmh BETWEEN 0 AND v_max_speed THEN round(v.speed_gps_kmh,2) END AS speed_gps_kmh,
        CASE WHEN v.speed_obd_kmh BETWEEN 0 AND v_max_speed THEN round(v.speed_obd_kmh,2) END AS speed_obd_kmh,
        COALESCE(
            CASE WHEN v.speed_obd_kmh BETWEEN 0 AND v_max_speed THEN round(v.speed_obd_kmh,2) END,
            CASE WHEN v.speed_gps_kmh BETWEEN 0 AND v_max_speed THEN round(v.speed_gps_kmh,2) END
        ) AS speed_kmh,
        CASE
            WHEN v.source IN (SELECT id FROM public.position_source) THEN v.source
            WHEN v.speed_obd_kmh IS NOT NULL THEN 'obd'
            ELSE 'gps'
        END AS position_source_id,
        COALESCE(
            CASE WHEN v.bearing_deg IS NOT NULL THEN ((v.bearing_deg % 360) + 360) % 360 END,
            round(degrees(ST_Azimuth(lag(v.geom) OVER (ORDER BY v.recorded_at), v.geom))::numeric, 2)
        ) AS bearing_deg,
        round(v.accuracy_m, 2) AS accuracy_m,
        CASE WHEN abs(v.altitude_m) <= v_max_alt THEN round(v.altitude_m, 2) END AS altitude_m,
        CASE WHEN v.rpm BETWEEN v_min_rpm AND v_max_rpm THEN round(v.rpm, 2) END AS rpm,
        CASE WHEN v.coolant_temp_c BETWEEN v_min_temp AND v_max_temp THEN round(v.coolant_temp_c,1) END AS coolant_temp_c,
        CASE WHEN v.fuel_level_pct BETWEEN 0 AND 100 THEN round(v.fuel_level_pct,2) END AS fuel_level_pct
    FROM valid v;

    WITH ins AS (
        INSERT INTO tracking.position (
            tenant_id, device_id, trip_id, ingest_batch_id, obd_session_id, position_source_id,
            geom, speed_kmh, speed_gps_kmh, speed_obd_kmh, bearing_deg, accuracy_m,
            altitude_m, rpm, coolant_temp_c, fuel_level_pct, recorded_at)
        SELECT v_tenant, p_device_id, t.trip_id, p_batch_id, t.obd_session_id, t.position_source_id,
               t.geom, t.speed_kmh, t.speed_gps_kmh, t.speed_obd_kmh, t.bearing_deg, t.accuracy_m,
               t.altitude_m, t.rpm, t.coolant_temp_c, t.fuel_level_pct, t.recorded_at
        FROM _tele t
        ON CONFLICT (recorded_at, device_id) DO UPDATE SET
            trip_id            = COALESCE(EXCLUDED.trip_id,        position.trip_id),
            obd_session_id     = COALESCE(EXCLUDED.obd_session_id, position.obd_session_id),
            ingest_batch_id    = EXCLUDED.ingest_batch_id,
            position_source_id = EXCLUDED.position_source_id,
            geom               = EXCLUDED.geom,
            speed_kmh          = COALESCE(EXCLUDED.speed_kmh,      position.speed_kmh),
            speed_gps_kmh      = COALESCE(EXCLUDED.speed_gps_kmh,  position.speed_gps_kmh),
            speed_obd_kmh      = COALESCE(EXCLUDED.speed_obd_kmh,  position.speed_obd_kmh),
            bearing_deg        = COALESCE(EXCLUDED.bearing_deg,    position.bearing_deg),
            accuracy_m         = COALESCE(EXCLUDED.accuracy_m,     position.accuracy_m),
            altitude_m         = COALESCE(EXCLUDED.altitude_m,     position.altitude_m),
            rpm                = COALESCE(EXCLUDED.rpm,            position.rpm),
            coolant_temp_c     = COALESCE(EXCLUDED.coolant_temp_c, position.coolant_temp_c),
            fuel_level_pct     = COALESCE(EXCLUDED.fuel_level_pct, position.fuel_level_pct),
            received_at        = now()
        RETURNING (xmax = 0) AS was_insert
    )
    SELECT count(*) FILTER (WHERE was_insert),
           count(*) FILTER (WHERE NOT was_insert)
      INTO v_inserted, v_updated
      FROM ins;

    WITH src AS (
        SELECT t.*,
               traffic.fnc_resolve_grid_link(
                   geo.fnc_resolve_grid_cell(t.geom),
                   public.fnc_heading_bucket_of(t.bearing_deg)
               ) AS traffic_link_id
        FROM _tele t
        WHERE t.speed_kmh IS NOT NULL
          AND t.bearing_deg IS NOT NULL
          AND (t.accuracy_m IS NULL OR t.accuracy_m <= v_tr_acc)
    )
    INSERT INTO traffic.observation (
        tenant_id, device_id, trip_id, ingest_batch_id, traffic_link_id, position_source_id,
        day_kind_id, time_slot_id, speed_kmh, accuracy_m, heading_deg, observed_at)
    SELECT v_tenant, p_device_id, s.trip_id, p_batch_id, s.traffic_link_id, s.position_source_id,
           public.fnc_day_kind_of(s.recorded_at, v_tz),
           public.fnc_time_slot_of(s.recorded_at, v_tz),
           s.speed_kmh, s.accuracy_m, s.bearing_deg::smallint, s.recorded_at
    FROM src s;

    GET DIAGNOSTICS v_traffic = ROW_COUNT;

    UPDATE tracking.ingest_batch
       SET accepted_count = v_inserted + v_updated,
           rejected_count = v_total - (v_inserted + v_updated)
     WHERE id = p_batch_id;

    UPDATE device.obd_session o
       SET sample_count = o.sample_count + c.n, updated_at = now()
      FROM (SELECT obd_session_id, count(*) AS n FROM _tele
             WHERE obd_session_id IS NOT NULL GROUP BY obd_session_id) c
     WHERE o.id = c.obd_session_id;

    UPDATE device.device SET last_seen_at = now() WHERE id = p_device_id;

    p_result := jsonb_build_object(
        'batch_id', p_batch_id, 'duplicate', false, 'tenant_id', v_tenant,
        'received', v_total, 'inserted', v_inserted, 'updated', v_updated,
        'rejected', v_total - (v_inserted + v_updated),
        'traffic_observations', v_traffic);
END $$;

-- ---- sesion OBD: tambien estampa tenant --------------------------------------------
-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_upsert_obd_session
-- Proposito : Registra o actualiza una sesion OBD (protocolo, adaptador, ventana).
-- Parametros: (ver 003_telemetry.sql)
-- Errores   : VT001 device inexistente
-- Autor     : Lucho · Devitech
-- Version   : 1.1.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
--             1.1.0  2026-08-01  Lucho  Estampa tenant_id del device.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_upsert_obd_session(
    p_session_id   uuid,
    p_device_id    uuid,
    p_protocol     text,
    p_trip_id      uuid DEFAULT NULL,
    p_adapter_name text DEFAULT NULL,
    p_started_at   timestamptz DEFAULT NULL,
    p_ended_at     timestamptz DEFAULT NULL,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_protocol text;
    v_tenant   uuid;
    v_created  boolean;
BEGIN
    SELECT tenant_id INTO v_tenant FROM device.device WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device % no registrado', p_device_id USING ERRCODE = 'VT001';
    END IF;

    SELECT id INTO v_protocol FROM public.obd_protocol
     WHERE id = lower(coalesce(p_protocol,'')) OR elm_code = upper(coalesce(p_protocol,''))
     ORDER BY sort_order LIMIT 1;
    v_protocol := COALESCE(v_protocol, 'unknown');

    INSERT INTO device.obd_session (
        id, tenant_id, device_id, trip_id, obd_protocol_id, adapter_name, started_at, ended_at, updated_at)
    VALUES (p_session_id, v_tenant, p_device_id, p_trip_id, v_protocol, p_adapter_name,
            COALESCE(p_started_at, now()), p_ended_at, now())
    ON CONFLICT (id) DO UPDATE SET
        trip_id         = COALESCE(EXCLUDED.trip_id, obd_session.trip_id),
        obd_protocol_id = EXCLUDED.obd_protocol_id,
        adapter_name    = COALESCE(EXCLUDED.adapter_name, obd_session.adapter_name),
        ended_at        = COALESCE(EXCLUDED.ended_at, obd_session.ended_at),
        updated_at      = now()
    RETURNING (xmax = 0) INTO v_created;

    p_result := jsonb_build_object(
        'session_id', p_session_id, 'tenant_id', v_tenant,
        'obd_protocol_id', v_protocol, 'created', v_created);
END $$;

-- ---- ingesta de trafico "pura" (si decides conservarla) -----------------------------
-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.prc_ingest_batch
-- Version   : 1.1.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
--             1.1.0  2026-08-01  Lucho  Estampa tenant_id. Sigue siendo redundante con
--                                        prc_ingest_telemetry (ver seccion 8 de la 003).
-- ─────────────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname='traffic' AND p.proname='prc_ingest_batch') THEN
        RAISE WARNING 'traffic.prc_ingest_batch sigue en 1.0.0 y NO estampa tenant_id: con RLS activo sus inserts fallaran. Elimina el procedimiento o subelo a 1.1.0 antes de usarlo.';
    END IF;
END $$;

-- =====================================================================================
-- 7. LECTURA POR TENANT
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_tenant_usage
-- Proposito : Consumo por tenant (devices, viajes, puntos, aporte a trafico). Base para
--             facturar, para poner limites y para saber quien esta abusando de la ingesta.
-- Parametros: p_from, p_to  ventana
-- Retorna   : SETOF por tenant
-- Errores   : ninguno
-- Nota      : Corre como dueno (bypass de RLS) para poder consolidar todos los tenants.
--             No exponer al rol de la app.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_tenant_usage(
    p_from timestamptz,
    p_to   timestamptz
) RETURNS TABLE (
    tenant_id           uuid,
    slug                text,
    device_count        bigint,
    batch_count         bigint,
    position_count      bigint,
    observation_count   bigint
) LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT t.id, t.slug,
           (SELECT count(*) FROM device.device d WHERE d.tenant_id = t.id),
           (SELECT count(*) FROM tracking.ingest_batch b
             WHERE b.tenant_id = t.id AND b.received_at >= p_from AND b.received_at < p_to),
           (SELECT count(*) FROM tracking.position p
             WHERE p.tenant_id = t.id AND p.recorded_at >= p_from AND p.recorded_at < p_to),
           (SELECT count(*) FROM traffic.observation o
             WHERE o.tenant_id = t.id AND o.observed_at >= p_from AND o.observed_at < p_to)
    FROM public.tenant t
    WHERE t.is_active
    ORDER BY t.slug;
$$;

-- =====================================================================================
-- 8. REGISTRO Y PERMISOS
-- =====================================================================================

INSERT INTO public.db_routine (schema_name, routine_name, routine_type, purpose, author, version, migration) VALUES
 ('public','fnc_current_tenant','function','Tenant de la transaccion (GUC app.tenant_id)','Lucho · Devitech','1.0.0','004_tenant.sql'),
 ('public','prc_upsert_tenant','procedure','Registro o actualizacion de tenant','Lucho · Devitech','1.0.0','004_tenant.sql'),
 ('public','fnc_tenant_usage','function','Consumo por tenant para limites y facturacion','Lucho · Devitech','1.0.0','004_tenant.sql'),
 ('device','prc_register_device','procedure','Registro o actualizacion de device dentro de un tenant','Lucho · Devitech','1.0.0','004_tenant.sql'),
 ('device','fnc_tenant_of_device','function','Tenant dueno de un device','Lucho · Devitech','1.0.0','004_tenant.sql'),
 ('tracking','fnc_ensure_position_partition','function','Crea particion mensual de position','Lucho · Devitech','1.1.0','004_tenant.sql'),
 ('traffic','fnc_ensure_observation_partition','function','Crea particion mensual de observation','Lucho · Devitech','1.1.0','004_tenant.sql'),
 ('tracking','prc_ingest_telemetry','procedure','Ingesta de telemetria GPS+OBD con tenant','Lucho · Devitech','1.1.0','004_tenant.sql'),
 ('device','prc_upsert_obd_session','procedure','Registro o actualizacion de sesion OBD con tenant','Lucho · Devitech','1.1.0','004_tenant.sql')
ON CONFLICT (schema_name, routine_name) DO UPDATE SET
    purpose = EXCLUDED.purpose, author = EXCLUDED.author,
    version = EXCLUDED.version, migration = EXCLUDED.migration, updated_at = now();

GRANT SELECT ON public.tenant, public.tenant_kind TO vehitrack_app;

GRANT EXECUTE ON FUNCTION
    public.fnc_current_tenant(),
    device.fnc_tenant_of_device(uuid)
TO vehitrack_app;

GRANT EXECUTE ON PROCEDURE
    device.prc_register_device(uuid, uuid, text, text, uuid, jsonb)
TO vehitrack_app;

-- fnc_tenant_usage y prc_upsert_tenant NO se otorgan al rol de la app: son de administracion.
REVOKE EXECUTE ON FUNCTION public.fnc_tenant_usage(timestamptz, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE public.prc_upsert_tenant(uuid, text, text, text, int, boolean, jsonb) FROM PUBLIC;

COMMIT;

-- =====================================================================================
-- 9. CONTRATO CON EL ms — la parte que hay que hacer bien
--
-- El ms resuelve el tenant desde el device_id (o del token) y lo setea POR TRANSACCION:
--
--   BEGIN;
--   SET LOCAL app.tenant_id = '<uuid del tenant>';
--   CALL tracking.prc_ingest_telemetry($1,$2,$3,$4,NULL);
--   COMMIT;
--
-- SET LOCAL, no SET: con pool de conexiones un SET normal se queda pegado y el siguiente
-- request hereda el tenant del anterior. Ese es EL bug clasico de multi-tenant con RLS.
--
-- Middleware en Go: el mismo que ya inyecta device_id en el context resuelve tenant_id y
-- abre la transaccion con el SET LOCAL. Ningun repositorio recibe tenant_id como parametro.
--
-- Verificacion rapida:
--   SET LOCAL app.tenant_id = '<tenant A>';  SELECT count(*) FROM tracking.position;
--   SET LOCAL app.tenant_id = '<tenant B>';  SELECT count(*) FROM tracking.position;
-- Como rol vehitrack_app deben dar numeros distintos. Como dueno de la BD dan el total:
-- eso es intencional (los rollups lo necesitan), asi que el ms NUNCA se conecta como dueno.
-- =====================================================================================