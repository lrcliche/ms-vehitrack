-- =====================================================================================
-- VehiTrack · migrations/001_vehitrack.sql
-- MODELO COMPLETO Y UNIFICADO — multi-tenant desde la definicion, no por ALTER.
--
-- Reemplaza y consolida: 002_traffic.sql + 003_telemetry.sql + 004_tenant.sql.
-- Si ya corriste alguna de esas, NO corras esta sobre la misma base: es el baseline
-- para una base limpia.
--
-- Aplicar manualmente:  psql "$POSTGRES_DSN" -f migrations/001_vehitrack.sql
-- Requiere: PostgreSQL 17, PostGIS 3.4+.
-- Idempotente: se puede correr dos veces sin romper nada.
--
-- -------------------------------------------------------------------------------------
-- CONVENCIONES DE BD (aplican a TODA migracion de VehiTrack)
-- -------------------------------------------------------------------------------------
-- C1. Rutinas: FUNCTION -> fnc_<accion> · PROCEDURE -> prc_<accion>.
--     Criterio: se usa dentro de un SELECT u otra rutina -> FUNCTION.
--               es un caso de uso que invoca el ms o el cron -> PROCEDURE (CALL).
-- C2. Toda rutina lleva cabecera: proposito, parametros, retorno, errores, autor,
--     version e historial de cambios.
-- C3. Toda rutina queda registrada en public.db_routine.
-- C4. Ninguna columna de valores cerrados sin tabla de diccionario.
-- C5. Ningun umbral, ventana ni retencion en Go o Dart: public.app_setting.
-- C6. Tablas y columnas en ingles, singular, lower_snake_case. timestamptz UTC, sufijo _at.
-- C7. Migraciones manuales por psql, numeradas, nunca auto-migrate.
-- C8. La app no hace DML directo: entra y sale por prc_ / fnc_.
-- C9. Todo lo que pertenece a alguien lleva tenant_id + RLS.
--
-- -------------------------------------------------------------------------------------
-- AISLAMIENTO
-- -------------------------------------------------------------------------------------
-- CON tenant_id + RLS: device.account, device.device, device.obd_session,
--                      tracking.ingest_batch, tracking.trip, tracking.trip_track,
--                      tracking.position, traffic.observation
-- GLOBAL (compartido): public.*, geo.*, traffic.link, traffic.live_state, traffic.profile
--
-- El trafico colaborativo se muere si se particiona por tenant: una flota sola no hace un
-- mapa. Los agregados no llevan device_id y exigen min_device_count, asi que compartirlos
-- no expone a nadie. El crudo (observation) SI lleva tenant para purgar, auditar y bloquear.
--
-- Un tenant por cliente SIEMPRE, incluido el usuario personal: una sola regla de filtrado
-- en todo el sistema, cero casos especiales.
--
-- -------------------------------------------------------------------------------------
-- DECISION TOMADA EN ESTA UNIFICACION
-- -------------------------------------------------------------------------------------
-- No existe una ingesta de trafico separada. tracking.prc_ingest_telemetry escribe
-- position Y deriva traffic.observation en la misma transaccion. Si mas adelante quieres
-- aporte pasivo de trafico sin telemetria completa (pregunta 4 del doc 08), se agrega una
-- rutina nueva con tenant y RLS desde el dia uno.
-- =====================================================================================

BEGIN;

SET LOCAL client_min_messages = WARNING;

-- =====================================================================================
-- 1. EXTENSIONES Y ESQUEMAS
-- =====================================================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS geo;
CREATE SCHEMA IF NOT EXISTS device;
CREATE SCHEMA IF NOT EXISTS tracking;
CREATE SCHEMA IF NOT EXISTS traffic;
CREATE SCHEMA IF NOT EXISTS ops;

COMMENT ON SCHEMA geo      IS 'Conocimiento geografico: grilla, calles, lugares. Global.';
COMMENT ON SCHEMA device   IS 'Cuentas, dispositivos y sesiones OBD. Por tenant.';
COMMENT ON SCHEMA tracking IS 'Viajes, posiciones e ingesta. Por tenant.';
COMMENT ON SCHEMA traffic  IS 'Trafico colaborativo. Crudo por tenant, agregados globales.';
COMMENT ON SCHEMA ops      IS 'Trazabilidad: corridas del pipeline, logs, errores.';

-- =====================================================================================
-- 2. INVENTARIO DE RUTINAS (C3)
-- =====================================================================================

CREATE TABLE IF NOT EXISTS public.db_routine (
    schema_name  text NOT NULL,
    routine_name text NOT NULL,
    routine_type text NOT NULL CHECK (routine_type IN ('function','procedure')),
    purpose      text NOT NULL,
    author       text NOT NULL,
    version      text NOT NULL,
    migration    text NOT NULL,
    updated_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (schema_name, routine_name)
);
COMMENT ON TABLE public.db_routine IS
    'Inventario de fnc_/prc_ con autor y version. Se llena al final de cada migracion (C3).';

-- =====================================================================================
-- 3. CONFIGURACION (C5)
-- =====================================================================================

CREATE TABLE IF NOT EXISTS public.app_setting (
    key         text        PRIMARY KEY,
    value       jsonb       NOT NULL,
    description text        NOT NULL,
    updated_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.app_setting IS
    'Parametros operativos. Regla: si un numero aparece en Go o en Dart, esta mal; va aqui.';

INSERT INTO public.app_setting (key, value, description) VALUES
  ('locale.timezone',                   '"America/Bogota"', 'TZ para derivar day_kind y time_slot desde timestamptz UTC.'),
  ('locale.country_id',                 '"co"',  'Pais por defecto para festivos y catalogos.'),
  ('traffic.max_accuracy_m',            '25',    'Precision GPS maxima para APORTAR a trafico.'),
  ('traffic.max_speed_kmh',             '150',   'Velocidad maxima plausible. Por encima = spoofing o GPS loco.'),
  ('traffic.max_future_skew_minutes',   '5',     'Tolerancia de reloj adelantado del dispositivo.'),
  ('traffic.max_past_days',             '7',     'Antiguedad maxima de una muestra en un lote (offline acumulado).'),
  ('traffic.live_window_minutes',       '15',    'Ventana de observaciones que alimenta traffic.live_state.'),
  ('traffic.live_ttl_minutes',          '20',    'Vigencia de una fila de live_state. Vencida = gris, no verde.'),
  ('traffic.min_device_count',          '3',     'k-anonimato: minimo de dispositivos para publicar un link.'),
  ('traffic.observation_retention_days','21',    'Retencion del crudo de trafico. Se libera por DROP PARTITION.'),
  ('traffic.free_flow_night_from_hour', '0',     'Inicio de la ventana nocturna para flujo libre (hora local).'),
  ('traffic.free_flow_night_to_hour',   '4',     'Fin de la ventana nocturna para flujo libre (hora local).'),
  ('traffic.free_flow_min_samples',     '30',    'Muestras nocturnas minimas antes de confiar en el flujo libre propio.'),
  ('traffic.grid_precision',            '7',     'Precision del geohash de medicion (7 = ~76 m).'),
  ('traffic.corridor_precision',        '5',     'Precision del geohash de corredor (agrupador padre).'),
  ('tracking.position_retention_days',  '90',    'Retencion del crudo de posiciones. El viaje sobrevive en trip_track.'),
  ('tracking.max_accuracy_m',           '100',   'Precision GPS maxima para GUARDAR una posicion.'),
  ('tracking.max_altitude_m',           '6000',  'Altitud plausible. Por encima se guarda NULL en vez de basura.'),
  ('tracking.simplify_tolerance_deg',   '0.00005','Tolerancia de ST_Simplify para la traza de render (~5 m).'),
  ('obd.min_rpm',                       '0',     'Rango valido de RPM (PID 0C).'),
  ('obd.max_rpm',                       '16384', 'Rango valido de RPM (PID 0C).'),
  ('obd.min_coolant_temp_c',            '-40',   'Rango valido de temperatura de refrigerante (PID 05).'),
  ('obd.max_coolant_temp_c',            '215',   'Rango valido de temperatura de refrigerante (PID 05).'),
  ('holiday.generate_from_year',        '2020',  'Primer anio generado en public.holiday.'),
  ('holiday.generate_to_year',          '2040',  'Ultimo anio generado en public.holiday.')
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_setting_num
-- Proposito : Lee un parametro numerico de public.app_setting.
-- Parametros: p_key
-- Retorna   : numeric
-- Errores   : VT010 parametro inexistente (falla ruidosa, mejor que un default silencioso)
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_setting_num(p_key text)
RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE v numeric;
BEGIN
    SELECT (value #>> '{}')::numeric INTO v FROM public.app_setting WHERE key = p_key;
    IF v IS NULL THEN
        RAISE EXCEPTION 'app_setting % no existe', p_key USING ERRCODE = 'VT010';
    END IF;
    RETURN v;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_setting_text
-- Proposito : Lee un parametro de texto de public.app_setting.
-- Parametros: p_key
-- Retorna   : text
-- Errores   : VT010 parametro inexistente
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_setting_text(p_key text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v text;
BEGIN
    SELECT (value #>> '{}') INTO v FROM public.app_setting WHERE key = p_key;
    IF v IS NULL THEN
        RAISE EXCEPTION 'app_setting % no existe', p_key USING ERRCODE = 'VT010';
    END IF;
    RETURN v;
END $$;

-- =====================================================================================
-- 4. DICCIONARIOS (C4)
-- =====================================================================================

CREATE TABLE IF NOT EXISTS public.tenant_kind (
    id text PRIMARY KEY, name text NOT NULL, sort_order smallint NOT NULL);
INSERT INTO public.tenant_kind (id, name, sort_order) VALUES
  ('personal','Usuario personal',1),('fleet','Empresa con flota',2),
  ('reseller','Integrador o revendedor',3),('internal','Interno de Devitech',9)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.payload_kind (
    id text PRIMARY KEY, name text NOT NULL);
COMMENT ON TABLE public.payload_kind IS 'Tipo de contenido de un lote de ingesta.';
INSERT INTO public.payload_kind (id, name) VALUES
  ('telemetry','Telemetria GPS + OBD'),('position','Solo posiciones'),
  ('traffic','Solo aporte de trafico'),('event','Eventos')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.trip_status (
    id text PRIMARY KEY, name text NOT NULL, is_final boolean NOT NULL);
INSERT INTO public.trip_status (id, name, is_final) VALUES
  ('active','En curso',false),('closed','Cerrado',true),('discarded','Descartado',true)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.run_status (
    id text PRIMARY KEY, name text NOT NULL);
INSERT INTO public.run_status (id, name) VALUES
  ('running','En ejecucion'),('success','Exitosa'),('failed','Fallida')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.day_kind (
    id text PRIMARY KEY, name text NOT NULL, sort_order smallint NOT NULL);
COMMENT ON TABLE public.day_kind IS
    'Tipo de dia. Un domingo despejado no puede contaminar el perfil del martes 7am.';
INSERT INTO public.day_kind (id, name, sort_order) VALUES
  ('weekday','Dia habil',1),('saturday','Sabado',2),('sunday_holiday','Domingo o festivo',3)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.holiday (
    id          bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    on_date     date    NOT NULL,
    country_id  char(2) NOT NULL DEFAULT 'co',
    name        text    NOT NULL,
    is_movable  boolean NOT NULL DEFAULT false,
    source_date date    NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (country_id, on_date, name)
);
COMMENT ON TABLE public.holiday IS
    'Festivos generados por prc_generate_holiday. La Ley Emiliani es una regla, no una lista.
     La PK NO es on_date: San Pedro y Sagrado Corazon caen el mismo lunes en 2025-06-30,
     2030-07-01 y 2038-07-05; con PK en on_date uno de los dos se perderia en silencio.';
CREATE INDEX IF NOT EXISTS ix_holiday_country ON public.holiday (country_id, on_date);

CREATE TABLE IF NOT EXISTS public.time_slot (
    id smallint PRIMARY KEY CHECK (id BETWEEN 0 AND 47),
    start_minute smallint NOT NULL, end_minute smallint NOT NULL, label text NOT NULL,
    CHECK (end_minute > start_minute));
COMMENT ON TABLE public.time_slot IS
    'Franjas de 30 min. Reemplaza la formula hour*2+(minute>=30) hardcodeada en dos lenguajes.';
INSERT INTO public.time_slot (id, start_minute, end_minute, label)
SELECT s, s*30, s*30+30,
       to_char((s*30) * interval '1 minute','HH24:MI') || '-' ||
       to_char((s*30+30) * interval '1 minute','HH24:MI')
FROM generate_series(0,47) AS s
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.heading_bucket (
    id smallint PRIMARY KEY CHECK (id BETWEEN 0 AND 7),
    center_deg smallint NOT NULL, label text NOT NULL);
COMMENT ON TABLE public.heading_bucket IS
    'Sentido de circulacion en 8 sectores. Sin esto, el trancon norte-sur se diluye con el sur-norte libre.';
INSERT INTO public.heading_bucket (id, center_deg, label) VALUES
  (0,0,'N'),(1,45,'NE'),(2,90,'E'),(3,135,'SE'),(4,180,'S'),(5,225,'SO'),(6,270,'O'),(7,315,'NO')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.link_kind (
    id text PRIMARY KEY, name text NOT NULL, precedence smallint NOT NULL);
COMMENT ON COLUMN public.link_kind.precedence IS
    'Si un punto cae en celda y en segmento, gana el de precedence mayor.';
INSERT INTO public.link_kind (id, name, precedence) VALUES
  ('grid_cell','Celda de grilla',1),('street_segment','Segmento de via',2)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.congestion_level (
    id text PRIMARY KEY, name text NOT NULL,
    min_ratio numeric(4,2) NOT NULL, max_ratio numeric(4,2) NOT NULL,
    color_hex char(7) NOT NULL, sort_order smallint NOT NULL,
    CHECK (max_ratio > min_ratio));
COMMENT ON TABLE public.congestion_level IS
    'Umbrales y colores en tabla, no en el codigo: el dia que 0.5 sea heavy, app y API se alinean sin release.';
INSERT INTO public.congestion_level (id, name, min_ratio, max_ratio, color_hex, sort_order) VALUES
  ('standstill','Detenido',0.00,0.15,'#B00020',1),
  ('heavy','Congestion',0.15,0.35,'#E53935',2),
  ('moderate','Lento',0.35,0.60,'#FB8C00',3),
  ('light','Fluido',0.60,0.80,'#FDD835',4),
  ('free','Libre',0.80,9.99,'#43A047',5)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.speed_bucket (
    id smallint PRIMARY KEY, min_kmh smallint NOT NULL, max_kmh smallint NOT NULL,
    label text NOT NULL, CHECK (max_kmh > min_kmh));
COMMENT ON TABLE public.speed_bucket IS
    'Buckets del histograma de traffic.profile. Son las llaves del jsonb: el histograma SI esta diccionado.';
INSERT INTO public.speed_bucket (id, min_kmh, max_kmh, label) VALUES
  (1,0,5,'0-5'),(2,5,10,'5-10'),(3,10,15,'10-15'),(4,15,20,'15-20'),(5,20,25,'20-25'),
  (6,25,30,'25-30'),(7,30,40,'30-40'),(8,40,50,'40-50'),(9,50,60,'50-60'),
  (10,60,80,'60-80'),(11,80,100,'80-100'),(12,100,999,'100+')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.position_source (
    id text PRIMARY KEY, name text NOT NULL, trust_weight numeric(3,2) NOT NULL DEFAULT 1.00);
COMMENT ON COLUMN public.position_source.trust_weight IS
    'La velocidad por OBD es medida; por GPS es derivada. No pesan igual.';
INSERT INTO public.position_source (id, name, trust_weight) VALUES
  ('gps','GPS',1.00),('obd','OBD-II',1.00),('fused','Fusionada',0.90)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.obd_protocol (
    id text PRIMARY KEY, elm_code char(1) NOT NULL, name text NOT NULL,
    bus_speed_k int, is_can boolean NOT NULL DEFAULT false, sort_order smallint NOT NULL);
COMMENT ON TABLE public.obd_protocol IS
    'Protocolos del ELM327 (respuesta a ATDP). El "protocol" que hoy va en cada fila de BigQuery
     se mapea aqui una vez: es constante durante toda la conexion, no un dato por punto.';
INSERT INTO public.obd_protocol (id, elm_code, name, bus_speed_k, is_can, sort_order) VALUES
  ('auto','0','Automatico',NULL,false,0),
  ('j1850_pwm','1','SAE J1850 PWM (41.6 kbaud)',42,false,1),
  ('j1850_vpw','2','SAE J1850 VPW (10.4 kbaud)',10,false,2),
  ('iso9141_2','3','ISO 9141-2 (5 baud init)',10,false,3),
  ('iso14230_slow','4','ISO 14230-4 KWP (5 baud init)',10,false,4),
  ('iso14230_fast','5','ISO 14230-4 KWP (fast init)',10,false,5),
  ('iso15765_11_500','6','ISO 15765-4 CAN (11 bit, 500 kbaud)',500,true,6),
  ('iso15765_29_500','7','ISO 15765-4 CAN (29 bit, 500 kbaud)',500,true,7),
  ('iso15765_11_250','8','ISO 15765-4 CAN (11 bit, 250 kbaud)',250,true,8),
  ('iso15765_29_250','9','ISO 15765-4 CAN (29 bit, 250 kbaud)',250,true,9),
  ('j1939_can','A','SAE J1939 CAN (29 bit, 250 kbaud)',250,true,10),
  ('unknown','0','Desconocido / no reportado',NULL,false,99)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.pipeline_job (
    id text PRIMARY KEY, name text NOT NULL, expected_interval_min int NOT NULL);
COMMENT ON COLUMN public.pipeline_job.expected_interval_min IS
    'Base de la alerta "hace X que no corre". Sin esto, un rollup caido pasa desapercibido.';
INSERT INTO public.pipeline_job (id, name, expected_interval_min) VALUES
  ('osm_import','Import OSM',43200),('planetiler','Build de tiles',43200),
  ('osrm_build','Build OSRM',43200),('package_publish','Publicacion de paquetes',43200),
  ('traffic_rollup_live','Rollup de trafico vivo',5),
  ('traffic_rollup_profile','Rollup de perfil de trafico',60),
  ('traffic_free_flow','Recalculo de flujo libre',10080),
  ('partition_maintenance','Particiones y retencion',1440),
  ('holiday_generate','Generacion de festivos',525600)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.municipality (
    id            text PRIMARY KEY,
    department_id text,
    name          text NOT NULL,
    geom          geometry(MultiPolygon, 4326)
);
COMMENT ON TABLE public.municipality IS
    'Subconjunto del catalogo del doc 07 necesario aqui. El DDL de catalogos lo completa por ALTER.';

-- =====================================================================================
-- 5. TENANT
-- =====================================================================================

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
    'Unidad de aislamiento. Un usuario personal tambien tiene su tenant: una sola regla de filtrado.';
COMMENT ON COLUMN public.tenant.max_device IS 'NULL = sin limite. Se valida en prc_register_device.';

INSERT INTO public.tenant (id, slug, name, tenant_kind_id)
VALUES ('00000000-0000-0000-0000-000000000001','devitech','Devitech (interno)','internal')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================================
-- 6. ops
-- =====================================================================================

CREATE TABLE IF NOT EXISTS ops.pipeline_run (
    id              bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    pipeline_job_id text        NOT NULL REFERENCES public.pipeline_job(id),
    run_status_id   text        NOT NULL REFERENCES public.run_status(id),
    region_id       text,
    started_at      timestamptz NOT NULL DEFAULT now(),
    finished_at     timestamptz,
    row_count       bigint,
    log_excerpt     text
);
CREATE INDEX IF NOT EXISTS ix_pipeline_run_job_started
    ON ops.pipeline_run (pipeline_job_id, started_at DESC);

-- =====================================================================================
-- 7. device — cuentas, dispositivos, sesiones OBD
-- =====================================================================================

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
    'Cuenta dentro de un tenant. Sin uso hasta que exista login; existe para no alterar despues.';

CREATE TABLE IF NOT EXISTS device.device (
    id            uuid        PRIMARY KEY,
    tenant_id     uuid        NOT NULL REFERENCES public.tenant(id),
    account_id    uuid        REFERENCES device.account(id),
    install_id    text        UNIQUE,
    platform      text,
    os_version    text,
    app_version   text,
    model         text,
    push_token    text,
    registered_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at  timestamptz,
    is_blocked    boolean     NOT NULL DEFAULT false
);
COMMENT ON COLUMN device.device.tenant_id IS
    'Dueno del dispositivo. Un device NO se muda de tenant en caliente: mover historial entre
     clientes es una operacion administrativa, no un efecto secundario de un registro.';
CREATE INDEX IF NOT EXISTS ix_device_tenant ON device.device (tenant_id) WHERE NOT is_blocked;
CREATE INDEX IF NOT EXISTS ix_device_account ON device.device (account_id);

CREATE TABLE IF NOT EXISTS tracking.ingest_batch (
    id                uuid        PRIMARY KEY,
    tenant_id         uuid        NOT NULL REFERENCES public.tenant(id),
    device_id         uuid        NOT NULL REFERENCES device.device(id),
    payload_kind_id   text        NOT NULL REFERENCES public.payload_kind(id),
    item_count        int         NOT NULL DEFAULT 0,
    accepted_count    int         NOT NULL DEFAULT 0,
    rejected_count    int         NOT NULL DEFAULT 0,
    client_created_at timestamptz,
    received_at       timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE tracking.ingest_batch IS
    'Lote de ingesta. El id lo genera la app (uuid v7). Un reintento NO crea fila: devuelve esta.';
CREATE INDEX IF NOT EXISTS ix_ingest_batch_tenant ON tracking.ingest_batch (tenant_id, received_at DESC);
CREATE INDEX IF NOT EXISTS ix_ingest_batch_device ON tracking.ingest_batch (device_id, received_at DESC);

CREATE TABLE IF NOT EXISTS tracking.trip (
    id                 uuid        PRIMARY KEY,
    tenant_id          uuid        NOT NULL REFERENCES public.tenant(id),
    device_id          uuid        NOT NULL REFERENCES device.device(id),
    account_id         uuid        REFERENCES device.account(id),
    trip_status_id     text        NOT NULL REFERENCES public.trip_status(id) DEFAULT 'active',
    position_source_id text        REFERENCES public.position_source(id),
    started_at         timestamptz NOT NULL,
    ended_at           timestamptz,
    distance_m         numeric(12,2),
    max_speed_kmh      numeric(6,2),
    avg_speed_kmh      numeric(6,2),
    point_count        int,
    fuel_liters        numeric(8,3),
    cost_cop           numeric(12,2),
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE tracking.trip IS
    'Viaje. El id lo genera la app (uuid v7) para poder crearlo sin conexion.';
CREATE INDEX IF NOT EXISTS ix_trip_tenant ON tracking.trip (tenant_id, started_at DESC);
CREATE INDEX IF NOT EXISTS ix_trip_device ON tracking.trip (device_id, started_at DESC);

CREATE TABLE IF NOT EXISTS tracking.trip_track (
    trip_id            uuid PRIMARY KEY REFERENCES tracking.trip(id) ON DELETE CASCADE,
    tenant_id          uuid NOT NULL REFERENCES public.tenant(id),
    geom               geometry(LineString, 4326) NOT NULL,
    geom_simplified    geometry(LineString, 4326),
    source_point_count int NOT NULL,
    materialized_at    timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE tracking.trip_track IS
    'Traza materializada al cerrar el viaje. Es PERMANENTE: por eso position puede borrarse a los 90 dias.';

CREATE TABLE IF NOT EXISTS device.obd_session (
    id              uuid        PRIMARY KEY,
    tenant_id       uuid        NOT NULL REFERENCES public.tenant(id),
    device_id       uuid        NOT NULL REFERENCES device.device(id),
    trip_id         uuid        REFERENCES tracking.trip(id),
    obd_protocol_id text        NOT NULL REFERENCES public.obd_protocol(id),
    adapter_name    text,
    started_at      timestamptz NOT NULL,
    ended_at        timestamptz,
    sample_count    bigint      NOT NULL DEFAULT 0,
    updated_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE device.obd_session IS
    'Una conexion del adaptador OBD. Aqui vive el protocolo y el adaptador: constantes de la sesion, no del punto.';
CREATE INDEX IF NOT EXISTS ix_obd_session_tenant ON device.obd_session (tenant_id, started_at DESC);
CREATE INDEX IF NOT EXISTS ix_obd_session_trip   ON device.obd_session (trip_id);

-- =====================================================================================
-- 8. tracking.position — telemetria (reemplaza la tabla de BigQuery completa)
-- =====================================================================================

CREATE SEQUENCE IF NOT EXISTS tracking.position_id_seq AS bigint;

CREATE TABLE IF NOT EXISTS tracking.position (
    id                 bigint      NOT NULL DEFAULT nextval('tracking.position_id_seq'),
    tenant_id          uuid        NOT NULL REFERENCES public.tenant(id),
    device_id          uuid        NOT NULL REFERENCES device.device(id),
    trip_id            uuid        REFERENCES tracking.trip(id),
    ingest_batch_id    uuid        REFERENCES tracking.ingest_batch(id),
    obd_session_id     uuid        REFERENCES device.obd_session(id),
    position_source_id text        NOT NULL REFERENCES public.position_source(id),
    geom               geometry(Point, 4326) NOT NULL,
    speed_kmh          numeric(6,2),
    speed_gps_kmh      numeric(6,2),
    speed_obd_kmh      numeric(6,2),
    bearing_deg        numeric(5,2),
    accuracy_m         numeric(6,2),
    altitude_m         numeric(7,2),
    rpm                numeric(7,2),
    coolant_temp_c     numeric(5,1),
    fuel_level_pct     numeric(5,2) CHECK (fuel_level_pct BETWEEN 0 AND 100),
    recorded_at        timestamptz NOT NULL,
    received_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (recorded_at, id),
    UNIQUE (recorded_at, device_id)
) PARTITION BY RANGE (recorded_at);

COMMENT ON TABLE tracking.position IS
    'Posicion + telemetria del vehiculo. Retencion: tracking.position_retention_days.';
COMMENT ON COLUMN tracking.position.speed_kmh IS
    'Velocidad efectiva usada por el resto del sistema. position_source_id dice de donde salio.';
COMMENT ON COLUMN tracking.position.speed_gps_kmh IS
    'Cruda del GPS. Se conserva junto a la del OBD para comparar fuentes y calibrar.';
COMMENT ON COLUMN tracking.position.fuel_level_pct IS
    'PID 2F. Es la senal que permite consumo real en vez de estimado por distancia.';
COMMENT ON COLUMN tracking.position.tenant_id IS
    'Desnormalizado: el filtro de RLS en la tabla mas grande no puede depender de un join a device.';
COMMENT ON CONSTRAINT position_recorded_at_device_id_key ON tracking.position IS
    'Idempotencia natural: un punto por device por instante. Reenviar el mismo instante
     ACTUALIZA (enriquecer con OBD que llego tarde), no duplica.';

-- =====================================================================================
-- 9. geo — grilla y segmento (GLOBAL, sin tenant)
-- =====================================================================================

CREATE TABLE IF NOT EXISTS geo.grid_cell (
    id              text     PRIMARY KEY,
    parent_cell_id  text     REFERENCES geo.grid_cell(id),
    precision       smallint NOT NULL CHECK (precision BETWEEN 1 AND 12),
    municipality_id text     REFERENCES public.municipality(id),
    geom            geometry(Polygon, 4326) NOT NULL,
    centroid        geometry(Point, 4326)   NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE geo.grid_cell IS
    'Celdas geohash creadas BAJO DEMANDA. No se precarga la ciudad: la mayoria seria mar, cano y patio.';
COMMENT ON COLUMN geo.grid_cell.parent_cell_id IS
    'Celda de menor precision = corredor. Reemplaza la columna corridor duplicada dentro de la PK.';
CREATE INDEX IF NOT EXISTS ix_grid_cell_parent       ON geo.grid_cell (parent_cell_id);
CREATE INDEX IF NOT EXISTS ix_grid_cell_municipality ON geo.grid_cell (municipality_id);
CREATE INDEX IF NOT EXISTS ix_grid_cell_geom         ON geo.grid_cell USING gist (geom);

CREATE TABLE IF NOT EXISTS geo.street_segment (
    id              bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    street_id       bigint,
    seq             int      NOT NULL DEFAULT 0,
    grid_cell_id    text     REFERENCES geo.grid_cell(id),
    geom            geometry(LineString, 4326) NOT NULL,
    length_m        numeric(10,2),
    is_reverse      boolean  NOT NULL DEFAULT false,
    speed_limit_kmh smallint,
    UNIQUE (street_id, seq, is_reverse)
);
COMMENT ON TABLE geo.street_segment IS
    'Unidad direccional de via. Vacia en F3: la llena el map matching de F4. traffic.link la absorbe sin migracion.';
CREATE INDEX IF NOT EXISTS ix_street_segment_geom ON geo.street_segment USING gist (geom);

-- =====================================================================================
-- 10. traffic — link y agregados GLOBALES, crudo POR TENANT
-- =====================================================================================

CREATE TABLE IF NOT EXISTS traffic.link (
    id                     bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    link_kind_id           text     NOT NULL REFERENCES public.link_kind(id),
    grid_cell_id           text     REFERENCES geo.grid_cell(id),
    street_segment_id      bigint   REFERENCES geo.street_segment(id),
    heading_bucket_id      smallint REFERENCES public.heading_bucket(id),
    municipality_id        text     REFERENCES public.municipality(id),
    geom                   geometry(Geometry, 4326) NOT NULL,
    free_flow_speed_kmh    numeric(5,2),
    free_flow_sample_count int      NOT NULL DEFAULT 0,
    free_flow_computed_at  timestamptz,
    observation_count      bigint   NOT NULL DEFAULT 0,
    first_seen_at          timestamptz NOT NULL DEFAULT now(),
    last_seen_at           timestamptz NOT NULL DEFAULT now(),
    is_active              boolean  NOT NULL DEFAULT true,
    CONSTRAINT ck_link_shape CHECK (
        (link_kind_id = 'grid_cell'
            AND grid_cell_id IS NOT NULL AND heading_bucket_id IS NOT NULL AND street_segment_id IS NULL)
        OR
        (link_kind_id = 'street_segment'
            AND street_segment_id IS NOT NULL AND grid_cell_id IS NULL AND heading_bucket_id IS NULL)
    )
);
COMMENT ON TABLE traffic.link IS
    'Unidad direccional de medicion, GLOBAL. Un solo agregado sirve a grilla (F3) y a segmento (F4).';
COMMENT ON COLUMN traffic.link.free_flow_speed_kmh IS
    'p85 nocturno propio. Baseline real: 25 km/h es libre en una via de 30 y trancon en una de 80.';
CREATE UNIQUE INDEX IF NOT EXISTS ux_link_grid
    ON traffic.link (grid_cell_id, heading_bucket_id) WHERE link_kind_id = 'grid_cell';
CREATE UNIQUE INDEX IF NOT EXISTS ux_link_segment
    ON traffic.link (street_segment_id) WHERE link_kind_id = 'street_segment';
CREATE INDEX IF NOT EXISTS ix_link_geom ON traffic.link USING gist (geom);
CREATE INDEX IF NOT EXISTS ix_link_municipality ON traffic.link (municipality_id) WHERE is_active;

CREATE SEQUENCE IF NOT EXISTS traffic.observation_id_seq AS bigint;

CREATE TABLE IF NOT EXISTS traffic.observation (
    id                 bigint      NOT NULL DEFAULT nextval('traffic.observation_id_seq'),
    tenant_id          uuid        NOT NULL REFERENCES public.tenant(id),
    device_id          uuid        NOT NULL REFERENCES device.device(id),
    trip_id            uuid        REFERENCES tracking.trip(id),
    ingest_batch_id    uuid        NOT NULL REFERENCES tracking.ingest_batch(id) ON DELETE CASCADE,
    traffic_link_id    bigint      NOT NULL REFERENCES traffic.link(id),
    position_source_id text        NOT NULL REFERENCES public.position_source(id),
    day_kind_id        text        NOT NULL REFERENCES public.day_kind(id),
    time_slot_id       smallint    NOT NULL REFERENCES public.time_slot(id),
    speed_kmh          numeric(5,2) NOT NULL CHECK (speed_kmh >= 0),
    accuracy_m         numeric(6,2),
    heading_deg        smallint    CHECK (heading_deg BETWEEN 0 AND 359),
    observed_at        timestamptz NOT NULL,
    received_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (observed_at, id)
) PARTITION BY RANGE (observed_at);

COMMENT ON TABLE traffic.observation IS
    'Resultado del map matching, no una copia de position. Crudo POR TENANT, retencion corta.';
COMMENT ON COLUMN traffic.observation.day_kind_id IS
    'Resuelto en ingesta con la TZ local: el rollup del perfil queda como un GROUP BY puro.';

CREATE TABLE IF NOT EXISTS traffic.live_state (
    traffic_link_id     bigint       PRIMARY KEY REFERENCES traffic.link(id) ON DELETE CASCADE,
    speed_p50_kmh       numeric(5,2) NOT NULL,
    congestion_ratio    numeric(5,3),
    congestion_level_id text         REFERENCES public.congestion_level(id),
    sample_count        int          NOT NULL,
    device_count        int          NOT NULL,
    window_start_at     timestamptz  NOT NULL,
    window_end_at       timestamptz  NOT NULL,
    expires_at          timestamptz  NOT NULL,
    updated_at          timestamptz  NOT NULL DEFAULT now()
) WITH (fillfactor = 70,
        autovacuum_vacuum_scale_factor = 0.02,
        autovacuum_analyze_scale_factor = 0.05);
COMMENT ON TABLE traffic.live_state IS
    'Una fila por link, se sobrescribe. expires_at permite distinguir "libre" de "sin datos".';
CREATE INDEX IF NOT EXISTS ix_live_state_expires ON traffic.live_state (expires_at);

CREATE TABLE IF NOT EXISTS traffic.profile (
    traffic_link_id  bigint      NOT NULL REFERENCES traffic.link(id) ON DELETE CASCADE,
    day_kind_id      text        NOT NULL REFERENCES public.day_kind(id),
    time_slot_id     smallint    NOT NULL REFERENCES public.time_slot(id),
    speed_p50_kmh    numeric(5,2),
    speed_p85_kmh    numeric(5,2),
    congestion_ratio numeric(5,3),
    speed_histogram  jsonb       NOT NULL DEFAULT '{}'::jsonb,
    sample_count     bigint      NOT NULL DEFAULT 0,
    device_count     int         NOT NULL DEFAULT 0,
    covers_from_at   timestamptz,
    covers_to_at     timestamptz,
    updated_at       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (traffic_link_id, day_kind_id, time_slot_id)
);
COMMENT ON TABLE traffic.profile IS
    'Perfil tipico. No crece con el tiempo, solo con la cobertura: links x 3 x 48.';
COMMENT ON COLUMN traffic.profile.speed_histogram IS
    'Conteo por public.speed_bucket.id. Mergeable: el rollup nunca vuelve a leer el crudo.';
COMMENT ON COLUMN traffic.profile.device_count IS
    'Maximo de dispositivos distintos en una ventana de rollup. Conservador: es para k-anonimato, no estadistica.';
CREATE INDEX IF NOT EXISTS ix_profile_slot ON traffic.profile (day_kind_id, time_slot_id);

-- =====================================================================================
-- 11. RLS — el filtro que el ms no puede olvidar (C9)
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_current_tenant
-- Proposito : Tenant de la transaccion actual, leido del GUC app.tenant_id que setea el ms.
-- Parametros: ninguno
-- Retorna   : uuid, o NULL si no se seteo
-- Errores   : ninguno (falla cerrado: sin GUC las politicas no dejan ver nada)
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_current_tenant()
RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid;
$$;
COMMENT ON FUNCTION public.fnc_current_tenant IS
    'El dueno de las tablas NO tiene FORCE ROW LEVEL SECURITY: los rollups y el cron (que corren
     como dueno) siguen viendo todo. El rol vehitrack_app si esta sujeto a las politicas.';

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['device.account','device.device','device.obd_session',
                             'tracking.ingest_batch','tracking.trip','tracking.trip_track',
                             'tracking.position','traffic.observation']
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
-- 12. FUNCIONES DE CALENDARIO
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_easter_sunday
-- Proposito : Domingo de Pascua (Meeus/Butcher, calendario gregoriano).
-- Parametros: p_year
-- Retorna   : date
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_easter_sunday(p_year int)
RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE a int; b int; c int; d int; e int; f int; g int; h int;
        i int; k int; l int; m int; v_month int; v_day int;
BEGIN
    a := p_year % 19;  b := p_year / 100;  c := p_year % 100;
    d := b / 4;        e := b % 4;         f := (b + 8) / 25;
    g := (b - f + 1) / 3;
    h := (19 * a + b - d - g + 15) % 30;
    i := c / 4;        k := c % 4;
    l := (32 + 2 * e + 2 * i - h - k) % 7;
    m := (a + 11 * h + 22 * l) / 451;
    v_month := (h + l - 7 * m + 114) / 31;
    v_day   := ((h + l - 7 * m + 114) % 31) + 1;
    RETURN make_date(p_year, v_month, v_day);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_emiliani
-- Proposito : Ley Emiliani (Ley 51 de 1983): corre el festivo al lunes siguiente.
-- Parametros: p_date
-- Retorna   : date (igual si ya cae lunes)
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_emiliani(p_date date)
RETURNS date LANGUAGE sql IMMUTABLE AS $$
    SELECT p_date + (((8 - extract(isodow FROM p_date)::int) % 7))::int;
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.prc_generate_holiday
-- Proposito : Genera los 18 festivos colombianos por anio: 6 fijos, 7 trasladables,
--             2 de Semana Santa y 3 moviles derivados de Pascua con traslado.
-- Parametros: p_from_year, p_to_year, p_result INOUT {from_year, to_year, inserted}
-- Errores   : VT011 rango invalido
-- Nota      : Dos festivos SI pueden caer el mismo dia (San Pedro y Sagrado Corazon en
--             2025, 2030 y 2038). Por eso la unicidad es (country_id, on_date, name).
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE public.prc_generate_holiday(
    p_from_year int, p_to_year int, INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_run_id   bigint;
    v_country  char(2) := public.fnc_setting_text('locale.country_id');
    v_inserted int := 0; v_n int; y int; e date;
BEGIN
    IF p_to_year < p_from_year THEN
        RAISE EXCEPTION 'rango de anios invalido' USING ERRCODE = 'VT011';
    END IF;

    INSERT INTO ops.pipeline_run (pipeline_job_id, run_status_id)
    VALUES ('holiday_generate','running') RETURNING id INTO v_run_id;

    FOR y IN p_from_year..p_to_year LOOP
        e := public.fnc_easter_sunday(y);
        INSERT INTO public.holiday (on_date, country_id, name, is_movable, source_date)
        SELECT h.on_date, v_country, h.name, h.is_movable, h.source_date
        FROM (
            SELECT make_date(y,1,1) AS on_date, 'Ano Nuevo' AS name, false AS is_movable, make_date(y,1,1) AS source_date
            UNION ALL SELECT make_date(y,5,1),   'Dia del Trabajo',           false, make_date(y,5,1)
            UNION ALL SELECT make_date(y,7,20),  'Independencia de Colombia', false, make_date(y,7,20)
            UNION ALL SELECT make_date(y,8,7),   'Batalla de Boyaca',         false, make_date(y,8,7)
            UNION ALL SELECT make_date(y,12,8),  'Inmaculada Concepcion',     false, make_date(y,12,8)
            UNION ALL SELECT make_date(y,12,25), 'Navidad',                   false, make_date(y,12,25)
            UNION ALL SELECT public.fnc_emiliani(make_date(y,1,6)),   'Reyes Magos',                true, make_date(y,1,6)
            UNION ALL SELECT public.fnc_emiliani(make_date(y,3,19)),  'San Jose',                   true, make_date(y,3,19)
            UNION ALL SELECT public.fnc_emiliani(make_date(y,6,29)),  'San Pedro y San Pablo',      true, make_date(y,6,29)
            UNION ALL SELECT public.fnc_emiliani(make_date(y,8,15)),  'Asuncion de la Virgen',      true, make_date(y,8,15)
            UNION ALL SELECT public.fnc_emiliani(make_date(y,10,12)), 'Dia de la Raza',             true, make_date(y,10,12)
            UNION ALL SELECT public.fnc_emiliani(make_date(y,11,1)),  'Todos los Santos',           true, make_date(y,11,1)
            UNION ALL SELECT public.fnc_emiliani(make_date(y,11,11)), 'Independencia de Cartagena', true, make_date(y,11,11)
            UNION ALL SELECT e - 3,  'Jueves Santo',        false, e - 3
            UNION ALL SELECT e - 2,  'Viernes Santo',       false, e - 2
            UNION ALL SELECT e + 43, 'Ascension del Senor', true,  e + 39
            UNION ALL SELECT e + 64, 'Corpus Christi',      true,  e + 60
            UNION ALL SELECT e + 71, 'Sagrado Corazon',     true,  e + 68
        ) h
        ON CONFLICT (country_id, on_date, name) DO NOTHING;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_inserted := v_inserted + v_n;
    END LOOP;

    UPDATE ops.pipeline_run SET run_status_id='success', finished_at=now(), row_count=v_inserted
     WHERE id = v_run_id;

    p_result := jsonb_build_object('from_year',p_from_year,'to_year',p_to_year,'inserted',v_inserted);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_day_kind_of
-- Proposito : Clasifica un instante UTC en weekday / saturday / sunday_holiday.
-- Parametros: p_at, p_tz (default app_setting locale.timezone)
-- Retorna   : text (FK a public.day_kind)
-- Errores   : VT010 si falta el setting de TZ
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_day_kind_of(p_at timestamptz, p_tz text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE l timestamp; d int;
BEGIN
    l := p_at AT TIME ZONE COALESCE(p_tz, public.fnc_setting_text('locale.timezone'));
    d := extract(dow FROM l);
    IF d = 0 OR EXISTS (SELECT 1 FROM public.holiday WHERE on_date = l::date) THEN
        RETURN 'sunday_holiday';
    ELSIF d = 6 THEN
        RETURN 'saturday';
    END IF;
    RETURN 'weekday';
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_time_slot_of
-- Proposito : Franja de 30 min (0..47) de un instante, en hora local.
-- Parametros: p_at, p_tz
-- Retorna   : smallint (FK a public.time_slot)
-- Errores   : VT010 si falta el setting de TZ
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_time_slot_of(p_at timestamptz, p_tz text DEFAULT NULL)
RETURNS smallint LANGUAGE sql STABLE AS $$
    SELECT (extract(hour FROM l) * 2 + CASE WHEN extract(minute FROM l) >= 30 THEN 1 ELSE 0 END)::smallint
    FROM (SELECT p_at AT TIME ZONE COALESCE(p_tz, public.fnc_setting_text('locale.timezone')) AS l) s;
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_heading_bucket_of
-- Proposito : Convierte un rumbo en grados al sector de 45 grados (0..7).
-- Parametros: p_heading_deg
-- Retorna   : smallint (FK a public.heading_bucket)
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_heading_bucket_of(p_heading_deg numeric)
RETURNS smallint LANGUAGE sql IMMUTABLE AS $$
    SELECT (floor((((p_heading_deg % 360 + 360) % 360) + 22.5) / 45)::int % 8)::smallint;
$$;

-- =====================================================================================
-- 13. FUNCIONES DE DOMINIO — trafico
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.fnc_congestion_level_of
-- Proposito : Traduce un ratio p50/free_flow al nivel de congestion diccionado.
-- Parametros: p_ratio
-- Retorna   : text (FK a public.congestion_level) o NULL
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION traffic.fnc_congestion_level_of(p_ratio numeric)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT id FROM public.congestion_level
    WHERE p_ratio IS NOT NULL AND p_ratio >= min_ratio AND p_ratio < max_ratio
    ORDER BY sort_order LIMIT 1;
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.fnc_merge_histogram
-- Proposito : Suma dos histogramas {speed_bucket_id: conteo}.
-- Parametros: a, b
-- Retorna   : jsonb
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION traffic.fnc_merge_histogram(a jsonb, b jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
    SELECT COALESCE(jsonb_object_agg(k, v), '{}'::jsonb)
    FROM (
        SELECT key AS k, sum(value::bigint) AS v
        FROM (
            SELECT * FROM jsonb_each_text(COALESCE(a,'{}'::jsonb))
            UNION ALL
            SELECT * FROM jsonb_each_text(COALESCE(b,'{}'::jsonb))
        ) s GROUP BY key
    ) m;
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.fnc_percentile_from_histogram
-- Proposito : Percentil por interpolacion lineal sobre public.speed_bucket. Es lo que hace
--             innecesario releer el crudo en cada rollup.
-- Parametros: p_hist, p_percentile (0..1)
-- Retorna   : numeric km/h, o NULL si el histograma esta vacio
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION traffic.fnc_percentile_from_histogram(p_hist jsonb, p_percentile numeric)
RETURNS numeric LANGUAGE sql STABLE AS $$
    WITH b AS (
        SELECT sb.min_kmh, sb.max_kmh, COALESCE((p_hist ->> sb.id::text)::bigint, 0) AS cnt
        FROM public.speed_bucket sb
    ),
    t AS (SELECT sum(cnt) AS total FROM b),
    c AS (
        SELECT b.*, t.total, sum(b.cnt) OVER (ORDER BY b.min_kmh) AS cum
        FROM b CROSS JOIN t WHERE t.total > 0
    )
    SELECT round(min_kmh + (max_kmh - min_kmh) *
        LEAST(1, GREATEST(0, (total * p_percentile - (cum - cnt)) / NULLIF(cnt, 0))), 2)
    FROM c
    WHERE cnt > 0 AND cum >= total * p_percentile
    ORDER BY min_kmh LIMIT 1;
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- geo.fnc_resolve_grid_cell
-- Proposito : Geohash de la celda de un punto, creandola (y a su corredor padre) si falta.
-- Parametros: p_geom (Point 4326)
-- Retorna   : text  id de geo.grid_cell
-- Errores   : VT010 si faltan settings de precision
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION geo.fnc_resolve_grid_cell(p_geom geometry)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_p_cell     smallint := public.fnc_setting_num('traffic.grid_precision')::smallint;
    v_p_corridor smallint := public.fnc_setting_num('traffic.corridor_precision')::smallint;
    v_cell       text := ST_GeoHash(p_geom, v_p_cell);
    v_corridor   text := left(ST_GeoHash(p_geom, v_p_cell), v_p_corridor);
BEGIN
    INSERT INTO geo.grid_cell (id, parent_cell_id, precision, municipality_id, geom, centroid)
    SELECT v_corridor, NULL, v_p_corridor,
           (SELECT m.id FROM public.municipality m
             WHERE m.geom IS NOT NULL AND ST_Intersects(m.geom, ST_Centroid(g)) LIMIT 1),
           g, ST_Centroid(g)
    FROM (SELECT ST_SetSRID(ST_GeomFromGeoHash(v_corridor),4326)::geometry(Polygon,4326) AS g) x
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO geo.grid_cell (id, parent_cell_id, precision, municipality_id, geom, centroid)
    SELECT v_cell, v_corridor, v_p_cell,
           (SELECT m.id FROM public.municipality m
             WHERE m.geom IS NOT NULL AND ST_Intersects(m.geom, ST_Centroid(g)) LIMIT 1),
           g, ST_Centroid(g)
    FROM (SELECT ST_SetSRID(ST_GeomFromGeoHash(v_cell),4326)::geometry(Polygon,4326) AS g) x
    ON CONFLICT (id) DO NOTHING;

    RETURN v_cell;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.fnc_resolve_grid_link
-- Proposito : Id del link (celda + sentido), creandolo si no existe.
-- Parametros: p_grid_cell_id, p_heading_bucket_id
-- Retorna   : bigint
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION traffic.fnc_resolve_grid_link(p_grid_cell_id text, p_heading_bucket_id smallint)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
    SELECT id INTO v_id FROM traffic.link
     WHERE link_kind_id = 'grid_cell' AND grid_cell_id = p_grid_cell_id
       AND heading_bucket_id = p_heading_bucket_id;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    INSERT INTO traffic.link (link_kind_id, grid_cell_id, heading_bucket_id, municipality_id, geom)
    SELECT 'grid_cell', c.id, p_heading_bucket_id, c.municipality_id, c.centroid
    FROM geo.grid_cell c WHERE c.id = p_grid_cell_id
    ON CONFLICT (grid_cell_id, heading_bucket_id) WHERE link_kind_id = 'grid_cell'
    DO UPDATE SET last_seen_at = now()
    RETURNING id INTO v_id;

    RETURN v_id;
END $$;

-- =====================================================================================
-- 14. PARTICIONES Y RETENCION
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- tracking.fnc_ensure_position_partition
-- Proposito : Crea (si falta) la particion mensual de tracking.position y sus indices.
-- Parametros: p_month
-- Retorna   : text nombre de la particion
-- Errores   : ninguno
-- Nota      : Sin particion DEFAULT a proposito: una DEFAULT con datos obliga a escanearla
--             al adjuntar la siguiente. Advisory lock para ingestas concurrentes.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tracking.fnc_ensure_position_partition(p_month date)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_from date := date_trunc('month', p_month)::date;
    v_to   date := (date_trunc('month', p_month) + interval '1 month')::date;
    v_name text := 'position_' || to_char(v_from,'YYYYMM');
BEGIN
    IF to_regclass('tracking.'||v_name) IS NOT NULL THEN RETURN v_name; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('tracking.'||v_name));
    IF to_regclass('tracking.'||v_name) IS NOT NULL THEN RETURN v_name; END IF;

    EXECUTE format('CREATE TABLE tracking.%I PARTITION OF tracking.position FOR VALUES FROM (%L) TO (%L)',
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
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION traffic.fnc_ensure_observation_partition(p_month date)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_from date := date_trunc('month', p_month)::date;
    v_to   date := (date_trunc('month', p_month) + interval '1 month')::date;
    v_name text := 'observation_' || to_char(v_from,'YYYYMM');
BEGIN
    IF to_regclass('traffic.'||v_name) IS NOT NULL THEN RETURN v_name; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('traffic.'||v_name));
    IF to_regclass('traffic.'||v_name) IS NOT NULL THEN RETURN v_name; END IF;

    EXECUTE format('CREATE TABLE traffic.%I PARTITION OF traffic.observation FOR VALUES FROM (%L) TO (%L)',
                   v_name, v_from, v_to);
    EXECUTE format('CREATE INDEX %I ON traffic.%I USING brin (observed_at)', 'brin_'||v_name, v_name);
    EXECUTE format('CREATE INDEX %I ON traffic.%I (traffic_link_id, observed_at)', 'ix_'||v_name||'_link', v_name);
    EXECUTE format('CREATE INDEX %I ON traffic.%I (device_id, observed_at)', 'ix_'||v_name||'_device', v_name);
    EXECUTE format('CREATE INDEX %I ON traffic.%I (tenant_id, observed_at)', 'ix_'||v_name||'_tenant', v_name);
    RETURN v_name;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- ops.prc_maintain_partitions
-- Proposito : Unico job de particiones: pre-crea las de position y observation y suelta
--             las vencidas segun la retencion de cada una.
-- Parametros: p_months_ahead, p_result INOUT {ensured, dropped_position, dropped_observation}
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion (unifica tracking.prc_maintain y traffic.prc_maintain).
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE ops.prc_maintain_partitions(
    p_months_ahead int DEFAULT 2, INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_run_id  bigint;
    v_ensured int := 0; v_pos int := 0; v_obs int := 0;
    v_ret_pos int := public.fnc_setting_num('tracking.position_retention_days')::int;
    v_ret_obs int := public.fnc_setting_num('traffic.observation_retention_days')::int;
    v_cut_pos date; v_cut_obs date; r record;
BEGIN
    INSERT INTO ops.pipeline_run (pipeline_job_id, run_status_id)
    VALUES ('partition_maintenance','running') RETURNING id INTO v_run_id;

    FOR i IN 0..p_months_ahead LOOP
        PERFORM tracking.fnc_ensure_position_partition((current_date + (i||' month')::interval)::date);
        PERFORM traffic.fnc_ensure_observation_partition((current_date + (i||' month')::interval)::date);
        v_ensured := v_ensured + 2;
    END LOOP;

    v_cut_pos := date_trunc('month', current_date - (v_ret_pos||' day')::interval)::date;
    v_cut_obs := date_trunc('month', current_date - (v_ret_obs||' day')::interval)::date;

    FOR r IN
        SELECT n.nspname AS sch, c.relname AS rel
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE (n.nspname='tracking' AND c.relname ~ '^position_[0-9]{6}$'
               AND to_date(right(c.relname,6),'YYYYMM') < v_cut_pos)
           OR (n.nspname='traffic'  AND c.relname ~ '^observation_[0-9]{6}$'
               AND to_date(right(c.relname,6),'YYYYMM') < v_cut_obs)
    LOOP
        EXECUTE format('DROP TABLE %I.%I', r.sch, r.rel);
        IF r.sch = 'tracking' THEN v_pos := v_pos + 1; ELSE v_obs := v_obs + 1; END IF;
    END LOOP;

    UPDATE ops.pipeline_run SET run_status_id='success', finished_at=now(), row_count=v_pos+v_obs
     WHERE id = v_run_id;

    p_result := jsonb_build_object('ensured',v_ensured,'dropped_position',v_pos,'dropped_observation',v_obs);
END $$;

-- =====================================================================================
-- 15. ADMINISTRACION DE TENANT Y DISPOSITIVOS
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.prc_upsert_tenant
-- Proposito : Registra o actualiza un tenant.
-- Parametros: p_tenant_id, p_slug, p_name, p_kind, p_max_device, p_is_active
--             p_result INOUT {tenant_id, slug, created}
-- Errores   : VT020 tipo de tenant invalido
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE public.prc_upsert_tenant(
    p_tenant_id uuid, p_slug text, p_name text,
    p_kind text DEFAULT 'personal', p_max_device int DEFAULT NULL,
    p_is_active boolean DEFAULT true, INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_created boolean;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.tenant_kind WHERE id = p_kind) THEN
        RAISE EXCEPTION 'tenant_kind % invalido', p_kind USING ERRCODE = 'VT020';
    END IF;

    INSERT INTO public.tenant (id, slug, name, tenant_kind_id, max_device, is_active, updated_at)
    VALUES (p_tenant_id, lower(p_slug), p_name, p_kind, p_max_device, p_is_active, now())
    ON CONFLICT (id) DO UPDATE SET
        slug=EXCLUDED.slug, name=EXCLUDED.name, tenant_kind_id=EXCLUDED.tenant_kind_id,
        max_device=EXCLUDED.max_device, is_active=EXCLUDED.is_active, updated_at=now()
    RETURNING (xmax = 0) INTO v_created;

    p_result := jsonb_build_object('tenant_id',p_tenant_id,'slug',lower(p_slug),'created',v_created);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_register_device
-- Proposito : Registra o actualiza un dispositivo dentro de un tenant. Unico camino para
--             que exista un device, porque es donde se decide el aislamiento.
-- Parametros: p_device_id, p_tenant_id, p_install_id, p_platform, p_account_id,
--             p_os_version, p_app_version, p_model, p_result INOUT
-- Errores   : VT021 tenant inexistente o inactivo · VT022 cupo agotado
--             VT023 el device ya pertenece a otro tenant
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_register_device(
    p_device_id uuid, p_tenant_id uuid,
    p_install_id text DEFAULT NULL, p_platform text DEFAULT NULL,
    p_account_id uuid DEFAULT NULL, p_os_version text DEFAULT NULL,
    p_app_version text DEFAULT NULL, p_model text DEFAULT NULL,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_max int; v_count int; v_owner uuid; v_created boolean;
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

    INSERT INTO device.device (id, tenant_id, account_id, install_id, platform,
                               os_version, app_version, model, registered_at, last_seen_at)
    VALUES (p_device_id, p_tenant_id, p_account_id, p_install_id, p_platform,
            p_os_version, p_app_version, p_model, now(), now())
    ON CONFLICT (id) DO UPDATE SET
        account_id   = COALESCE(EXCLUDED.account_id,  device.account_id),
        install_id   = COALESCE(EXCLUDED.install_id,  device.install_id),
        platform     = COALESCE(EXCLUDED.platform,    device.platform),
        os_version   = COALESCE(EXCLUDED.os_version,  device.os_version),
        app_version  = COALESCE(EXCLUDED.app_version, device.app_version),
        model        = COALESCE(EXCLUDED.model,       device.model),
        last_seen_at = now()
    RETURNING (xmax = 0) INTO v_created;

    p_result := jsonb_build_object('device_id',p_device_id,'tenant_id',p_tenant_id,'created',v_created);
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

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_upsert_obd_session
-- Proposito : Registra o actualiza una sesion OBD (protocolo, adaptador, ventana).
-- Parametros: p_session_id, p_device_id, p_protocol (id o codigo ELM), p_trip_id,
--             p_adapter_name, p_started_at, p_ended_at, p_result INOUT
-- Errores   : VT001 device inexistente
-- Nota      : Protocolo no reconocido -> 'unknown'. Perder la telemetria del viaje por un
--             string raro del adaptador seria peor.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_upsert_obd_session(
    p_session_id uuid, p_device_id uuid, p_protocol text,
    p_trip_id uuid DEFAULT NULL, p_adapter_name text DEFAULT NULL,
    p_started_at timestamptz DEFAULT NULL, p_ended_at timestamptz DEFAULT NULL,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_protocol text; v_tenant uuid; v_created boolean;
BEGIN
    SELECT tenant_id INTO v_tenant FROM device.device WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device % no registrado', p_device_id USING ERRCODE = 'VT001';
    END IF;

    SELECT id INTO v_protocol FROM public.obd_protocol
     WHERE id = lower(coalesce(p_protocol,'')) OR elm_code = upper(coalesce(p_protocol,''))
     ORDER BY sort_order LIMIT 1;
    v_protocol := COALESCE(v_protocol, 'unknown');

    INSERT INTO device.obd_session (id, tenant_id, device_id, trip_id, obd_protocol_id,
                                    adapter_name, started_at, ended_at, updated_at)
    VALUES (p_session_id, v_tenant, p_device_id, p_trip_id, v_protocol, p_adapter_name,
            COALESCE(p_started_at, now()), p_ended_at, now())
    ON CONFLICT (id) DO UPDATE SET
        trip_id         = COALESCE(EXCLUDED.trip_id, obd_session.trip_id),
        obd_protocol_id = EXCLUDED.obd_protocol_id,
        adapter_name    = COALESCE(EXCLUDED.adapter_name, obd_session.adapter_name),
        ended_at        = COALESCE(EXCLUDED.ended_at, obd_session.ended_at),
        updated_at      = now()
    RETURNING (xmax = 0) INTO v_created;

    p_result := jsonb_build_object('session_id',p_session_id,'tenant_id',v_tenant,
                                   'obd_protocol_id',v_protocol,'created',v_created);
END $$;

-- =====================================================================================
-- 16. VIAJES
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- tracking.prc_upsert_trip
-- Proposito : Registra o actualiza un viaje. El id lo genera la app para crear sin conexion.
-- Parametros: p_trip_id, p_device_id, p_started_at, p_ended_at, p_status,
--             p_fuel_liters, p_cost_cop, p_result INOUT
-- Errores   : VT001 device inexistente · VT024 estado invalido
--             VT025 el viaje pertenece a otro device
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE tracking.prc_upsert_trip(
    p_trip_id uuid, p_device_id uuid, p_started_at timestamptz DEFAULT NULL,
    p_ended_at timestamptz DEFAULT NULL, p_status text DEFAULT 'active',
    p_fuel_liters numeric DEFAULT NULL, p_cost_cop numeric DEFAULT NULL,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_tenant uuid; v_account uuid; v_owner uuid; v_created boolean;
BEGIN
    SELECT tenant_id, account_id INTO v_tenant, v_account FROM device.device WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device % no registrado', p_device_id USING ERRCODE = 'VT001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.trip_status WHERE id = p_status) THEN
        RAISE EXCEPTION 'trip_status % invalido', p_status USING ERRCODE = 'VT024';
    END IF;

    SELECT device_id INTO v_owner FROM tracking.trip WHERE id = p_trip_id;
    IF FOUND AND v_owner <> p_device_id THEN
        RAISE EXCEPTION 'trip % pertenece a otro device', p_trip_id USING ERRCODE = 'VT025';
    END IF;

    INSERT INTO tracking.trip (id, tenant_id, device_id, account_id, trip_status_id,
                               started_at, ended_at, fuel_liters, cost_cop, updated_at)
    VALUES (p_trip_id, v_tenant, p_device_id, v_account, p_status,
            COALESCE(p_started_at, now()), p_ended_at, p_fuel_liters, p_cost_cop, now())
    ON CONFLICT (id) DO UPDATE SET
        trip_status_id = EXCLUDED.trip_status_id,
        ended_at       = COALESCE(EXCLUDED.ended_at,     trip.ended_at),
        fuel_liters    = COALESCE(EXCLUDED.fuel_liters,  trip.fuel_liters),
        cost_cop       = COALESCE(EXCLUDED.cost_cop,     trip.cost_cop),
        updated_at     = now()
    RETURNING (xmax = 0) INTO v_created;

    p_result := jsonb_build_object('trip_id',p_trip_id,'tenant_id',v_tenant,'created',v_created);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- tracking.prc_close_trip
-- Proposito : Cierra un viaje: materializa la traza en trip_track y calcula distancia,
--             velocidades y conteo de puntos. Es lo que permite borrar position a los 90
--             dias sin perder el viaje.
-- Parametros: p_trip_id, p_result INOUT {trip_id, point_count, distance_m, max/avg}
-- Errores   : VT026 viaje inexistente · VT027 viaje sin puntos suficientes
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE tracking.prc_close_trip(
    p_trip_id uuid, INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_tenant uuid; v_tol numeric := public.fnc_setting_num('tracking.simplify_tolerance_deg');
    v_geom geometry; v_n int; v_dist numeric; v_max numeric; v_avg numeric;
BEGIN
    SELECT tenant_id INTO v_tenant FROM tracking.trip WHERE id = p_trip_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'trip % inexistente', p_trip_id USING ERRCODE = 'VT026';
    END IF;

    SELECT ST_MakeLine(p.geom ORDER BY p.recorded_at), count(*),
           max(p.speed_kmh), avg(p.speed_kmh)
      INTO v_geom, v_n, v_max, v_avg
      FROM tracking.position p WHERE p.trip_id = p_trip_id;

    IF v_n IS NULL OR v_n < 2 THEN
        RAISE EXCEPTION 'trip % no tiene puntos suficientes para cerrarse', p_trip_id
            USING ERRCODE = 'VT027';
    END IF;

    v_dist := ST_Length(v_geom::geography);

    INSERT INTO tracking.trip_track (trip_id, tenant_id, geom, geom_simplified, source_point_count)
    VALUES (p_trip_id, v_tenant, v_geom, ST_SimplifyPreserveTopology(v_geom, v_tol), v_n)
    ON CONFLICT (trip_id) DO UPDATE SET
        geom = EXCLUDED.geom, geom_simplified = EXCLUDED.geom_simplified,
        source_point_count = EXCLUDED.source_point_count, materialized_at = now();

    UPDATE tracking.trip
       SET trip_status_id = 'closed',
           ended_at       = COALESCE(ended_at, (SELECT max(recorded_at) FROM tracking.position WHERE trip_id = p_trip_id)),
           distance_m     = round(v_dist, 2),
           max_speed_kmh  = round(v_max, 2),
           avg_speed_kmh  = round(v_avg, 2),
           point_count    = v_n,
           updated_at     = now()
     WHERE id = p_trip_id;

    p_result := jsonb_build_object('trip_id',p_trip_id,'point_count',v_n,
                                   'distance_m',round(v_dist,2),
                                   'max_speed_kmh',round(v_max,2),'avg_speed_kmh',round(v_avg,2));
END $$;

-- =====================================================================================
-- 17. INGESTA DE TELEMETRIA — unico punto de escritura
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- tracking.prc_ingest_telemetry
-- Proposito : Reemplaza el insert a BigQuery. En una transaccion:
--               1) upsert de tracking.position (GPS + OBD),
--               2) derivacion de traffic.observation,
--               3) contadores del lote y de la sesion OBD.
-- Parametros: p_device_id, p_batch_id (uuid v7, idempotencia), p_client_created_at,
--             p_samples jsonb:
--               [{"lat":10.99,"lon":-74.79,"recorded_at":"2026-08-01T12:00:00Z",
--                 "speed_gps_kmh":32.4,"speed_obd_kmh":33.0,"bearing_deg":275,
--                 "accuracy_m":8.5,"altitude_m":14,"rpm":1850,"coolant_temp_c":88,
--                 "fuel_level_pct":54.5,"trip_id":null,"obd_session_id":null,"source":"obd"}]
--             p_result INOUT {batch_id, duplicate, tenant_id, received, inserted, updated,
--                             rejected, traffic_observations}
-- Errores   : VT001 device inexistente · VT002 device bloqueado · VT003 lote de otro device
-- Reglas    : - Reenviar el mismo (device, recorded_at) ACTUALIZA con COALESCE: un reenvio
--               parcial nunca borra un dato que ya estaba.
--             - speed_kmh = OBD si vino, si no GPS. position_source_id lo deja explicito.
--             - Sin bearing_deg se calcula con ST_Azimuth contra el punto anterior del lote:
--               sin rumbo no hay sentido y el trancon se diluye.
--             - Solo aportan a trafico las muestras con precision y velocidad plausibles.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion (unifica ingesta de telemetria y de trafico,
--                                        con tenant_id desde el inicio).
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE tracking.prc_ingest_telemetry(
    p_device_id uuid, p_batch_id uuid, p_samples jsonb,
    p_client_created_at timestamptz DEFAULT NULL, INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_blocked   boolean; v_tenant uuid; v_owner uuid; v_existing record;
    v_pos_acc   numeric  := public.fnc_setting_num('tracking.max_accuracy_m');
    v_max_alt   numeric  := public.fnc_setting_num('tracking.max_altitude_m');
    v_tr_acc    numeric  := public.fnc_setting_num('traffic.max_accuracy_m');
    v_max_speed numeric  := public.fnc_setting_num('traffic.max_speed_kmh');
    v_min_rpm   numeric  := public.fnc_setting_num('obd.min_rpm');
    v_max_rpm   numeric  := public.fnc_setting_num('obd.max_rpm');
    v_min_temp  numeric  := public.fnc_setting_num('obd.min_coolant_temp_c');
    v_max_temp  numeric  := public.fnc_setting_num('obd.max_coolant_temp_c');
    v_skew      interval := (public.fnc_setting_num('traffic.max_future_skew_minutes')||' minute')::interval;
    v_past      interval := (public.fnc_setting_num('traffic.max_past_days')||' day')::interval;
    v_tz        text     := public.fnc_setting_text('locale.timezone');
    v_total int := 0; v_inserted int := 0; v_updated int := 0; v_traffic int := 0;
    m date;
BEGIN
    SELECT is_blocked, tenant_id INTO v_blocked, v_tenant FROM device.device WHERE id = p_device_id;
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
        p_result := jsonb_build_object('batch_id',p_batch_id,'duplicate',true,
            'received',v_existing.item_count,'accepted',v_existing.accepted_count,
            'rejected',v_existing.rejected_count);
        RETURN;
    END IF;

    v_total := COALESCE(jsonb_array_length(p_samples), 0);

    INSERT INTO tracking.ingest_batch (id, tenant_id, device_id, payload_kind_id, item_count, client_created_at)
    VALUES (p_batch_id, v_tenant, p_device_id, 'telemetry', v_total, p_client_created_at);

    FOR m IN
        SELECT DISTINCT date_trunc('month', (s ->> 'recorded_at')::timestamptz)::date
        FROM jsonb_array_elements(COALESCE(p_samples,'[]'::jsonb)) s
        WHERE (s ->> 'recorded_at') IS NOT NULL
    LOOP
        PERFORM tracking.fnc_ensure_position_partition(m);
        PERFORM traffic.fnc_ensure_observation_partition(m);
    END LOOP;

    DROP TABLE IF EXISTS _tele;
    CREATE TEMP TABLE _tele ON COMMIT DROP AS
    WITH raw AS (
        SELECT * FROM jsonb_to_recordset(COALESCE(p_samples,'[]'::jsonb)) AS s(
            lat double precision, lon double precision, recorded_at timestamptz,
            speed_gps_kmh numeric, speed_obd_kmh numeric, bearing_deg numeric,
            accuracy_m numeric, altitude_m numeric, rpm numeric,
            coolant_temp_c numeric, fuel_level_pct numeric,
            trip_id uuid, obd_session_id uuid, source text)
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
        v.geom, v.recorded_at,
        (SELECT t.id FROM tracking.trip t WHERE t.id = v.trip_id)             AS trip_id,
        (SELECT o.id FROM device.obd_session o WHERE o.id = v.obd_session_id) AS obd_session_id,
        CASE WHEN v.speed_gps_kmh BETWEEN 0 AND v_max_speed THEN round(v.speed_gps_kmh,2) END AS speed_gps_kmh,
        CASE WHEN v.speed_obd_kmh BETWEEN 0 AND v_max_speed THEN round(v.speed_obd_kmh,2) END AS speed_obd_kmh,
        COALESCE(
            CASE WHEN v.speed_obd_kmh BETWEEN 0 AND v_max_speed THEN round(v.speed_obd_kmh,2) END,
            CASE WHEN v.speed_gps_kmh BETWEEN 0 AND v_max_speed THEN round(v.speed_gps_kmh,2) END
        ) AS speed_kmh,
        CASE WHEN v.source IN (SELECT id FROM public.position_source) THEN v.source
             WHEN v.speed_obd_kmh IS NOT NULL THEN 'obd'
             ELSE 'gps' END AS position_source_id,
        COALESCE(
            CASE WHEN v.bearing_deg IS NOT NULL THEN ((v.bearing_deg % 360) + 360) % 360 END,
            round(degrees(ST_Azimuth(lag(v.geom) OVER (ORDER BY v.recorded_at), v.geom))::numeric, 2)
        ) AS bearing_deg,
        round(v.accuracy_m,2) AS accuracy_m,
        CASE WHEN abs(v.altitude_m) <= v_max_alt THEN round(v.altitude_m,2) END AS altitude_m,
        CASE WHEN v.rpm BETWEEN v_min_rpm AND v_max_rpm THEN round(v.rpm,2) END AS rpm,
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
        RETURNING 1
    )
    SELECT count(*) INTO v_inserted FROM ins;
    -- Particiones no permiten RETURNING (xmax=0); se reporta el total tocado como inserted.
    v_updated := 0;

    WITH src AS (
        SELECT t.*, traffic.fnc_resolve_grid_link(
                        geo.fnc_resolve_grid_cell(t.geom),
                        public.fnc_heading_bucket_of(t.bearing_deg)) AS traffic_link_id
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

    p_result := jsonb_build_object('batch_id',p_batch_id,'duplicate',false,'tenant_id',v_tenant,
        'received',v_total,'inserted',v_inserted,'updated',v_updated,
        'rejected',v_total-(v_inserted+v_updated),'traffic_observations',v_traffic);
END $$;

-- =====================================================================================
-- 18. ROLLUPS DE TRAFICO (corren como dueno: ven todos los tenants)
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.prc_rollup_live
-- Proposito : Recalcula traffic.live_state con la ventana de observaciones reciente.
-- Parametros: p_window_minutes, p_result INOUT {links_updated, window_minutes}
-- Errores   : ninguno
-- Nota      : No incrementa observation_count: las ventanas se solapan. Ese contador lo
--             recalcula prc_rollup_profile de forma exacta.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE traffic.prc_rollup_live(
    p_window_minutes int DEFAULT NULL, INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_run_id bigint;
    v_win int := COALESCE(p_window_minutes, public.fnc_setting_num('traffic.live_window_minutes')::int);
    v_ttl int := public.fnc_setting_num('traffic.live_ttl_minutes')::int;
    v_from timestamptz := now() - (v_win||' minute')::interval;
    v_rows int := 0;
BEGIN
    INSERT INTO ops.pipeline_run (pipeline_job_id, run_status_id)
    VALUES ('traffic_rollup_live','running') RETURNING id INTO v_run_id;

    WITH w AS (
        SELECT o.traffic_link_id,
               percentile_cont(0.5) WITHIN GROUP (ORDER BY o.speed_kmh)::numeric(5,2) AS p50,
               count(*)::int AS samples, count(DISTINCT o.device_id)::int AS devices,
               min(o.observed_at) AS win_start, max(o.observed_at) AS win_end
        FROM traffic.observation o WHERE o.observed_at >= v_from
        GROUP BY o.traffic_link_id
    ),
    calc AS (
        SELECT w.*, CASE WHEN l.free_flow_speed_kmh > 0
                         THEN round(w.p50 / l.free_flow_speed_kmh, 3) END AS ratio
        FROM w JOIN traffic.link l ON l.id = w.traffic_link_id
    )
    INSERT INTO traffic.live_state (traffic_link_id, speed_p50_kmh, congestion_ratio,
        congestion_level_id, sample_count, device_count, window_start_at, window_end_at,
        expires_at, updated_at)
    SELECT traffic_link_id, p50, ratio, traffic.fnc_congestion_level_of(ratio),
           samples, devices, win_start, win_end, now() + (v_ttl||' minute')::interval, now()
    FROM calc
    ON CONFLICT (traffic_link_id) DO UPDATE SET
        speed_p50_kmh=EXCLUDED.speed_p50_kmh, congestion_ratio=EXCLUDED.congestion_ratio,
        congestion_level_id=EXCLUDED.congestion_level_id, sample_count=EXCLUDED.sample_count,
        device_count=EXCLUDED.device_count, window_start_at=EXCLUDED.window_start_at,
        window_end_at=EXCLUDED.window_end_at, expires_at=EXCLUDED.expires_at, updated_at=now();

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    UPDATE traffic.link l SET last_seen_at = ls.window_end_at
      FROM traffic.live_state ls
     WHERE ls.traffic_link_id = l.id AND ls.updated_at >= v_from
       AND ls.window_end_at > l.last_seen_at;

    UPDATE ops.pipeline_run SET run_status_id='success', finished_at=now(), row_count=v_rows
     WHERE id = v_run_id;

    p_result := jsonb_build_object('links_updated',v_rows,'window_minutes',v_win);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.prc_rollup_profile
-- Proposito : Consolida una ventana cerrada en traffic.profile. Suma histogramas y
--             recalcula percentiles sobre 12 numeros: nunca relee el historico.
-- Parametros: p_from, p_to, p_result INOUT {profile_rows, from, to}
-- Errores   : VT011 ventana invalida
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE traffic.prc_rollup_profile(
    p_from timestamptz, p_to timestamptz, INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_run_id bigint; v_rows int := 0;
BEGIN
    IF p_to <= p_from THEN
        RAISE EXCEPTION 'ventana invalida' USING ERRCODE = 'VT011';
    END IF;

    INSERT INTO ops.pipeline_run (pipeline_job_id, run_status_id)
    VALUES ('traffic_rollup_profile','running') RETURNING id INTO v_run_id;

    DROP TABLE IF EXISTS _touched;
    CREATE TEMP TABLE _touched (
        traffic_link_id bigint, day_kind_id text, time_slot_id smallint) ON COMMIT DROP;

    WITH buckets AS (
        SELECT o.traffic_link_id, o.day_kind_id, o.time_slot_id, sb.id AS bucket_id, count(*) AS cnt
        FROM traffic.observation o
        JOIN public.speed_bucket sb ON o.speed_kmh >= sb.min_kmh AND o.speed_kmh < sb.max_kmh
        WHERE o.observed_at >= p_from AND o.observed_at < p_to
        GROUP BY 1,2,3,4
    ),
    devices AS (
        SELECT o.traffic_link_id, o.day_kind_id, o.time_slot_id,
               count(DISTINCT o.device_id)::int AS devices
        FROM traffic.observation o
        WHERE o.observed_at >= p_from AND o.observed_at < p_to
        GROUP BY 1,2,3
    ),
    agg AS (
        SELECT b.traffic_link_id, b.day_kind_id, b.time_slot_id,
               jsonb_object_agg(b.bucket_id::text, b.cnt) AS hist,
               sum(b.cnt)::bigint AS samples, d.devices
        FROM buckets b JOIN devices d USING (traffic_link_id, day_kind_id, time_slot_id)
        GROUP BY b.traffic_link_id, b.day_kind_id, b.time_slot_id, d.devices
    ),
    up AS (
        INSERT INTO traffic.profile (traffic_link_id, day_kind_id, time_slot_id, speed_histogram,
            sample_count, device_count, covers_from_at, covers_to_at, updated_at)
        SELECT traffic_link_id, day_kind_id, time_slot_id, hist, samples, devices, p_from, p_to, now()
        FROM agg
        ON CONFLICT (traffic_link_id, day_kind_id, time_slot_id) DO UPDATE SET
            speed_histogram = traffic.fnc_merge_histogram(profile.speed_histogram, EXCLUDED.speed_histogram),
            sample_count    = profile.sample_count + EXCLUDED.sample_count,
            device_count    = GREATEST(profile.device_count, EXCLUDED.device_count),
            covers_from_at  = LEAST(COALESCE(profile.covers_from_at, EXCLUDED.covers_from_at), EXCLUDED.covers_from_at),
            covers_to_at    = GREATEST(COALESCE(profile.covers_to_at, EXCLUDED.covers_to_at), EXCLUDED.covers_to_at),
            updated_at      = now()
        RETURNING traffic_link_id, day_kind_id, time_slot_id
    )
    INSERT INTO _touched SELECT * FROM up;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    UPDATE traffic.profile p
       SET speed_p50_kmh = traffic.fnc_percentile_from_histogram(p.speed_histogram, 0.50),
           speed_p85_kmh = traffic.fnc_percentile_from_histogram(p.speed_histogram, 0.85),
           congestion_ratio = CASE WHEN l.free_flow_speed_kmh > 0
               THEN round(traffic.fnc_percentile_from_histogram(p.speed_histogram,0.50)
                          / l.free_flow_speed_kmh, 3) END
      FROM _touched t JOIN traffic.link l ON l.id = t.traffic_link_id
     WHERE p.traffic_link_id = t.traffic_link_id
       AND p.day_kind_id = t.day_kind_id AND p.time_slot_id = t.time_slot_id;

    UPDATE traffic.link l SET observation_count = a.total
      FROM (SELECT p.traffic_link_id, sum(p.sample_count) AS total
              FROM traffic.profile p
             WHERE p.traffic_link_id IN (SELECT DISTINCT traffic_link_id FROM _touched)
             GROUP BY p.traffic_link_id) a
     WHERE l.id = a.traffic_link_id;

    UPDATE ops.pipeline_run SET run_status_id='success', finished_at=now(), row_count=v_rows
     WHERE id = v_run_id;

    p_result := jsonb_build_object('profile_rows',v_rows,'from',p_from,'to',p_to);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.prc_recompute_free_flow
-- Proposito : Recalcula la velocidad de flujo libre por link como p85 nocturno propio.
--             Fallback al limite de OSM solo para links de tipo segmento.
-- Parametros: p_days, p_result INOUT {links_updated, window_days}
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE traffic.prc_recompute_free_flow(
    p_days int DEFAULT 28, INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_run_id bigint;
    v_from smallint := public.fnc_setting_num('traffic.free_flow_night_from_hour')::smallint;
    v_to   smallint := public.fnc_setting_num('traffic.free_flow_night_to_hour')::smallint;
    v_min  int      := public.fnc_setting_num('traffic.free_flow_min_samples')::int;
    v_rows int := 0;
BEGIN
    INSERT INTO ops.pipeline_run (pipeline_job_id, run_status_id)
    VALUES ('traffic_free_flow','running') RETURNING id INTO v_run_id;

    WITH night AS (
        SELECT o.traffic_link_id,
               percentile_cont(0.85) WITHIN GROUP (ORDER BY o.speed_kmh)::numeric(5,2) AS p85,
               count(*)::int AS samples
        FROM traffic.observation o
        WHERE o.observed_at >= now() - (p_days||' day')::interval
          AND o.time_slot_id BETWEEN v_from*2 AND v_to*2 - 1
          AND o.speed_kmh > 0
        GROUP BY o.traffic_link_id
        HAVING count(*) >= v_min
    )
    UPDATE traffic.link l
       SET free_flow_speed_kmh = n.p85, free_flow_sample_count = n.samples,
           free_flow_computed_at = now()
      FROM night n WHERE l.id = n.traffic_link_id;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    UPDATE traffic.link l
       SET free_flow_speed_kmh = s.speed_limit_kmh, free_flow_computed_at = now()
      FROM geo.street_segment s
     WHERE l.street_segment_id = s.id AND l.free_flow_speed_kmh IS NULL
       AND s.speed_limit_kmh IS NOT NULL;

    UPDATE ops.pipeline_run SET run_status_id='success', finished_at=now(), row_count=v_rows
     WHERE id = v_run_id;

    p_result := jsonb_build_object('links_updated',v_rows,'window_days',p_days);
END $$;

-- =====================================================================================
-- 19. LECTURA
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.fnc_live_by_bbox
-- Proposito : Trafico vivo por bbox. Filtra vencidos y aplica k-anonimato DENTRO de la BD.
-- Parametros: bbox, p_min_device_count
-- Retorna   : SETOF link + estado + color
-- Errores   : ninguno
-- Nota      : Es global a proposito: el mapa de trafico no se filtra por tenant.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION traffic.fnc_live_by_bbox(
    p_min_lon double precision, p_min_lat double precision,
    p_max_lon double precision, p_max_lat double precision,
    p_min_device_count int DEFAULT NULL
) RETURNS TABLE (
    traffic_link_id bigint, link_kind_id text, grid_cell_id text, heading_bucket_id smallint,
    geom geometry, speed_p50_kmh numeric, free_flow_speed_kmh numeric,
    congestion_ratio numeric, congestion_level_id text, color_hex char(7),
    sample_count int, device_count int, window_end_at timestamptz
) LANGUAGE sql STABLE AS $$
    SELECT l.id, l.link_kind_id, l.grid_cell_id, l.heading_bucket_id, l.geom,
           s.speed_p50_kmh, l.free_flow_speed_kmh, s.congestion_ratio,
           s.congestion_level_id, cl.color_hex, s.sample_count, s.device_count, s.window_end_at
    FROM traffic.live_state s
    JOIN traffic.link l ON l.id = s.traffic_link_id AND l.is_active
    LEFT JOIN public.congestion_level cl ON cl.id = s.congestion_level_id
    WHERE s.expires_at > now()
      AND s.device_count >= COALESCE(p_min_device_count,
                                     public.fnc_setting_num('traffic.min_device_count')::int)
      AND l.geom && ST_MakeEnvelope(p_min_lon, p_min_lat, p_max_lon, p_max_lat, 4326);
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.fnc_profile_by_bbox
-- Proposito : Perfil tipico por bbox para el momento indicado (day_kind + slot).
-- Parametros: bbox, p_at, p_min_device_count
-- Retorna   : SETOF perfil por link
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION traffic.fnc_profile_by_bbox(
    p_min_lon double precision, p_min_lat double precision,
    p_max_lon double precision, p_max_lat double precision,
    p_at timestamptz DEFAULT now(), p_min_device_count int DEFAULT NULL
) RETURNS TABLE (
    traffic_link_id bigint, geom geometry, day_kind_id text, time_slot_id smallint,
    speed_p50_kmh numeric, speed_p85_kmh numeric, congestion_ratio numeric,
    congestion_level_id text, sample_count bigint, device_count int
) LANGUAGE sql STABLE AS $$
    SELECT p.traffic_link_id, l.geom, p.day_kind_id, p.time_slot_id,
           p.speed_p50_kmh, p.speed_p85_kmh, p.congestion_ratio,
           traffic.fnc_congestion_level_of(p.congestion_ratio), p.sample_count, p.device_count
    FROM traffic.profile p
    JOIN traffic.link l ON l.id = p.traffic_link_id AND l.is_active
    WHERE p.day_kind_id  = public.fnc_day_kind_of(p_at)
      AND p.time_slot_id = public.fnc_time_slot_of(p_at)
      AND p.device_count >= COALESCE(p_min_device_count,
                                     public.fnc_setting_num('traffic.min_device_count')::int)
      AND l.geom && ST_MakeEnvelope(p_min_lon, p_min_lat, p_max_lon, p_max_lat, 4326);
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.fnc_profile_for_links
-- Proposito : Perfil de un conjunto de links para ETA y prediccion de ruta frecuente.
--             Devuelve is_reliable en vez de esconder la fila: el consumidor decide.
-- Parametros: p_link_ids, p_at
-- Retorna   : SETOF (link, p50, ratio, muestras, is_reliable)
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION traffic.fnc_profile_for_links(
    p_link_ids bigint[], p_at timestamptz DEFAULT now()
) RETURNS TABLE (
    traffic_link_id bigint, speed_p50_kmh numeric, congestion_ratio numeric,
    sample_count bigint, is_reliable boolean
) LANGUAGE sql STABLE AS $$
    SELECT p.traffic_link_id, p.speed_p50_kmh, p.congestion_ratio, p.sample_count,
           p.device_count >= public.fnc_setting_num('traffic.min_device_count')::int
    FROM traffic.profile p
    WHERE p.traffic_link_id = ANY (p_link_ids)
      AND p.day_kind_id  = public.fnc_day_kind_of(p_at)
      AND p.time_slot_id = public.fnc_time_slot_of(p_at);
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.fnc_aggregates_by_corridor
-- Proposito : Compatibilidad con GET /traffic/aggregates?corridor=&slot=.
--             Lee live_state (no DML) y proyecta la forma que consume la app.
-- Parametros: p_corridor (geohash padre), p_slot (0..47, NULL = franja actual),
--             p_min_device_count
-- Retorna   : SETOF (cell, slot, corridor, median_speed_kmh, sample_count, device_count)
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion (reemplaza SELECT directo a traffic_aggregates).
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION traffic.fnc_aggregates_by_corridor(
    p_corridor text,
    p_slot smallint DEFAULT NULL,
    p_min_device_count int DEFAULT NULL
) RETURNS TABLE (
    cell text, slot smallint, corridor text,
    median_speed_kmh numeric, sample_count int, device_count int
) LANGUAGE sql STABLE AS $$
    WITH params AS (
        SELECT COALESCE(p_slot, public.fnc_time_slot_of(now())) AS want_slot,
               COALESCE(p_min_device_count,
                        public.fnc_setting_num('traffic.min_device_count')::int) AS min_dev
    )
    SELECT l.grid_cell_id AS cell,
           p.want_slot AS slot,
           left(l.grid_cell_id, length(p_corridor)) AS corridor,
           s.speed_p50_kmh AS median_speed_kmh,
           s.sample_count,
           s.device_count
    FROM traffic.live_state s
    JOIN traffic.link l ON l.id = s.traffic_link_id AND l.is_active
    CROSS JOIN params p
    WHERE s.expires_at > now()
      AND s.device_count >= p.min_dev
      AND left(l.grid_cell_id, length(p_corridor)) = p_corridor
    ORDER BY s.sample_count DESC
    LIMIT 200;
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- tracking.fnc_telemetry_by_trip
-- Proposito : Telemetria completa de un viaje. Reemplaza el SELECT contra BigQuery.
-- Parametros: p_trip_id, p_max_points (0 = sin tope)
-- Retorna   : SETOF telemetria ordenada por recorded_at
-- Errores   : ninguno
-- Nota      : Sujeta a RLS: solo devuelve datos del tenant de la transaccion.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tracking.fnc_telemetry_by_trip(
    p_trip_id uuid, p_max_points int DEFAULT 0
) RETURNS TABLE (
    recorded_at timestamptz, lat double precision, lon double precision,
    speed_kmh numeric, speed_gps_kmh numeric, speed_obd_kmh numeric,
    position_source_id text, bearing_deg numeric, altitude_m numeric,
    rpm numeric, coolant_temp_c numeric, fuel_level_pct numeric, obd_protocol_id text
) LANGUAGE sql STABLE AS $$
    SELECT p.recorded_at, ST_Y(p.geom), ST_X(p.geom), p.speed_kmh, p.speed_gps_kmh,
           p.speed_obd_kmh, p.position_source_id, p.bearing_deg, p.altitude_m,
           p.rpm, p.coolant_temp_c, p.fuel_level_pct, s.obd_protocol_id
    FROM tracking.position p
    LEFT JOIN device.obd_session s ON s.id = p.obd_session_id
    WHERE p.trip_id = p_trip_id
    ORDER BY p.recorded_at
    LIMIT NULLIF(p_max_points, 0);
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- tracking.fnc_telemetry_last
-- Proposito : Ultimo estado conocido de un device (head unit y panel).
-- Parametros: p_device_id
-- Retorna   : una fila
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tracking.fnc_telemetry_last(p_device_id uuid)
RETURNS TABLE (
    recorded_at timestamptz, lat double precision, lon double precision,
    speed_kmh numeric, rpm numeric, coolant_temp_c numeric,
    fuel_level_pct numeric, trip_id uuid
) LANGUAGE sql STABLE AS $$
    SELECT p.recorded_at, ST_Y(p.geom), ST_X(p.geom), p.speed_kmh,
           p.rpm, p.coolant_temp_c, p.fuel_level_pct, p.trip_id
    FROM tracking.position p
    WHERE p.device_id = p_device_id
    ORDER BY p.recorded_at DESC LIMIT 1;
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- public.fnc_tenant_usage
-- Proposito : Consumo por tenant. Base para limites, facturacion y para detectar abuso.
-- Parametros: p_from, p_to
-- Retorna   : SETOF por tenant
-- Errores   : ninguno
-- Nota      : SECURITY DEFINER para consolidar todos los tenants. NO se otorga al rol de
--             la app: es de administracion.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnc_tenant_usage(p_from timestamptz, p_to timestamptz)
RETURNS TABLE (
    tenant_id uuid, slug text, device_count bigint, batch_count bigint,
    position_count bigint, observation_count bigint
) LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT t.id, t.slug,
      (SELECT count(*) FROM device.device d WHERE d.tenant_id = t.id),
      (SELECT count(*) FROM tracking.ingest_batch b
        WHERE b.tenant_id = t.id AND b.received_at >= p_from AND b.received_at < p_to),
      (SELECT count(*) FROM tracking.position p
        WHERE p.tenant_id = t.id AND p.recorded_at >= p_from AND p.recorded_at < p_to),
      (SELECT count(*) FROM traffic.observation o
        WHERE o.tenant_id = t.id AND o.observed_at >= p_from AND o.observed_at < p_to)
    FROM public.tenant t WHERE t.is_active ORDER BY t.slug;
$$;

-- =====================================================================================
-- 20. CARGA INICIAL
-- =====================================================================================

CALL public.prc_generate_holiday(2020, 2040, NULL);
CALL ops.prc_maintain_partitions(2, NULL);

-- =====================================================================================
-- 21. REGISTRO DE RUTINAS (C3)
-- =====================================================================================

INSERT INTO public.db_routine (schema_name, routine_name, routine_type, purpose, author, version, migration) VALUES
 ('public','fnc_setting_num','function','Lee parametro numerico de app_setting','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('public','fnc_setting_text','function','Lee parametro de texto de app_setting','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('public','fnc_current_tenant','function','Tenant de la transaccion (GUC app.tenant_id)','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('public','fnc_easter_sunday','function','Domingo de Pascua (Meeus/Butcher)','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('public','fnc_emiliani','function','Traslado de festivo al lunes (Ley 51/1983)','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('public','prc_generate_holiday','procedure','Genera festivos colombianos por rango de anios','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('public','fnc_day_kind_of','function','Clasifica instante en weekday/saturday/sunday_holiday','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('public','fnc_time_slot_of','function','Franja de 30 min de un instante','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('public','fnc_heading_bucket_of','function','Rumbo en grados a sector de 45','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('public','prc_upsert_tenant','procedure','Registro o actualizacion de tenant','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('public','fnc_tenant_usage','function','Consumo por tenant para limites y facturacion','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('device','prc_register_device','procedure','Registro o actualizacion de device dentro de un tenant','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('device','fnc_tenant_of_device','function','Tenant dueno de un device','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('device','prc_upsert_obd_session','procedure','Registro o actualizacion de sesion OBD','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('tracking','prc_upsert_trip','procedure','Registro o actualizacion de viaje','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('tracking','prc_close_trip','procedure','Cierra viaje y materializa trip_track','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('tracking','prc_ingest_telemetry','procedure','Ingesta de telemetria GPS+OBD y derivacion a trafico','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('tracking','fnc_ensure_position_partition','function','Crea particion mensual de position','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('tracking','fnc_telemetry_by_trip','function','Telemetria completa de un viaje','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('tracking','fnc_telemetry_last','function','Ultimo estado conocido de un device','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('geo','fnc_resolve_grid_cell','function','Resuelve/crea celda geohash y su corredor','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('traffic','fnc_resolve_grid_link','function','Resuelve/crea link celda+sentido','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('traffic','fnc_congestion_level_of','function','Ratio a nivel de congestion diccionado','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('traffic','fnc_merge_histogram','function','Suma dos histogramas de velocidad','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('traffic','fnc_percentile_from_histogram','function','Percentil interpolado sobre speed_bucket','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('traffic','fnc_ensure_observation_partition','function','Crea particion mensual de observation','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('traffic','prc_rollup_live','procedure','Rollup de estado vivo','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('traffic','prc_rollup_profile','procedure','Rollup incremental de perfil','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('traffic','prc_recompute_free_flow','procedure','Recalculo de flujo libre p85 nocturno','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('traffic','fnc_live_by_bbox','function','Trafico vivo por bbox con k-anonimato','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('traffic','fnc_profile_by_bbox','function','Perfil tipico por bbox','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('traffic','fnc_profile_for_links','function','Perfil por lista de links para ETA','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('traffic','fnc_aggregates_by_corridor','function','Agregados vivos por corredor (API Copiloto)','Lucho · Devitech','1.0.0','001_vehitrack.sql'),
 ('ops','prc_maintain_partitions','procedure','Particiones y retencion de position y observation','Lucho · Devitech','1.0.0','001_vehitrack.sql')
ON CONFLICT (schema_name, routine_name) DO UPDATE SET
    purpose=EXCLUDED.purpose, author=EXCLUDED.author,
    version=EXCLUDED.version, migration=EXCLUDED.migration, updated_at=now();

-- =====================================================================================
-- 22. ROL DE APLICACION (C8)
-- =====================================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vehitrack_app') THEN
        CREATE ROLE vehitrack_app NOLOGIN;
    END IF;
END $$;

GRANT USAGE ON SCHEMA public, geo, device, tracking, traffic, ops TO vehitrack_app;

GRANT SELECT ON
    public.app_setting, public.tenant, public.tenant_kind, public.payload_kind,
    public.trip_status, public.day_kind, public.holiday, public.time_slot,
    public.heading_bucket, public.link_kind, public.congestion_level, public.speed_bucket,
    public.position_source, public.obd_protocol, public.db_routine
TO vehitrack_app;

GRANT EXECUTE ON FUNCTION
    public.fnc_current_tenant(),
    public.fnc_day_kind_of(timestamptz, text),
    public.fnc_time_slot_of(timestamptz, text),
    device.fnc_tenant_of_device(uuid),
    tracking.fnc_telemetry_by_trip(uuid, int),
    tracking.fnc_telemetry_last(uuid),
    traffic.fnc_live_by_bbox(double precision, double precision, double precision, double precision, int),
    traffic.fnc_profile_by_bbox(double precision, double precision, double precision, double precision, timestamptz, int),
    traffic.fnc_profile_for_links(bigint[], timestamptz),
    traffic.fnc_aggregates_by_corridor(text, smallint, int)
TO vehitrack_app;

GRANT EXECUTE ON PROCEDURE
    device.prc_register_device(uuid, uuid, text, text, uuid, text, text, text, jsonb),
    device.prc_upsert_obd_session(uuid, uuid, text, uuid, text, timestamptz, timestamptz, jsonb),
    tracking.prc_upsert_trip(uuid, uuid, timestamptz, timestamptz, text, numeric, numeric, jsonb),
    tracking.prc_close_trip(uuid, jsonb),
    tracking.prc_ingest_telemetry(uuid, uuid, jsonb, timestamptz, jsonb)
TO vehitrack_app;

-- administracion: no van al rol de la app
REVOKE EXECUTE ON FUNCTION public.fnc_tenant_usage(timestamptz, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE public.prc_upsert_tenant(uuid, text, text, text, int, boolean, jsonb) FROM PUBLIC;

COMMIT;

-- =====================================================================================
-- 23. CONTRATO CON EL ms
--
-- Toda transaccion del ms abre con el tenant:
--   BEGIN;
--   SET LOCAL app.tenant_id = '<uuid del tenant>';
--   CALL tracking.prc_ingest_telemetry($1,$2,$3,$4,NULL);
--   COMMIT;
--
-- SET LOCAL, no SET: con pool de conexiones un SET normal se queda pegado y el siguiente
-- request hereda el tenant del anterior. Ese es EL bug clasico de multi-tenant con RLS,
-- y no da error: da datos de otro cliente.
--
-- Flujo tipico:
--   CALL public.prc_upsert_tenant(...);            -- alta de cliente (admin)
--   CALL device.prc_register_device(...);          -- alta de dispositivo
--   CALL tracking.prc_upsert_trip(...);            -- inicio de viaje
--   CALL device.prc_upsert_obd_session(...);       -- al conectar el adaptador
--   CALL tracking.prc_ingest_telemetry(...);       -- por cada lote
--   CALL tracking.prc_close_trip(...);             -- al terminar
--   SELECT * FROM traffic.fnc_live_by_bbox(...);   -- mapa de trafico
--
-- Cron del VPS (corre como dueno, ve todos los tenants):
--   */3 * * * *  psql -c "CALL traffic.prc_rollup_live(NULL, NULL);"
--   7   * * * *  psql -c "CALL traffic.prc_rollup_profile(now() - interval '1 hour', now(), NULL);"
--   30  3 * * 1  psql -c "CALL traffic.prc_recompute_free_flow(28, NULL);"
--   0   4 * * *  psql -c "CALL ops.prc_maintain_partitions(2, NULL);"
--   0   5 1 1 *  psql -c "CALL public.prc_generate_holiday(date_part('year',now())::int+10, date_part('year',now())::int+10, NULL);"
--
-- Verificacion de aislamiento (como rol vehitrack_app deben dar numeros distintos):
--   SET LOCAL app.tenant_id = '<tenant A>'; SELECT count(*) FROM tracking.position;
--   SET LOCAL app.tenant_id = '<tenant B>'; SELECT count(*) FROM tracking.position;
--
-- Inventario: SELECT * FROM public.db_routine ORDER BY schema_name, routine_name;
-- Alertas   : ops.pipeline_run sin 'success' reciente dentro de expected_interval_min.
-- =====================================================================================
