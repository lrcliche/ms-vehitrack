-- =====================================================================================
-- VehiTrack · migrations/003_device_data.sql
-- Datos del usuario (favoritos, POI propios, geocercas, ajustes) + motor de sync delta.
--
-- Depende de 001_vehitrack.sql y 002_geocoding.sql.
-- Aplicar manualmente:  psql "$POSTGRES_DSN" -f migrations/003_device_data.sql
--
-- -------------------------------------------------------------------------------------
-- DOS COSAS QUE ARREGLA ESTE ARCHIVO
-- -------------------------------------------------------------------------------------
-- 1) EL HUECO DE REGISTRO DEL 001.
--    prc_register_device esta sujeto a RLS y prc_upsert_tenant NO se le otorgo a
--    vehitrack_app (correcto: es administracion). Resultado: un usuario personal NUEVO no
--    puede existir — no hay tenant que poner en SET LOCAL antes de registrarse, y no puede
--    crearlo. Ciclo cerrado.
--    Aqui va prc_provision_personal_tenant: SECURITY DEFINER, crea tenant + device en una
--    transaccion. Es el UNICO camino de escritura que corre sin app.tenant_id, y por eso
--    el ms debe exponerlo SOLO en POST /v1/devices/register CON RATE LIMIT POR IP. Sin eso
--    es una fabrica gratuita de tenants para cualquiera que descubra el endpoint.
--
-- 2) EL SYNC SIN BORRADOS.
--    Sin soft delete y sin version monotona, los borrados nunca llegan al dispositivo y el
--    registro revive en el proximo push. Aqui van sync_version (secuencia global),
--    deleted_at en todo lo sincronizable, y fnc_sync_changes devolviendo cambios Y
--    eliminados en el mismo payload.
--
-- CONFLICTOS: last-write-wins por updated_at del cliente, devolviendo el estado ganador
-- para que el dispositivo se alinee. Sin merge por campo: con un usuario por device,
-- inventar CRDTs seria complejidad sin caso de uso.
-- =====================================================================================

BEGIN;

SET LOCAL client_min_messages = WARNING;

DO $$
BEGIN
    IF to_regclass('public.tenant') IS NULL OR to_regclass('geo.place') IS NULL THEN
        RAISE EXCEPTION 'Aplica primero 001_vehitrack.sql y 002_geocoding.sql';
    END IF;
END $$;

-- =====================================================================================
-- 1. CONFIGURACION Y DICCIONARIOS
-- =====================================================================================

INSERT INTO public.app_setting (key, value, description) VALUES
  ('tenant.personal_max_device', '3',   'Dispositivos por tenant personal. Fleet y reseller lo definen por tenant.'),
  ('sync.max_batch_items',       '500', 'Items maximos en un POST /v1/sync/push.'),
  ('sync.max_changes_per_entity','500', 'Filas por entidad en un delta. Si se alcanza, el cliente vuelve a pedir.'),
  ('fuel.price_cop_per_liter',   '16000','Precio por defecto si el device no configuro el suyo.'),
  ('fuel.km_per_liter',          '12',  'Rendimiento por defecto si el device no configuro el suyo.'),
  ('geofence.default_cooldown_s','120', 'Espera minima entre dos disparos de la misma geocerca.')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.favorite_kind (
    id text PRIMARY KEY, name text NOT NULL, icon text, is_unique_per_device boolean NOT NULL,
    sort_order smallint NOT NULL);
COMMENT ON COLUMN public.favorite_kind.is_unique_per_device IS
    'Casa y trabajo hay una sola. Cliente y personalizado, las que sean. Lo valida prc_upsert_favorite_place.';
INSERT INTO public.favorite_kind (id, name, icon, is_unique_per_device, sort_order) VALUES
  ('home','Casa','home',true,1),
  ('work','Trabajo','briefcase',true,2),
  ('client','Cliente','user',false,3),
  ('custom','Personalizado','star',false,9)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.poi_category (
    id             text PRIMARY KEY,
    name           text NOT NULL,
    icon           text,
    color_hex      text,
    osm_tag_filter text,
    is_syncable    boolean NOT NULL DEFAULT true,
    sort_order     smallint NOT NULL
);
COMMENT ON COLUMN public.poi_category.osm_tag_filter IS
    'Filtro con el que el import mensual llena los POI publicos. Vacio = categoria solo del usuario.';
INSERT INTO public.poi_category (id, name, icon, color_hex, osm_tag_filter, is_syncable, sort_order) VALUES
  ('fuel_station','Estacion de servicio','fuel','#F59E0B','amenity=fuel',true,1),
  ('workshop','Taller','wrench','#6366F1','shop=car_repair',true,2),
  ('parking','Parqueadero','parking','#0EA5E9','amenity=parking',true,3),
  ('toll','Peaje','coin','#EF4444','barrier=toll_booth',true,4),
  ('hospital','Hospital','cross','#DC2626','amenity=hospital',true,5),
  ('client_site','Sede de cliente','building','#10B981',NULL,true,6),
  ('other','Otro','pin','#64748B',NULL,true,9)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.geofence_shape (
    id text PRIMARY KEY, name text NOT NULL, geometry_type text NOT NULL);
INSERT INTO public.geofence_shape (id, name, geometry_type) VALUES
  ('circle','Circulo con radio','ST_Point'),
  ('polygon','Poligono','ST_Polygon')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.geofence_trigger (
    id text PRIMARY KEY, name text NOT NULL);
INSERT INTO public.geofence_trigger (id, name) VALUES
  ('enter','Al entrar'),('exit','Al salir'),('both','Al entrar y salir')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.sync_entity (
    id text PRIMARY KEY, name text NOT NULL, table_name text NOT NULL, sort_order smallint NOT NULL);
COMMENT ON TABLE public.sync_entity IS
    'Entidades sincronizables. fnc_sync_changes y prc_sync_push validan contra esta tabla en
     vez de contra un IN (...) escondido en el codigo.';
INSERT INTO public.sync_entity (id, name, table_name, sort_order) VALUES
  ('favorite_place','Lugares favoritos','favorite_place',1),
  ('place_user','POI propios','place_user',2),
  ('geofence','Geocercas','geofence',3),
  ('device_setting','Ajustes del dispositivo','device_setting',4)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.sync_operation (
    id text PRIMARY KEY, name text NOT NULL);
INSERT INTO public.sync_operation (id, name) VALUES
  ('upsert','Crear o actualizar'),('delete','Borrado logico')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================================
-- 2. VERSION DE SYNC Y TABLAS DEL USUARIO
-- =====================================================================================

CREATE SEQUENCE IF NOT EXISTS device.seq_sync_version AS bigint START 1;
COMMENT ON SEQUENCE device.seq_sync_version IS
    'Version monotona GLOBAL de cambios. Global y no por device: un valor mas alto siempre
     significa mas nuevo, sin comparar relojes de dispositivos distintos.';

CREATE TABLE IF NOT EXISTS device.favorite_place (
    id                uuid        PRIMARY KEY,
    tenant_id         uuid        NOT NULL REFERENCES public.tenant(id),
    device_id         uuid        NOT NULL REFERENCES device.device(id),
    account_id        uuid        REFERENCES device.account(id),
    favorite_kind_id  text        NOT NULL REFERENCES public.favorite_kind(id) DEFAULT 'custom',
    label             text        NOT NULL,
    description       text,
    icon              text,
    color_hex         text,
    place_id          bigint      REFERENCES geo.place(id) ON DELETE SET NULL,
    geom              geometry(Point, 4326) NOT NULL,
    visit_count       int         NOT NULL DEFAULT 0,
    last_visited_at   timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    deleted_at        timestamptz,
    sync_version      bigint      NOT NULL DEFAULT nextval('device.seq_sync_version')
);
COMMENT ON COLUMN device.favorite_place.id IS
    'uuid v7 generado por la APP. Sin esto no hay offline-first: crear un favorito sin red
     no puede depender de que el servidor asigne el id.';
-- NO hay indice unico parcial para "una sola casa por device": el predicado tendria que
-- consultar public.favorite_kind y Postgres no admite subconsultas en un indice. La
-- alternativa seria quemar ('home','work') como literales, que es justo el valor cerrado
-- sin diccionario que este modelo prohibe. La unicidad la valida prc_upsert_favorite_place
-- (VT044). Contrapartida asumida: hay que pasar SIEMPRE por el procedimiento.

CREATE TABLE IF NOT EXISTS device.place_user (
    id              uuid        PRIMARY KEY,
    tenant_id       uuid        NOT NULL REFERENCES public.tenant(id),
    device_id       uuid        NOT NULL REFERENCES device.device(id),
    account_id      uuid        REFERENCES device.account(id),
    poi_category_id text        NOT NULL REFERENCES public.poi_category(id) DEFAULT 'other',
    name            text        NOT NULL,
    description     text,
    geom            geometry(Point, 4326) NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    deleted_at      timestamptz,
    sync_version    bigint      NOT NULL DEFAULT nextval('device.seq_sync_version')
);
COMMENT ON TABLE device.place_user IS
    'POI del usuario. NUNCA lo toca el import mensual de OSM; los POI publicos van en su
     propia tabla y se reemplazan enteros. Si se mezclaran, el proximo import borra clientes.';

CREATE TABLE IF NOT EXISTS device.geofence (
    id                  uuid        PRIMARY KEY,
    tenant_id           uuid        NOT NULL REFERENCES public.tenant(id),
    device_id           uuid        NOT NULL REFERENCES device.device(id),
    account_id          uuid        REFERENCES device.account(id),
    name                text        NOT NULL,
    geofence_shape_id   text        NOT NULL REFERENCES public.geofence_shape(id) DEFAULT 'circle',
    geofence_trigger_id text        NOT NULL REFERENCES public.geofence_trigger(id) DEFAULT 'both',
    geom                geometry(Geometry, 4326) NOT NULL,
    radius_m            int,
    cooldown_s          int         NOT NULL,
    is_active           boolean     NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    sync_version        bigint      NOT NULL DEFAULT nextval('device.seq_sync_version'),
    CONSTRAINT ck_geofence_circle_radius
        CHECK (geofence_shape_id <> 'circle' OR radius_m IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS device.device_setting (
    id           bigint      GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    tenant_id    uuid        NOT NULL REFERENCES public.tenant(id),
    device_id    uuid        NOT NULL REFERENCES device.device(id),
    key          text        NOT NULL,
    value        jsonb       NOT NULL,
    updated_at   timestamptz NOT NULL DEFAULT now(),
    deleted_at   timestamptz,
    sync_version bigint      NOT NULL DEFAULT nextval('device.seq_sync_version'),
    UNIQUE (device_id, key)
);
COMMENT ON TABLE device.device_setting IS
    'Ajustes del usuario. El precio de combustible y el rendimiento salen de aqui: por eso
     el costo del viaje puede variar entre dispositivos del mismo tenant.';

CREATE TABLE IF NOT EXISTS device.geofence_event (
    id          bigint      GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    tenant_id   uuid        NOT NULL REFERENCES public.tenant(id),
    device_id   uuid        NOT NULL REFERENCES device.device(id),
    geofence_id uuid        NOT NULL REFERENCES device.geofence(id) ON DELETE CASCADE,
    trip_id     uuid        REFERENCES tracking.trip(id),
    trigger_id  text        NOT NULL REFERENCES public.geofence_trigger(id),
    geom        geometry(Point, 4326),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (geofence_id, occurred_at)
);
COMMENT ON TABLE device.geofence_event IS
    'Evento reportado por la APP: la evaluacion en vivo es del dispositivo, no del servidor.
     El servidor no puede garantizar latencia ni conectividad en la via.';

CREATE INDEX IF NOT EXISTS ix_favorite_device ON device.favorite_place (device_id, sync_version);
CREATE INDEX IF NOT EXISTS ix_place_user_device ON device.place_user (device_id, sync_version);
CREATE INDEX IF NOT EXISTS ix_geofence_device ON device.geofence (device_id, sync_version);
CREATE INDEX IF NOT EXISTS ix_setting_device ON device.device_setting (device_id, sync_version);
CREATE INDEX IF NOT EXISTS gist_favorite_geom ON device.favorite_place USING gist (geom);
CREATE INDEX IF NOT EXISTS gist_place_user_geom ON device.place_user USING gist (geom);
CREATE INDEX IF NOT EXISTS gist_geofence_geom ON device.geofence USING gist (geom) WHERE is_active;
CREATE INDEX IF NOT EXISTS ix_geofence_event_device
    ON device.geofence_event (device_id, occurred_at DESC);

-- RLS con la misma politica del 001
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['device.favorite_place','device.place_user','device.geofence',
                             'device.device_setting','device.geofence_event']
    LOOP
        EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('DROP POLICY IF EXISTS pol_tenant_isolation ON %s', t);
        EXECUTE format(
            'CREATE POLICY pol_tenant_isolation ON %s
                 USING (tenant_id = public.fnc_current_tenant())
                 WITH CHECK (tenant_id = public.fnc_current_tenant())', t);
    END LOOP;
END $$;

-- =====================================================================================
-- 3. PROVISION SIN CONTEXTO DE TENANT
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_provision_personal_tenant
-- Proposito : Alta de un usuario personal nuevo: crea su tenant y su device en una sola
--             transaccion. Es el unico camino de escritura que puede correr SIN
--             app.tenant_id seteado, porque es el momento exacto en que el tenant aun no
--             existe. Idempotente por install_id.
-- Parametros: p_install_id, p_device_id, p_platform, p_os_version, p_app_version, p_model
--             p_result INOUT {tenant_id, device_id, created}
-- Errores   : VT040 install_id vacio
-- Nota      : SECURITY DEFINER con search_path fijado (sin eso, un rol que pueda crear
--             objetos en el search_path ejecuta codigo como el dueno). Es el UNICO DEFINER
--             de escritura del sistema: todo lo demas pasa por RLS.
--             El ms lo expone SOLO en POST /v1/devices/register y con rate limit por IP.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_provision_personal_tenant(
    p_install_id  text,
    p_device_id   uuid,
    p_platform    text DEFAULT NULL,
    p_os_version  text DEFAULT NULL,
    p_app_version text DEFAULT NULL,
    p_model       text DEFAULT NULL,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_tenant uuid; v_device uuid; v_slug text; v_max int;
BEGIN
    IF p_install_id IS NULL OR btrim(p_install_id) = '' THEN
        RAISE EXCEPTION 'install_id requerido' USING ERRCODE = 'VT040';
    END IF;

    SELECT d.id, d.tenant_id INTO v_device, v_tenant
      FROM device.device d WHERE d.install_id = p_install_id;

    IF FOUND THEN
        UPDATE device.device
           SET last_seen_at = now(),
               app_version  = COALESCE(p_app_version, app_version),
               os_version   = COALESCE(p_os_version,  os_version),
               model        = COALESCE(p_model,       model)
         WHERE id = v_device;
        p_result := jsonb_build_object('tenant_id', v_tenant, 'device_id', v_device, 'created', false);
        RETURN;
    END IF;

    v_max    := public.fnc_setting_num('tenant.personal_max_device')::int;
    v_tenant := gen_random_uuid();
    v_slug   := 'p-' || left(replace(v_tenant::text, '-', ''), 12);

    INSERT INTO public.tenant (id, slug, name, tenant_kind_id, max_device)
    VALUES (v_tenant, v_slug, 'Personal ' || v_slug, 'personal', v_max);

    INSERT INTO device.device (id, tenant_id, install_id, platform, os_version, app_version,
                               model, registered_at, last_seen_at)
    VALUES (p_device_id, v_tenant, p_install_id, p_platform, p_os_version, p_app_version,
            p_model, now(), now());

    p_result := jsonb_build_object('tenant_id', v_tenant, 'device_id', p_device_id, 'created', true);
END $$;

-- =====================================================================================
-- 4. ESCRITURA DE DATOS DEL USUARIO
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_upsert_favorite_place
-- Proposito : Crea o actualiza un favorito. El id lo trae la app (uuid v7).
-- Parametros: p_id, p_device_id, p_label, p_lat, p_lon, p_kind, p_description, p_icon,
--             p_color_hex, p_place_id, p_client_updated_at, p_result INOUT
-- Errores   : VT041 device no visible en el tenant activo · VT042 coordenadas invalidas
--             VT043 favorite_kind invalido · VT044 ya existe casa/trabajo
-- Nota      : last-write-wins. Si el updated_at del cliente es MAS VIEJO que el guardado,
--             no se aplica: se devuelve applied=false con el estado ganador. Es el servidor
--             diciendole al dispositivo "estas atrasado, sincroniza".
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_upsert_favorite_place(
    p_id                uuid,
    p_device_id         uuid,
    p_label             text,
    p_lat               double precision,
    p_lon               double precision,
    p_kind              text DEFAULT 'custom',
    p_description       text DEFAULT NULL,
    p_icon              text DEFAULT NULL,
    p_color_hex         text DEFAULT NULL,
    p_place_id          bigint DEFAULT NULL,
    p_client_updated_at timestamptz DEFAULT NULL,
    INOUT p_result      jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_tenant uuid; v_account uuid; v_current timestamptz;
    v_unique boolean; v_version bigint; v_created boolean;
BEGIN
    SELECT tenant_id, account_id INTO v_tenant, v_account
      FROM device.device WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device % no visible en el tenant activo', p_device_id USING ERRCODE = 'VT041';
    END IF;
    IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
        RAISE EXCEPTION 'coordenadas invalidas (%, %)', p_lat, p_lon USING ERRCODE = 'VT042';
    END IF;

    SELECT is_unique_per_device INTO v_unique FROM public.favorite_kind WHERE id = p_kind;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'favorite_kind % invalido', p_kind USING ERRCODE = 'VT043';
    END IF;
    IF v_unique AND EXISTS (
        SELECT 1 FROM device.favorite_place
         WHERE device_id = p_device_id AND favorite_kind_id = p_kind
           AND deleted_at IS NULL AND id <> p_id)
    THEN
        RAISE EXCEPTION 'ya existe un favorito % para este device', p_kind USING ERRCODE = 'VT044';
    END IF;

    SELECT updated_at INTO v_current FROM device.favorite_place WHERE id = p_id;
    IF FOUND AND p_client_updated_at IS NOT NULL AND p_client_updated_at < v_current THEN
        SELECT sync_version INTO v_version FROM device.favorite_place WHERE id = p_id;
        p_result := jsonb_build_object('id', p_id, 'applied', false, 'reason', 'stale_client_update',
                                       'server_updated_at', v_current, 'sync_version', v_version);
        RETURN;
    END IF;

    INSERT INTO device.favorite_place (
        id, tenant_id, device_id, account_id, favorite_kind_id, label, description, icon,
        color_hex, place_id, geom, updated_at, deleted_at, sync_version)
    VALUES (p_id, v_tenant, p_device_id, v_account, p_kind, p_label, p_description, p_icon,
            p_color_hex, p_place_id, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326),
            COALESCE(p_client_updated_at, now()), NULL, nextval('device.seq_sync_version'))
    ON CONFLICT (id) DO UPDATE SET
        favorite_kind_id = EXCLUDED.favorite_kind_id,
        label            = EXCLUDED.label,
        description      = EXCLUDED.description,
        icon             = EXCLUDED.icon,
        color_hex        = EXCLUDED.color_hex,
        place_id         = COALESCE(EXCLUDED.place_id, favorite_place.place_id),
        geom             = EXCLUDED.geom,
        updated_at       = EXCLUDED.updated_at,
        deleted_at       = NULL,
        sync_version     = nextval('device.seq_sync_version')
    RETURNING (xmax = 0), sync_version INTO v_created, v_version;

    p_result := jsonb_build_object('id', p_id, 'applied', true,
                                   'created', v_created, 'sync_version', v_version);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_upsert_place_user
-- Proposito : Crea o actualiza un POI propio del usuario (cliente, taller, parqueadero).
-- Parametros: p_id, p_device_id, p_name, p_lat, p_lon, p_category_id, p_description,
--             p_client_updated_at, p_result INOUT
-- Errores   : VT041 device no visible · VT042 coordenadas invalidas · VT045 categoria invalida
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_upsert_place_user(
    p_id                uuid,
    p_device_id         uuid,
    p_name              text,
    p_lat               double precision,
    p_lon               double precision,
    p_category_id       text DEFAULT 'other',
    p_description       text DEFAULT NULL,
    p_client_updated_at timestamptz DEFAULT NULL,
    INOUT p_result      jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_tenant uuid; v_account uuid; v_version bigint; v_created boolean;
BEGIN
    SELECT tenant_id, account_id INTO v_tenant, v_account FROM device.device WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device % no visible en el tenant activo', p_device_id USING ERRCODE = 'VT041';
    END IF;
    IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
        RAISE EXCEPTION 'coordenadas invalidas' USING ERRCODE = 'VT042';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.poi_category WHERE id = p_category_id) THEN
        RAISE EXCEPTION 'poi_category % invalida', p_category_id USING ERRCODE = 'VT045';
    END IF;

    INSERT INTO device.place_user (id, tenant_id, device_id, account_id, poi_category_id,
                                   name, description, geom, updated_at, deleted_at, sync_version)
    VALUES (p_id, v_tenant, p_device_id, v_account, p_category_id, p_name, p_description,
            ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326),
            COALESCE(p_client_updated_at, now()), NULL, nextval('device.seq_sync_version'))
    ON CONFLICT (id) DO UPDATE SET
        poi_category_id = EXCLUDED.poi_category_id, name = EXCLUDED.name,
        description = EXCLUDED.description, geom = EXCLUDED.geom,
        updated_at = EXCLUDED.updated_at, deleted_at = NULL,
        sync_version = nextval('device.seq_sync_version')
    RETURNING (xmax = 0), sync_version INTO v_created, v_version;

    p_result := jsonb_build_object('id', p_id, 'applied', true,
                                   'created', v_created, 'sync_version', v_version);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_upsert_geofence
-- Proposito : Crea o actualiza una geocerca (punto + radio, o poligono en WKT).
-- Parametros: p_id, p_device_id, p_name, p_geom_wkt, p_shape, p_radius_m, p_trigger,
--             p_cooldown_s, p_is_active, p_client_updated_at, p_result INOUT
-- Errores   : VT041 device no visible · VT046 shape o trigger invalido
--             VT047 geometria incompatible con el shape
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_upsert_geofence(
    p_id                uuid,
    p_device_id         uuid,
    p_name              text,
    p_geom_wkt          text,
    p_shape             text DEFAULT 'circle',
    p_radius_m          int  DEFAULT NULL,
    p_trigger           text DEFAULT 'both',
    p_cooldown_s        int  DEFAULT NULL,
    p_is_active         boolean DEFAULT true,
    p_client_updated_at timestamptz DEFAULT NULL,
    INOUT p_result      jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_tenant uuid; v_account uuid; v_geom geometry; v_expected text;
    v_cool int; v_version bigint; v_created boolean;
BEGIN
    SELECT tenant_id, account_id INTO v_tenant, v_account FROM device.device WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device % no visible en el tenant activo', p_device_id USING ERRCODE = 'VT041';
    END IF;

    SELECT geometry_type INTO v_expected FROM public.geofence_shape WHERE id = p_shape;
    IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM public.geofence_trigger WHERE id = p_trigger) THEN
        RAISE EXCEPTION 'shape % o trigger % invalido', p_shape, p_trigger USING ERRCODE = 'VT046';
    END IF;

    v_geom := ST_SetSRID(ST_GeomFromText(p_geom_wkt), 4326);
    IF ST_GeometryType(v_geom) <> v_expected THEN
        RAISE EXCEPTION 'geometria % incompatible con shape % (esperada %)',
            ST_GeometryType(v_geom), p_shape, v_expected USING ERRCODE = 'VT047';
    END IF;

    v_cool := COALESCE(p_cooldown_s, public.fnc_setting_num('geofence.default_cooldown_s')::int);

    INSERT INTO device.geofence (id, tenant_id, device_id, account_id, name,
                                 geofence_shape_id, geofence_trigger_id, geom, radius_m,
                                 cooldown_s, is_active, updated_at, deleted_at, sync_version)
    VALUES (p_id, v_tenant, p_device_id, v_account, p_name, p_shape, p_trigger, v_geom,
            p_radius_m, v_cool, p_is_active,
            COALESCE(p_client_updated_at, now()), NULL, nextval('device.seq_sync_version'))
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name, geofence_shape_id = EXCLUDED.geofence_shape_id,
        geofence_trigger_id = EXCLUDED.geofence_trigger_id, geom = EXCLUDED.geom,
        radius_m = EXCLUDED.radius_m, cooldown_s = EXCLUDED.cooldown_s,
        is_active = EXCLUDED.is_active, updated_at = EXCLUDED.updated_at,
        deleted_at = NULL, sync_version = nextval('device.seq_sync_version')
    RETURNING (xmax = 0), sync_version INTO v_created, v_version;

    p_result := jsonb_build_object('id', p_id, 'applied', true,
                                   'created', v_created, 'sync_version', v_version);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_upsert_setting
-- Proposito : Guarda un ajuste del dispositivo (precio de combustible, rendimiento,
--             umbral de alerta, tema).
-- Parametros: p_device_id, p_key, p_value, p_result INOUT
-- Errores   : VT041 device no visible
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_upsert_setting(
    p_device_id uuid, p_key text, p_value jsonb, INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_tenant uuid; v_version bigint;
BEGIN
    SELECT tenant_id INTO v_tenant FROM device.device WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device % no visible en el tenant activo', p_device_id USING ERRCODE = 'VT041';
    END IF;

    INSERT INTO device.device_setting (tenant_id, device_id, key, value, updated_at, deleted_at, sync_version)
    VALUES (v_tenant, p_device_id, p_key, p_value, now(), NULL, nextval('device.seq_sync_version'))
    ON CONFLICT (device_id, key) DO UPDATE SET
        value = EXCLUDED.value, updated_at = now(), deleted_at = NULL,
        sync_version = nextval('device.seq_sync_version')
    RETURNING sync_version INTO v_version;

    p_result := jsonb_build_object('key', p_key, 'applied', true, 'sync_version', v_version);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_soft_delete
-- Proposito : Borrado logico de una entidad sincronizable. NUNCA se hace DELETE: un
--             borrado duro no viaja en el delta y el registro revive en el proximo push.
--             Es el bug clasico de todo motor de sync.
-- Parametros: p_entity (public.sync_entity), p_id, p_device_id, p_result INOUT
-- Errores   : VT048 entidad no soportada · VT049 registro inexistente o ya eliminado
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_soft_delete(
    p_entity text, p_id uuid, p_device_id uuid, INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_table text; v_version bigint;
BEGIN
    SELECT table_name INTO v_table FROM public.sync_entity WHERE id = p_entity;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'sync_entity % no soportada', p_entity USING ERRCODE = 'VT048';
    END IF;

    EXECUTE format(
        'UPDATE device.%I SET deleted_at = now(), updated_at = now(),
                sync_version = nextval(''device.seq_sync_version'')
          WHERE id = $1 AND device_id = $2 AND deleted_at IS NULL
        RETURNING sync_version', v_table)
    INTO v_version USING p_id, p_device_id;

    IF v_version IS NULL THEN
        RAISE EXCEPTION '% % inexistente o ya eliminado', p_entity, p_id USING ERRCODE = 'VT049';
    END IF;

    p_result := jsonb_build_object('id', p_id, 'deleted', true, 'sync_version', v_version);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_record_geofence_event
-- Proposito : Registra un evento de geocerca que la APP evaluo en el dispositivo.
-- Parametros: p_device_id, p_geofence_id, p_trigger, p_lat, p_lon, p_occurred_at, p_trip_id
--             p_result INOUT {recorded, duplicate}
-- Errores   : VT041 device no visible · VT046 trigger invalido
-- Nota      : idempotente por (geofence_id, occurred_at): la app va a reenviar la cola
--             offline y eso es lo esperado, no una anomalia.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_record_geofence_event(
    p_device_id   uuid,
    p_geofence_id uuid,
    p_trigger     text,
    p_lat         double precision,
    p_lon         double precision,
    p_occurred_at timestamptz,
    p_trip_id     uuid DEFAULT NULL,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_tenant uuid; v_new boolean;
BEGIN
    SELECT tenant_id INTO v_tenant FROM device.device WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device % no visible en el tenant activo', p_device_id USING ERRCODE = 'VT041';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.geofence_trigger WHERE id = p_trigger) THEN
        RAISE EXCEPTION 'trigger % invalido', p_trigger USING ERRCODE = 'VT046';
    END IF;

    INSERT INTO device.geofence_event (tenant_id, device_id, geofence_id, trip_id,
                                       trigger_id, geom, occurred_at)
    VALUES (v_tenant, p_device_id, p_geofence_id, p_trip_id, p_trigger,
            ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326), p_occurred_at)
    ON CONFLICT (geofence_id, occurred_at) DO NOTHING
    RETURNING true INTO v_new;

    p_result := jsonb_build_object('recorded', COALESCE(v_new, false),
                                   'duplicate', v_new IS NULL);
END $$;

-- =====================================================================================
-- 5. LECTURA Y SYNC
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.fnc_setting_of_device
-- Proposito : Valor numerico de un ajuste, con respaldo en public.app_setting. Es lo que
--             hace que el costo del viaje use el precio real del usuario.
-- Parametros: p_device_id, p_key
-- Retorna   : numeric
-- Errores   : VT010 si la clave tampoco existe en app_setting (heredado, correcto)
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION device.fnc_setting_of_device(p_device_id uuid, p_key text)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT COALESCE(
        (SELECT (value #>> '{}')::numeric FROM device.device_setting
          WHERE device_id = p_device_id AND key = p_key AND deleted_at IS NULL),
        public.fnc_setting_num(p_key));
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.fnc_list_favorite_place
-- Proposito : Favoritos vigentes de un dispositivo. Responde GET /v1/favorites?device_id=.
-- Parametros: p_device_id, p_include_deleted
-- Retorna   : SETOF favoritos
-- Errores   : ninguno
-- Nota      : el aislamiento lo pone RLS, no este WHERE. Si algun dia el scope pasa a ser
--             por cuenta, cambia aqui y el contrato HTTP no se entera.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION device.fnc_list_favorite_place(
    p_device_id uuid, p_include_deleted boolean DEFAULT false
) RETURNS TABLE (
    id uuid, favorite_kind_id text, label text, description text, icon text, color_hex text,
    lat double precision, lon double precision, place_id bigint,
    visit_count int, last_visited_at timestamptz,
    updated_at timestamptz, deleted_at timestamptz, sync_version bigint
) LANGUAGE sql STABLE AS $$
    SELECT f.id, f.favorite_kind_id, f.label, f.description,
           COALESCE(f.icon, k.icon), f.color_hex,
           ST_Y(f.geom), ST_X(f.geom), f.place_id,
           f.visit_count, f.last_visited_at, f.updated_at, f.deleted_at, f.sync_version
    FROM device.favorite_place f
    JOIN public.favorite_kind k ON k.id = f.favorite_kind_id
    WHERE f.device_id = p_device_id
      AND (p_include_deleted OR f.deleted_at IS NULL)
    ORDER BY k.sort_order, f.label;
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.fnc_sync_changes
-- Proposito : Delta para /v1/sync/changes: cambios Y eliminados desde una version, con la
--             siguiente version a guardar en el cliente.
-- Parametros: p_device_id, p_entities (NULL = todas), p_since_version, p_limit
-- Retorna   : jsonb {next_version, has_more, entities:{<entidad>:{changes:[],deleted:[]}}}
-- Errores   : VT048 entidad no soportada
-- Nota      : el delta esta paginado POR VERSION, no por offset. Si has_more es true, el
--             cliente vuelve a pedir con el next_version recibido. Documentar esto en el
--             contrato HTTP o alguien va a asumir que un delta siempre viene completo.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION device.fnc_sync_changes(
    p_device_id     uuid,
    p_entities      text[] DEFAULT NULL,
    p_since_version bigint DEFAULT 0,
    p_limit         int    DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    e text; v_table text;
    v_out jsonb := '{}'::jsonb;
    v_changes jsonb; v_deleted jsonb; v_max bigint; v_n int;
    v_next bigint := COALESCE(p_since_version, 0);
    v_more boolean := false;
    v_cap  int := COALESCE(p_limit, public.fnc_setting_num('sync.max_changes_per_entity')::int);
    v_list text[] := COALESCE(p_entities, ARRAY(SELECT id FROM public.sync_entity ORDER BY sort_order));
BEGIN
    FOREACH e IN ARRAY v_list LOOP
        SELECT table_name INTO v_table FROM public.sync_entity WHERE id = e;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'sync_entity % no soportada', e USING ERRCODE = 'VT048';
        END IF;

        EXECUTE format($f$
            WITH win AS (
                SELECT * FROM device.%I
                 WHERE device_id = $1 AND sync_version > $2
                 ORDER BY sync_version LIMIT $3)
            SELECT COALESCE(jsonb_agg(
                     (to_jsonb(w) - 'geom' - 'tenant_id' - 'account_id')
                     || CASE WHEN to_jsonb(w) ? 'geom'
                             -- geom se extrae del jsonb (WKB hex) y NO como columna w.geom:
                             -- device_setting no tiene geom y "w.geom" haría fallar el parseo
                             -- de la consulta entera para esa entidad.
                             THEN jsonb_build_object('geom',
                                    ST_AsGeoJSON((to_jsonb(w) ->> 'geom')::geometry)::jsonb)
                             ELSE '{}'::jsonb END)
                     FILTER (WHERE w.deleted_at IS NULL), '[]'::jsonb),
                   COALESCE(jsonb_agg(w.id) FILTER (WHERE w.deleted_at IS NOT NULL), '[]'::jsonb),
                   COALESCE(max(w.sync_version), $2),
                   count(*)
            FROM win w $f$, v_table)
        INTO v_changes, v_deleted, v_max, v_n
        USING p_device_id, COALESCE(p_since_version, 0), v_cap;

        v_out  := v_out || jsonb_build_object(e, jsonb_build_object(
                    'changes', v_changes, 'deleted', v_deleted));
        v_next := GREATEST(v_next, v_max);
        IF v_n >= v_cap THEN v_more := true; END IF;
    END LOOP;

    RETURN jsonb_build_object('next_version', v_next, 'has_more', v_more, 'entities', v_out);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_sync_push
-- Proposito : Aplica en lote los cambios locales del dispositivo (/v1/sync/push). Cada item
--             se enruta al prc_ correspondiente; un item malo NO aborta el lote, se reporta.
-- Parametros: p_device_id, p_items jsonb [{entity, op, id, data{}, updated_at}]
--             p_result INOUT {applied, skipped, failed[], next_version}
-- Errores   : VT050 payload mal formado · VT051 lote demasiado grande
-- Nota      : idempotente por (entity, id, updated_at). Reenviar el mismo lote no cambia
--             nada — y la app VA a reenviar: es el comportamiento esperado de una cola
--             offline, no una anomalia que haya que castigar con un 409.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_sync_push(
    p_device_id uuid, p_items jsonb, INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    it jsonb; d jsonb; v_sub jsonb;
    v_applied int := 0; v_skipped int := 0; v_failed jsonb := '[]'::jsonb;
    v_max int := public.fnc_setting_num('sync.max_batch_items')::int;
    v_next bigint;
BEGIN
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'p_items debe ser un array' USING ERRCODE = 'VT050';
    END IF;
    IF jsonb_array_length(p_items) > v_max THEN
        RAISE EXCEPTION 'lote de % items excede el maximo de %', jsonb_array_length(p_items), v_max
            USING ERRCODE = 'VT051';
    END IF;

    FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        d := COALESCE(it -> 'data', '{}'::jsonb);
        BEGIN
            IF (it ->> 'op') = 'delete' THEN
                CALL device.prc_soft_delete(it ->> 'entity', (it ->> 'id')::uuid, p_device_id, v_sub);
            ELSIF (it ->> 'entity') = 'favorite_place' THEN
                CALL device.prc_upsert_favorite_place(
                    (it ->> 'id')::uuid, p_device_id, d ->> 'label',
                    (d ->> 'lat')::double precision, (d ->> 'lon')::double precision,
                    COALESCE(d ->> 'favorite_kind_id','custom'), d ->> 'description',
                    d ->> 'icon', d ->> 'color_hex', NULLIF(d ->> 'place_id','')::bigint,
                    (it ->> 'updated_at')::timestamptz, v_sub);
            ELSIF (it ->> 'entity') = 'place_user' THEN
                CALL device.prc_upsert_place_user(
                    (it ->> 'id')::uuid, p_device_id, d ->> 'name',
                    (d ->> 'lat')::double precision, (d ->> 'lon')::double precision,
                    COALESCE(d ->> 'poi_category_id','other'), d ->> 'description',
                    (it ->> 'updated_at')::timestamptz, v_sub);
            ELSIF (it ->> 'entity') = 'geofence' THEN
                CALL device.prc_upsert_geofence(
                    (it ->> 'id')::uuid, p_device_id, d ->> 'name', d ->> 'geom_wkt',
                    COALESCE(d ->> 'geofence_shape_id','circle'), NULLIF(d ->> 'radius_m','')::int,
                    COALESCE(d ->> 'geofence_trigger_id','both'), NULLIF(d ->> 'cooldown_s','')::int,
                    COALESCE((d ->> 'is_active')::boolean, true),
                    (it ->> 'updated_at')::timestamptz, v_sub);
            ELSIF (it ->> 'entity') = 'device_setting' THEN
                CALL device.prc_upsert_setting(p_device_id, d ->> 'key', d -> 'value', v_sub);
            ELSE
                RAISE EXCEPTION 'sync_entity % no soportada', it ->> 'entity' USING ERRCODE = 'VT048';
            END IF;

            IF COALESCE((v_sub ->> 'applied')::boolean, true) THEN
                v_applied := v_applied + 1;
            ELSE
                v_skipped := v_skipped + 1;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_failed := v_failed || jsonb_build_object(
                'entity', it ->> 'entity', 'id', it ->> 'id',
                'sqlstate', SQLSTATE, 'message', SQLERRM);
        END;
    END LOOP;

    SELECT last_value INTO v_next FROM device.seq_sync_version;

    p_result := jsonb_build_object(
        'applied', v_applied, 'skipped', v_skipped, 'failed', v_failed,
        'next_version', v_next);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.fnc_evaluate_geofence
-- Proposito : Evalua un lote de puntos contra las geocercas activas del dispositivo. Sirve
--             para AUDITORIA y reproceso, no para tiempo real: en la via manda la
--             evaluacion local de la app, porque el servidor no puede garantizar latencia
--             ni conectividad.
-- Parametros: p_device_id, p_points jsonb [{lat,lon,ts}]
-- Retorna   : SETOF (geofence_id, name, trigger_id, occurred_at)
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION device.fnc_evaluate_geofence(p_device_id uuid, p_points jsonb)
RETURNS TABLE (geofence_id uuid, name text, trigger_id text, occurred_at timestamptz)
LANGUAGE sql STABLE AS $$
    WITH pts AS (
        SELECT ST_SetSRID(ST_MakePoint(p.lon, p.lat), 4326) AS geom, p.ts,
               row_number() OVER (ORDER BY p.ts) AS seq
        FROM jsonb_to_recordset(COALESCE(p_points,'[]'::jsonb))
             AS p(lat double precision, lon double precision, ts timestamptz)),
    hits AS (
        SELECT g.id, g.name, g.geofence_trigger_id AS trig, p.ts, p.seq,
               CASE WHEN g.geofence_shape_id = 'circle'
                    THEN ST_DWithin(g.geom::geography, p.geom::geography, g.radius_m)
                    ELSE ST_Contains(g.geom, p.geom) END AS inside
        FROM device.geofence g CROSS JOIN pts p
        WHERE g.device_id = p_device_id AND g.is_active AND g.deleted_at IS NULL),
    edges AS (
        SELECT h.*, lag(h.inside) OVER (PARTITION BY h.id ORDER BY h.seq) AS prev FROM hits h)
    SELECT e.id, e.name,
           CASE WHEN e.inside THEN 'enter' ELSE 'exit' END,
           e.ts
    FROM edges e
    WHERE e.prev IS NOT NULL AND e.inside <> e.prev
      AND (e.trig = 'both'
        OR (e.trig = 'enter' AND e.inside)
        OR (e.trig = 'exit'  AND NOT e.inside))
    ORDER BY e.ts;
$$;

-- =====================================================================================
-- 6. REGISTRO Y PERMISOS
-- =====================================================================================

INSERT INTO public.db_routine (schema_name, routine_name, routine_type, purpose, author, version, migration) VALUES
 ('device','prc_provision_personal_tenant','procedure','Alta de tenant personal + device (unico SECURITY DEFINER)','Lucho · Devitech','1.0.0','003_device_data.sql'),
 ('device','prc_upsert_favorite_place','procedure','Alta o actualizacion de favorito','Lucho · Devitech','1.0.0','003_device_data.sql'),
 ('device','prc_upsert_place_user','procedure','Alta o actualizacion de POI propio','Lucho · Devitech','1.0.0','003_device_data.sql'),
 ('device','prc_upsert_geofence','procedure','Alta o actualizacion de geocerca','Lucho · Devitech','1.0.0','003_device_data.sql'),
 ('device','prc_upsert_setting','procedure','Ajuste del dispositivo','Lucho · Devitech','1.0.0','003_device_data.sql'),
 ('device','prc_soft_delete','procedure','Borrado logico de entidad sincronizable','Lucho · Devitech','1.0.0','003_device_data.sql'),
 ('device','prc_record_geofence_event','procedure','Evento de geocerca evaluado por la app','Lucho · Devitech','1.0.0','003_device_data.sql'),
 ('device','fnc_setting_of_device','function','Ajuste numerico con respaldo en app_setting','Lucho · Devitech','1.0.0','003_device_data.sql'),
 ('device','fnc_list_favorite_place','function','Favoritos vigentes por device','Lucho · Devitech','1.0.0','003_device_data.sql'),
 ('device','fnc_sync_changes','function','Delta de sync con cambios y eliminados','Lucho · Devitech','1.0.0','003_device_data.sql'),
 ('device','prc_sync_push','procedure','Aplicacion en lote de cambios locales','Lucho · Devitech','1.0.0','003_device_data.sql'),
 ('device','fnc_evaluate_geofence','function','Evaluacion server-side de geocercas (auditoria)','Lucho · Devitech','1.0.0','003_device_data.sql')
ON CONFLICT (schema_name, routine_name) DO UPDATE SET
    purpose = EXCLUDED.purpose, author = EXCLUDED.author,
    version = EXCLUDED.version, migration = EXCLUDED.migration, updated_at = now();

GRANT SELECT ON
    public.favorite_kind, public.poi_category, public.geofence_shape,
    public.geofence_trigger, public.sync_entity, public.sync_operation,
    device.favorite_place, device.place_user, device.geofence,
    device.device_setting, device.geofence_event
TO vehitrack_app;

GRANT USAGE ON SEQUENCE device.seq_sync_version TO vehitrack_app;

GRANT EXECUTE ON FUNCTION
    device.fnc_list_favorite_place(uuid, boolean),
    device.fnc_sync_changes(uuid, text[], bigint, int),
    device.fnc_setting_of_device(uuid, text),
    device.fnc_evaluate_geofence(uuid, jsonb)
TO vehitrack_app;

GRANT EXECUTE ON PROCEDURE
    device.prc_provision_personal_tenant(text, uuid, text, text, text, text, jsonb),
    device.prc_upsert_favorite_place(uuid, uuid, text, double precision, double precision, text, text, text, text, bigint, timestamptz, jsonb),
    device.prc_upsert_place_user(uuid, uuid, text, double precision, double precision, text, text, timestamptz, jsonb),
    device.prc_upsert_geofence(uuid, uuid, text, text, text, int, text, int, boolean, timestamptz, jsonb),
    device.prc_upsert_setting(uuid, text, jsonb, jsonb),
    device.prc_soft_delete(text, uuid, uuid, jsonb),
    device.prc_record_geofence_event(uuid, uuid, text, double precision, double precision, timestamptz, uuid, jsonb),
    device.prc_sync_push(uuid, jsonb, jsonb)
TO vehitrack_app;

COMMIT;

-- =====================================================================================
-- 7. VERIFICACION
--
--   -- alta de usuario personal (SIN SET LOCAL: es el unico caso del sistema)
--   CALL device.prc_provision_personal_tenant('install-abc', gen_random_uuid(),
--        'android','10','1.4.0','YT9270', NULL);
--
--   -- de aqui en adelante, TODO va con el tenant seteado
--   BEGIN;
--     SET LOCAL app.tenant_id = '<tenant devuelto>';
--     CALL device.prc_upsert_favorite_place(gen_random_uuid(), '<device>', 'Casa',
--          10.9942, -74.7965, 'home', NULL, NULL, NULL, NULL, now(), NULL);
--     SELECT device.fnc_sync_changes('<device>', NULL, 0, NULL);
--   COMMIT;
--
-- LA PRUEBA QUE NO PUEDES SALTARTE (la del borrado):
--   crear favorito -> prc_soft_delete -> fnc_sync_changes desde version 0 debe traerlo en
--   'deleted', NO ausente. Si sale ausente, el dispositivo nunca se entera y el registro
--   revive en el proximo push.
--
-- LA OTRA (aislamiento), como rol vehitrack_app:
--   SET LOCAL app.tenant_id = '<A>'; SELECT count(*) FROM device.favorite_place;
--   SET LOCAL app.tenant_id = '<B>'; SELECT count(*) FROM device.favorite_place;
--   Numeros distintos. Iguales = RLS no esta activo y todo lo demas da lo mismo.
-- =====================================================================================
