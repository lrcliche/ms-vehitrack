-- =====================================================================================
-- VehiTrack · migrations/004_routing_offline_ops.sql
-- Cache de rutas OSRM, paquetes offline por region, log de API y mantenimiento diario.
--
-- Depende de 001_vehitrack.sql, 002_geocoding.sql, 003_device_data.sql.
-- Aplicar manualmente:  psql "$POSTGRES_DSN" -f migrations/004_routing_offline_ops.sql
--
-- -------------------------------------------------------------------------------------
-- QUE LLEVA TENANT Y QUE NO
-- -------------------------------------------------------------------------------------
-- CON tenant: routing.route_request, device.device_package, ops.api_request_log.
--             Son actividad de alguien.
-- SIN tenant: routing.route_cache, offline.*. Una ruta calculada sirve para todos, y un
--             paquete de Barranquilla es el mismo para todo el mundo. Particionar eso por
--             cliente seria pagarle a OSRM el mismo calculo N veces.
--
-- -------------------------------------------------------------------------------------
-- LA DECISION DE ROLLBACK QUE NO SE PROGRAMA
-- -------------------------------------------------------------------------------------
-- Las versiones de paquete son INMUTABLES: nunca se sobrescribe una publicada, se publica
-- la siguiente y el manifiesto apunta a ella. Con eso el rollback es cambiar un numero, y
-- no hay que escribir ningun mecanismo de rollback. VT072 hace cumplir la regla.
-- =====================================================================================

BEGIN;

SET LOCAL client_min_messages = WARNING;

DO $$
BEGIN
    IF to_regclass('device.favorite_place') IS NULL THEN
        RAISE EXCEPTION 'Aplica primero 003_device_data.sql';
    END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS routing;
CREATE SCHEMA IF NOT EXISTS offline;
COMMENT ON SCHEMA routing IS
    'Cache de rutas y map matching. Datos DERIVADOS: se puede vaciar entero sin perder nada del usuario.';
COMMENT ON SCHEMA offline IS
    'Regiones y paquetes descargables. Global, sin tenant: el mapa de Barranquilla es el mismo para todos.';

-- =====================================================================================
-- 1. CONFIGURACION, DICCIONARIOS Y JOBS
-- =====================================================================================

INSERT INTO public.app_setting (key, value, description) VALUES
  ('routing.cache_ttl_minutes',    '720',   'Vigencia de una ruta en cache antes de recalcular en OSRM.'),
  ('routing.hash_decimals',        '5',     'Decimales al redondear waypoints (~1 m). Mas = menos aciertos de cache.'),
  ('routing.max_waypoints',        '25',    'Waypoints maximos por peticion de ruta.'),
  ('ops.api_log_retention_days',   '30',    'Retencion del log de API. Crece mas rapido que las posiciones y vale menos.'),
  ('ops.api_log_days_ahead',       '3',     'Particiones diarias de log a pre-crear.'),
  ('maintenance.months_ahead',     '2',     'Meses de particiones mensuales a pre-crear.'),
  ('offline.min_free_bytes',       '1610612736', 'Espacio libre minimo que la app debe respetar (1,5 GB).')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.pipeline_job (id, name, expected_interval_min) VALUES
  ('daily_maintenance','Mantenimiento diario consolidado',1440)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.route_profile (
    id text PRIMARY KEY, name text NOT NULL, osrm_profile text NOT NULL, sort_order smallint NOT NULL);
COMMENT ON COLUMN public.route_profile.osrm_profile IS
    'Nombre del perfil compilado en OSRM. Hoy solo esta car: agregar moto exige otro build del grafo.';
INSERT INTO public.route_profile (id, name, osrm_profile, sort_order) VALUES
  ('car','Automovil','car',1)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.artifact_kind (
    id text PRIMARY KEY, name text NOT NULL, is_required boolean NOT NULL, sort_order smallint NOT NULL);
INSERT INTO public.artifact_kind (id, name, is_required, sort_order) VALUES
  ('tiles','Tiles vectoriales (pmtiles/mbtiles)',true,1),
  ('addresses','Indice de direcciones (sqlite con FTS5 y R*Tree)',true,2),
  ('poi','POI publicos de la region',false,3),
  ('dictionary','Diccionario de normalizacion embebido',false,4)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.package_status (
    id text PRIMARY KEY, name text NOT NULL, is_downloadable boolean NOT NULL);
INSERT INTO public.package_status (id, name, is_downloadable) VALUES
  ('building','En construccion',false),
  ('published','Publicado',true),
  ('deprecated','Reemplazado por una version mas nueva',true)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.package_operation (
    id text PRIMARY KEY, name text NOT NULL);
INSERT INTO public.package_operation (id, name) VALUES
  ('install','Instalado o actualizado'),('touch','Usado'),('remove','Eliminado del dispositivo')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================================
-- 2. CACHE DE RUTAS
-- =====================================================================================

CREATE TABLE IF NOT EXISTS routing.route_cache (
    id               bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    waypoints_hash   text   NOT NULL,
    route_profile_id text   NOT NULL REFERENCES public.route_profile(id),
    geom             geometry(LineString, 4326) NOT NULL,
    distance_m       numeric(12,2) NOT NULL,
    duration_s       int    NOT NULL,
    steps            jsonb,
    alternatives     jsonb,
    hit_count        int    NOT NULL DEFAULT 0,
    computed_at      timestamptz NOT NULL DEFAULT now(),
    expires_at       timestamptz NOT NULL,
    UNIQUE (waypoints_hash, route_profile_id)
);
COMMENT ON TABLE routing.route_cache IS
    'Ruta calculada por OSRM. GLOBAL: dos personas que salen de la misma cuadra al mismo
     destino comparten ruta en vez de gastar dos calculos.';
COMMENT ON COLUMN routing.route_cache.steps IS
    'Maniobras listas para persistirse tal cual en el dispositivo. Ese objeto guardado ES la
     navegacion cuando se cae la red a mitad de camino.';
CREATE INDEX IF NOT EXISTS ix_route_cache_expires ON routing.route_cache (expires_at);

CREATE TABLE IF NOT EXISTS routing.route_request (
    id             bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    tenant_id      uuid   NOT NULL REFERENCES public.tenant(id),
    device_id      uuid   NOT NULL REFERENCES device.device(id),
    route_cache_id bigint REFERENCES routing.route_cache(id) ON DELETE SET NULL,
    was_cache_hit  boolean NOT NULL,
    requested_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE routing.route_request IS
    'Existe para UNA metrica: el hit rate real del cache. Es el numero que justifica (o no)
     seguir manteniendo OSRM en el VPS.';
CREATE INDEX IF NOT EXISTS ix_route_request_tenant
    ON routing.route_request (tenant_id, requested_at DESC);

ALTER TABLE routing.route_request ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_tenant_isolation ON routing.route_request;
CREATE POLICY pol_tenant_isolation ON routing.route_request
    USING (tenant_id = public.fnc_current_tenant())
    WITH CHECK (tenant_id = public.fnc_current_tenant());

-- ─────────────────────────────────────────────────────────────────────────────────────
-- routing.fnc_waypoints_hash
-- Proposito : Clave de cache estable para un conjunto de waypoints. Redondea segun
--             routing.hash_decimals para que salidas casi iguales compartan ruta.
-- Parametros: p_waypoints jsonb [{lat,lon}], p_profile
-- Retorna   : text sha256 hex
-- Errores   : ninguno
-- Nota      : STABLE y no IMMUTABLE porque lee app_setting. No se indexa su resultado: se
--             materializa en route_cache.waypoints_hash.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION routing.fnc_waypoints_hash(
    p_waypoints jsonb, p_profile text DEFAULT 'car'
) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT encode(digest(p_profile || '|' || string_agg(
             round(w.lat::numeric, public.fnc_setting_num('routing.hash_decimals')::int)::text
             || ',' ||
             round(w.lon::numeric, public.fnc_setting_num('routing.hash_decimals')::int)::text,
             ';' ORDER BY w.ord), 'sha256'), 'hex')
    -- WITH ORDINALITY no admite lista de columnas directa sobre la funcion; hay que
    -- envolver en ROWS FROM(...) (la ordinalidad queda como ultima columna: ord).
    FROM ROWS FROM (jsonb_to_recordset(p_waypoints)
                    AS (lat double precision, lon double precision))
         WITH ORDINALITY AS w(lat, lon, ord);
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- routing.fnc_get_route
-- Proposito : Ruta vigente en cache. NULL = el ms debe llamar a OSRM.
-- Parametros: p_waypoints, p_profile
-- Retorna   : jsonb {route_cache_id, geojson, distance_m, duration_s, steps, expires_at}
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION routing.fnc_get_route(
    p_waypoints jsonb, p_profile text DEFAULT 'car'
) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
             'route_cache_id', r.id,
             'geojson',    ST_AsGeoJSON(r.geom)::jsonb,
             'distance_m', r.distance_m,
             'duration_s', r.duration_s,
             'steps',      r.steps,
             'computed_at', r.computed_at,
             'expires_at',  r.expires_at)
    FROM routing.route_cache r
    WHERE r.waypoints_hash = routing.fnc_waypoints_hash(p_waypoints, p_profile)
      AND r.route_profile_id = p_profile
      AND r.expires_at > now();
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- routing.prc_store_route
-- Proposito : Guarda la ruta que devolvio OSRM y registra la peticion del dispositivo.
-- Parametros: p_device_id, p_waypoints, p_geojson, p_distance_m, p_duration_s, p_profile,
--             p_steps, p_alternatives, p_result INOUT
-- Errores   : VT041 device no visible · VT060 geometria de ruta invalida
--             VT061 perfil invalido · VT062 demasiados waypoints
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE routing.prc_store_route(
    p_device_id    uuid,
    p_waypoints    jsonb,
    p_geojson      jsonb,
    p_distance_m   numeric,
    p_duration_s   int,
    p_profile      text  DEFAULT 'car',
    p_steps        jsonb DEFAULT NULL,
    p_alternatives jsonb DEFAULT NULL,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_tenant uuid; v_geom geometry; v_hash text; v_id bigint;
    v_ttl int := public.fnc_setting_num('routing.cache_ttl_minutes')::int;
    v_max int := public.fnc_setting_num('routing.max_waypoints')::int;
BEGIN
    SELECT tenant_id INTO v_tenant FROM device.device WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device % no visible en el tenant activo', p_device_id USING ERRCODE = 'VT041';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.route_profile WHERE id = p_profile) THEN
        RAISE EXCEPTION 'route_profile % invalido', p_profile USING ERRCODE = 'VT061';
    END IF;
    IF jsonb_array_length(p_waypoints) > v_max THEN
        RAISE EXCEPTION 'ruta con % waypoints excede el maximo de %',
            jsonb_array_length(p_waypoints), v_max USING ERRCODE = 'VT062';
    END IF;

    v_geom := ST_SetSRID(ST_GeomFromGeoJSON(p_geojson::text), 4326);
    IF v_geom IS NULL OR ST_GeometryType(v_geom) <> 'ST_LineString' THEN
        RAISE EXCEPTION 'geometria de ruta invalida' USING ERRCODE = 'VT060';
    END IF;

    v_hash := routing.fnc_waypoints_hash(p_waypoints, p_profile);

    INSERT INTO routing.route_cache (waypoints_hash, route_profile_id, geom, distance_m,
                                     duration_s, steps, alternatives, computed_at, expires_at)
    VALUES (v_hash, p_profile, v_geom, p_distance_m, p_duration_s, p_steps, p_alternatives,
            now(), now() + (v_ttl || ' minute')::interval)
    ON CONFLICT (waypoints_hash, route_profile_id) DO UPDATE SET
        geom = EXCLUDED.geom, distance_m = EXCLUDED.distance_m,
        duration_s = EXCLUDED.duration_s, steps = EXCLUDED.steps,
        alternatives = EXCLUDED.alternatives, computed_at = now(),
        expires_at = EXCLUDED.expires_at
    RETURNING id INTO v_id;

    INSERT INTO routing.route_request (tenant_id, device_id, route_cache_id, was_cache_hit)
    VALUES (v_tenant, p_device_id, v_id, false);

    p_result := jsonb_build_object('route_cache_id', v_id, 'waypoints_hash', v_hash);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- routing.prc_record_route_hit
-- Proposito : Registra que una ruta se sirvio desde cache (alimenta el hit rate).
-- Parametros: p_device_id, p_route_cache_id
-- Errores   : VT041 device no visible
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE routing.prc_record_route_hit(
    p_device_id uuid, p_route_cache_id bigint
) LANGUAGE plpgsql AS $$
DECLARE v_tenant uuid;
BEGIN
    SELECT tenant_id INTO v_tenant FROM device.device WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device % no visible en el tenant activo', p_device_id USING ERRCODE = 'VT041';
    END IF;

    UPDATE routing.route_cache SET hit_count = hit_count + 1 WHERE id = p_route_cache_id;
    INSERT INTO routing.route_request (tenant_id, device_id, route_cache_id, was_cache_hit)
    VALUES (v_tenant, p_device_id, p_route_cache_id, true);
END $$;

-- =====================================================================================
-- 3. PAQUETES OFFLINE
-- =====================================================================================

CREATE TABLE IF NOT EXISTS offline.region (
    id              text    PRIMARY KEY,
    name            text    NOT NULL,
    bbox            geometry(Polygon, 4326) NOT NULL,
    current_version int,
    is_published    boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gist_region_bbox ON offline.region USING gist (bbox);

CREATE TABLE IF NOT EXISTS offline.region_municipality (
    region_id       text NOT NULL REFERENCES offline.region(id) ON DELETE CASCADE,
    municipality_id text NOT NULL REFERENCES public.municipality(id),
    PRIMARY KEY (region_id, municipality_id)
);
COMMENT ON TABLE offline.region_municipality IS
    'Una region puede cubrir varios municipios (area metropolitana). Es lo que permite decir
     "esta ruta atraviesa las regiones X e Y" y precargarlas.';

CREATE TABLE IF NOT EXISTS offline.package (
    id                bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    region_id         text NOT NULL REFERENCES offline.region(id) ON DELETE CASCADE,
    version           int  NOT NULL,
    package_status_id text NOT NULL REFERENCES public.package_status(id) DEFAULT 'building',
    osm_extract_date  date,
    published_at      timestamptz,
    UNIQUE (region_id, version)
);

CREATE TABLE IF NOT EXISTS offline.package_artifact (
    id               bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    package_id       bigint NOT NULL REFERENCES offline.package(id) ON DELETE CASCADE,
    artifact_kind_id text   NOT NULL REFERENCES public.artifact_kind(id),
    url              text   NOT NULL,
    size_bytes       bigint NOT NULL,
    sha256           text   NOT NULL,
    UNIQUE (package_id, artifact_kind_id)
);
COMMENT ON COLUMN offline.package_artifact.sha256 IS
    'La app lo verifica EN STREAMING durante la descarga. En una tablet de 4 GB no se puede
     cargar el archivo entero en RAM para hashearlo al final.';

CREATE TABLE IF NOT EXISTS offline.package_delta (
    id               bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    from_package_id  bigint NOT NULL REFERENCES offline.package(id) ON DELETE CASCADE,
    to_package_id    bigint NOT NULL REFERENCES offline.package(id) ON DELETE CASCADE,
    artifact_kind_id text   NOT NULL REFERENCES public.artifact_kind(id),
    url              text   NOT NULL,
    size_bytes       bigint NOT NULL,
    sha256           text   NOT NULL,
    UNIQUE (from_package_id, to_package_id, artifact_kind_id)
);
COMMENT ON TABLE offline.package_delta IS
    'Deltas SOLO de artefactos tabulares (addresses, poi). Los tiles no tienen delta: diffear
     formatos comprimidos exige un motor de patching en servidor Y en cliente, con su propio
     riesgo de corrupcion, para ahorrar poco. Se publican tiles con menos frecuencia.';

CREATE TABLE IF NOT EXISTS device.device_package (
    id                bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    tenant_id         uuid   NOT NULL REFERENCES public.tenant(id),
    device_id         uuid   NOT NULL REFERENCES device.device(id),
    region_id         text   NOT NULL REFERENCES offline.region(id),
    installed_version int    NOT NULL,
    size_bytes        bigint,
    installed_at      timestamptz NOT NULL DEFAULT now(),
    last_used_at      timestamptz,
    use_count         int    NOT NULL DEFAULT 0,
    is_protected      boolean NOT NULL DEFAULT false,
    UNIQUE (device_id, region_id)
);
COMMENT ON TABLE device.device_package IS
    'Que version tiene instalada cada dispositivo. Sin esto no sabes a quien ofrecerle
     actualizacion ni que delta calcularle.';
COMMENT ON COLUMN device.device_package.is_protected IS
    'La region de casa y las que tienen clientes NUNCA entran en la limpieza LRU de la app.';

ALTER TABLE device.device_package ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_tenant_isolation ON device.device_package;
CREATE POLICY pol_tenant_isolation ON device.device_package
    USING (tenant_id = public.fnc_current_tenant())
    WITH CHECK (tenant_id = public.fnc_current_tenant());

-- ─────────────────────────────────────────────────────────────────────────────────────
-- offline.fnc_region_manifest
-- Proposito : Manifiesto de la version vigente de una region. Responde
--             GET /v1/regions/{id}/manifest. Es el corazon del motor offline.
-- Parametros: p_region_id, p_installed_version
-- Retorna   : jsonb {region_id, version, artifacts[], delta[], update_available, bbox}
-- Errores   : VT070 region sin paquete publicado
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION offline.fnc_region_manifest(
    p_region_id text, p_installed_version int DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE v_pkg record; v_from bigint;
BEGIN
    SELECT p.* INTO v_pkg
      FROM offline.package p JOIN offline.region r ON r.id = p.region_id
     WHERE p.region_id = p_region_id AND p.version = r.current_version
       AND p.package_status_id = 'published' AND r.is_published;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'region % sin paquete publicado', p_region_id USING ERRCODE = 'VT070';
    END IF;

    SELECT id INTO v_from FROM offline.package
     WHERE region_id = p_region_id AND version = p_installed_version;

    RETURN jsonb_build_object(
        'region_id',        v_pkg.region_id,
        'version',          v_pkg.version,
        'osm_extract_date', v_pkg.osm_extract_date,
        'published_at',     v_pkg.published_at,
        'update_available', p_installed_version IS NULL OR p_installed_version < v_pkg.version,
        'bbox', (SELECT ST_AsGeoJSON(bbox)::jsonb FROM offline.region WHERE id = p_region_id),
        'artifacts', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                     'kind', a.artifact_kind_id, 'url', a.url,
                     'bytes', a.size_bytes, 'sha256', a.sha256) ORDER BY a.artifact_kind_id)
            FROM offline.package_artifact a WHERE a.package_id = v_pkg.id), '[]'::jsonb),
        'deltas', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                     'kind', d.artifact_kind_id, 'url', d.url,
                     'bytes', d.size_bytes, 'sha256', d.sha256))
            FROM offline.package_delta d
            WHERE d.to_package_id = v_pkg.id AND d.from_package_id = v_from), '[]'::jsonb));
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- offline.fnc_regions_for_route
-- Proposito : Regiones que atraviesa una ruta. Es la Regla 2 de la descarga predictiva:
--             mientras el usuario ve la ruta, la app ya sabe que bajar.
-- Parametros: p_route_geojson
-- Retorna   : SETOF (region_id, name, current_version, size_bytes)
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION offline.fnc_regions_for_route(p_route_geojson jsonb)
RETURNS TABLE (region_id text, name text, current_version int, size_bytes bigint)
LANGUAGE sql STABLE AS $$
    WITH line AS (SELECT ST_SetSRID(ST_GeomFromGeoJSON(p_route_geojson::text), 4326) AS geom)
    SELECT r.id, r.name, r.current_version,
           COALESCE((SELECT sum(a.size_bytes) FROM offline.package_artifact a
                     JOIN offline.package p ON p.id = a.package_id
                     WHERE p.region_id = r.id AND p.version = r.current_version), 0)
    FROM offline.region r, line l
    WHERE r.is_published AND ST_Intersects(r.bbox, l.geom)
    ORDER BY ST_Distance(ST_StartPoint(l.geom), ST_Centroid(r.bbox));
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- offline.prc_publish_package
-- Proposito : Publica una version de region con sus artefactos y la marca vigente.
-- Parametros: p_region_id, p_version, p_artifacts jsonb [{kind,url,size_bytes,sha256}],
--             p_osm_extract_date, p_result INOUT
-- Errores   : VT071 region inexistente · VT072 version ya publicada (son inmutables)
--             VT073 faltan artefactos obligatorios
-- Nota      : la inmutabilidad no es purismo: es lo que hace que el rollback sea cambiar
--             current_version y nada mas.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE offline.prc_publish_package(
    p_region_id        text,
    p_version          int,
    p_artifacts        jsonb,
    p_osm_extract_date date DEFAULT NULL,
    INOUT p_result     jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_pkg bigint; v_n int; v_missing text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM offline.region WHERE id = p_region_id) THEN
        RAISE EXCEPTION 'region % inexistente', p_region_id USING ERRCODE = 'VT071';
    END IF;
    IF EXISTS (SELECT 1 FROM offline.package
                WHERE region_id = p_region_id AND version = p_version
                  AND package_status_id = 'published') THEN
        RAISE EXCEPTION 'version % de % ya publicada: las versiones son inmutables, publica la siguiente',
            p_version, p_region_id USING ERRCODE = 'VT072';
    END IF;

    SELECT string_agg(k.id, ', ') INTO v_missing
      FROM public.artifact_kind k
     WHERE k.is_required
       AND NOT EXISTS (SELECT 1 FROM jsonb_to_recordset(COALESCE(p_artifacts,'[]'::jsonb))
                            AS a(kind text) WHERE a.kind = k.id);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'faltan artefactos obligatorios: %', v_missing USING ERRCODE = 'VT073';
    END IF;

    INSERT INTO offline.package (region_id, version, package_status_id, osm_extract_date, published_at)
    VALUES (p_region_id, p_version, 'published', p_osm_extract_date, now())
    ON CONFLICT (region_id, version) DO UPDATE SET
        package_status_id = 'published', published_at = now(),
        osm_extract_date = EXCLUDED.osm_extract_date
    RETURNING id INTO v_pkg;

    INSERT INTO offline.package_artifact (package_id, artifact_kind_id, url, size_bytes, sha256)
    SELECT v_pkg, a.kind, a.url, a.size_bytes, a.sha256
    FROM jsonb_to_recordset(p_artifacts) AS a(kind text, url text, size_bytes bigint, sha256 text)
    ON CONFLICT (package_id, artifact_kind_id) DO UPDATE SET
        url = EXCLUDED.url, size_bytes = EXCLUDED.size_bytes, sha256 = EXCLUDED.sha256;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE offline.package SET package_status_id = 'deprecated'
     WHERE region_id = p_region_id AND version < p_version AND package_status_id = 'published';
    UPDATE offline.region SET current_version = p_version, is_published = true
     WHERE id = p_region_id;

    p_result := jsonb_build_object('package_id', v_pkg, 'version', p_version, 'artifact_count', v_n);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.prc_track_device_package
-- Proposito : Registra que un dispositivo instalo, uso o elimino una region.
-- Parametros: p_device_id, p_region_id, p_operation, p_version, p_size_bytes,
--             p_is_protected, p_result INOUT
-- Errores   : VT041 device no visible · VT074 operacion invalida
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE device.prc_track_device_package(
    p_device_id    uuid,
    p_region_id    text,
    p_operation    text DEFAULT 'install',
    p_version      int  DEFAULT NULL,
    p_size_bytes   bigint DEFAULT NULL,
    p_is_protected boolean DEFAULT NULL,
    INOUT p_result jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE v_tenant uuid;
BEGIN
    SELECT tenant_id INTO v_tenant FROM device.device WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'device % no visible en el tenant activo', p_device_id USING ERRCODE = 'VT041';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.package_operation WHERE id = p_operation) THEN
        RAISE EXCEPTION 'package_operation % invalida', p_operation USING ERRCODE = 'VT074';
    END IF;

    IF p_operation = 'remove' THEN
        DELETE FROM device.device_package
         WHERE device_id = p_device_id AND region_id = p_region_id;
        p_result := jsonb_build_object('region_id', p_region_id, 'operation', p_operation);
        RETURN;
    END IF;

    INSERT INTO device.device_package (tenant_id, device_id, region_id, installed_version,
                                       size_bytes, last_used_at, use_count, is_protected)
    VALUES (v_tenant, p_device_id, p_region_id, COALESCE(p_version, 0), p_size_bytes,
            now(), 1, COALESCE(p_is_protected, false))
    ON CONFLICT (device_id, region_id) DO UPDATE SET
        installed_version = COALESCE(EXCLUDED.installed_version, device_package.installed_version),
        size_bytes        = COALESCE(EXCLUDED.size_bytes, device_package.size_bytes),
        is_protected      = COALESCE(p_is_protected, device_package.is_protected),
        last_used_at      = now(),
        use_count         = device_package.use_count + 1;

    p_result := jsonb_build_object('region_id', p_region_id, 'operation', p_operation);
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- device.fnc_list_device_package
-- Proposito : Regiones instaladas en un dispositivo, con aviso de actualizacion. Alimenta
--             la pantalla "Offline Maps".
-- Parametros: p_device_id
-- Retorna   : SETOF (region_id, name, installed_version, current_version,
--                    update_available, size_bytes, last_used_at, is_protected)
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION device.fnc_list_device_package(p_device_id uuid)
RETURNS TABLE (region_id text, name text, installed_version int, current_version int,
               update_available boolean, size_bytes bigint, last_used_at timestamptz,
               is_protected boolean)
LANGUAGE sql STABLE AS $$
    SELECT dp.region_id, r.name, dp.installed_version, r.current_version,
           r.current_version IS NOT NULL AND dp.installed_version < r.current_version,
           dp.size_bytes, dp.last_used_at, dp.is_protected
    FROM device.device_package dp
    JOIN offline.region r ON r.id = dp.region_id
    WHERE dp.device_id = p_device_id
    ORDER BY dp.last_used_at DESC NULLS LAST;
$$;

-- =====================================================================================
-- 4. LOG DE API — trazabilidad por device_id
-- =====================================================================================

CREATE SEQUENCE IF NOT EXISTS ops.api_request_log_id_seq AS bigint;

CREATE TABLE IF NOT EXISTS ops.api_request_log (
    id          bigint      NOT NULL DEFAULT nextval('ops.api_request_log_id_seq'),
    tenant_id   uuid,
    device_id   uuid,
    endpoint    text        NOT NULL,
    http_method text        NOT NULL,
    status_code int         NOT NULL,
    duration_ms int,
    app_version text,
    trace_id    text,
    meta        jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (occurred_at, id)
) PARTITION BY RANGE (occurred_at);
COMMENT ON TABLE ops.api_request_log IS
    'device_id en cada fila: con un solo id reconstruyes toda la actividad de un dispositivo
     entre esta tabla y el log estructurado del ms (trace_id). Retencion corta a proposito.';
COMMENT ON COLUMN ops.api_request_log.device_id IS
    'NULL solo en /devices/register, que ocurre antes de que el device exista. Sin FK: el log
     debe sobrevivir al borrado de un dispositivo.';

-- ─────────────────────────────────────────────────────────────────────────────────────
-- ops.fnc_ensure_request_log_partition
-- Proposito : Crea (si falta) la particion diaria del log de API con sus indices.
-- Parametros: p_day
-- Retorna   : text nombre de la particion
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ops.fnc_ensure_request_log_partition(p_day date)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_name text := 'api_request_log_' || to_char(p_day, 'YYYYMMDD');
BEGIN
    IF to_regclass('ops.' || v_name) IS NOT NULL THEN RETURN v_name; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('ops.' || v_name));
    IF to_regclass('ops.' || v_name) IS NOT NULL THEN RETURN v_name; END IF;

    EXECUTE format(
        'CREATE TABLE ops.%I PARTITION OF ops.api_request_log FOR VALUES FROM (%L) TO (%L)',
        v_name, p_day, p_day + 1);
    EXECUTE format('CREATE INDEX %I ON ops.%I (device_id, occurred_at)', 'ix_'||v_name||'_device', v_name);
    EXECUTE format('CREATE INDEX %I ON ops.%I (endpoint, status_code)', 'ix_'||v_name||'_endpoint', v_name);
    EXECUTE format('CREATE INDEX %I ON ops.%I (trace_id)', 'ix_'||v_name||'_trace', v_name);
    RETURN v_name;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- ops.prc_log_api_request
-- Proposito : Escribe una fila de log. La llama el middleware del ms al cerrar la peticion,
--             con el mismo device_id que ya lleva en el context.
-- Parametros: p_device_id, p_endpoint, p_method, p_status_code, p_duration_ms,
--             p_app_version, p_trace_id, p_meta
-- Errores   : ninguno — el log NUNCA debe tumbar una peticion, por eso captura y avisa
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE ops.prc_log_api_request(
    p_device_id   uuid,
    p_endpoint    text,
    p_method      text,
    p_status_code int,
    p_duration_ms int  DEFAULT NULL,
    p_app_version text DEFAULT NULL,
    p_trace_id    text DEFAULT NULL,
    p_meta        jsonb DEFAULT NULL
) LANGUAGE plpgsql AS $$
BEGIN
    PERFORM ops.fnc_ensure_request_log_partition(current_date);
    INSERT INTO ops.api_request_log (tenant_id, device_id, endpoint, http_method, status_code,
                                     duration_ms, app_version, trace_id, meta)
    VALUES (public.fnc_current_tenant(), p_device_id, p_endpoint, p_method, p_status_code,
            p_duration_ms, p_app_version, p_trace_id, p_meta);
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'no se pudo escribir api_request_log: %', SQLERRM;
END $$;

-- =====================================================================================
-- 5. MANTENIMIENTO DIARIO — un solo punto de entrada del cron
-- =====================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────
-- ops.prc_daily_maintenance
-- Proposito : Orquesta el mantenimiento: particiones (delegando en ops.prc_maintain_partitions
--             del 001), particiones y retencion del log de API, purga de cache de geocoding
--             y de rutas vencidas. Registra en ops.pipeline_run.
-- Parametros: p_result INOUT {partitions, api_log, geocode, routes_deleted}
-- Errores   : ninguno propio; propaga el fallo tras marcar la corrida como failed
-- Nota      : corre como DUENO de la BD, no como vehitrack_app: necesita ver todos los
--             tenants y crear objetos. NO reimplementa lo que ya hace el 001.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE ops.prc_daily_maintenance(INOUT p_result jsonb DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_run    bigint;
    v_ahead  int := public.fnc_setting_num('maintenance.months_ahead')::int;
    v_days   int := public.fnc_setting_num('ops.api_log_days_ahead')::int;
    v_ret    int := public.fnc_setting_num('ops.api_log_retention_days')::int;
    v_part   jsonb; v_geo jsonb;
    v_logs   int := 0; v_dropped int := 0; v_routes int := 0;
    i int; r record; v_cut date;
BEGIN
    INSERT INTO ops.pipeline_run (pipeline_job_id, run_status_id)
    VALUES ('daily_maintenance','running') RETURNING id INTO v_run;

    -- particiones de position y observation: ya resuelto en 001, no se duplica
    CALL ops.prc_maintain_partitions(v_ahead, v_part);

    FOR i IN 0..v_days LOOP
        PERFORM ops.fnc_ensure_request_log_partition(current_date + i);
        v_logs := v_logs + 1;
    END LOOP;

    v_cut := current_date - v_ret;
    FOR r IN
        SELECT c.relname AS rel FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'ops' AND c.relname ~ '^api_request_log_[0-9]{8}$'
          AND to_date(right(c.relname, 8), 'YYYYMMDD') < v_cut
    LOOP
        EXECUTE format('DROP TABLE ops.%I', r.rel);
        v_dropped := v_dropped + 1;
    END LOOP;

    CALL geo.prc_purge_geocode_query(v_geo);

    DELETE FROM routing.route_cache WHERE expires_at < now() - interval '1 day';
    GET DIAGNOSTICS v_routes = ROW_COUNT;

    UPDATE ops.pipeline_run
       SET run_status_id = 'success', finished_at = now(),
           row_count = v_dropped + v_routes
     WHERE id = v_run;

    p_result := jsonb_build_object(
        'partitions', v_part,
        'api_log', jsonb_build_object('ensured', v_logs, 'dropped', v_dropped),
        'geocode', v_geo, 'routes_deleted', v_routes);
EXCEPTION WHEN OTHERS THEN
    UPDATE ops.pipeline_run
       SET run_status_id = 'failed', finished_at = now(), log_excerpt = SQLERRM
     WHERE id = v_run;
    RAISE;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- ops.fnc_route_cache_stats
-- Proposito : Hit rate del cache de rutas por ventana. Es el numero que justifica (o no)
--             mantener OSRM corriendo.
-- Parametros: p_from, p_to
-- Retorna   : jsonb {total, hits, misses, hit_rate}
-- Errores   : ninguno
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ops.fnc_route_cache_stats(p_from timestamptz, p_to timestamptz)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
    SELECT jsonb_build_object(
        'total',  count(*),
        'hits',   count(*) FILTER (WHERE was_cache_hit),
        'misses', count(*) FILTER (WHERE NOT was_cache_hit),
        'hit_rate', CASE WHEN count(*) = 0 THEN 0
                    ELSE round(count(*) FILTER (WHERE was_cache_hit)::numeric / count(*), 3) END)
    FROM routing.route_request
    WHERE requested_at >= p_from AND requested_at < p_to;
$$;

-- =====================================================================================
-- 6. REGISTRO Y PERMISOS
-- =====================================================================================

INSERT INTO public.db_routine (schema_name, routine_name, routine_type, purpose, author, version, migration) VALUES
 ('routing','fnc_waypoints_hash','function','Clave de cache de ruta','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql'),
 ('routing','fnc_get_route','function','Ruta vigente en cache','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql'),
 ('routing','prc_store_route','procedure','Persiste ruta calculada por OSRM','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql'),
 ('routing','prc_record_route_hit','procedure','Registra acierto de cache de ruta','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql'),
 ('offline','fnc_region_manifest','function','Manifiesto de la region vigente','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql'),
 ('offline','fnc_regions_for_route','function','Regiones que atraviesa una ruta (descarga predictiva)','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql'),
 ('offline','prc_publish_package','procedure','Publicacion inmutable de paquete de region','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql'),
 ('device','prc_track_device_package','procedure','Instalacion, uso o borrado de region por device','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql'),
 ('device','fnc_list_device_package','function','Regiones instaladas con aviso de actualizacion','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql'),
 ('ops','fnc_ensure_request_log_partition','function','Particion diaria del log de API','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql'),
 ('ops','prc_log_api_request','procedure','Log de peticion con device_id','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql'),
 ('ops','prc_daily_maintenance','procedure','Mantenimiento diario consolidado (cron)','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql'),
 ('ops','fnc_route_cache_stats','function','Hit rate del cache de rutas','Lucho · Devitech','1.0.0','004_routing_offline_ops.sql')
ON CONFLICT (schema_name, routine_name) DO UPDATE SET
    purpose = EXCLUDED.purpose, author = EXCLUDED.author,
    version = EXCLUDED.version, migration = EXCLUDED.migration, updated_at = now();

GRANT USAGE ON SCHEMA routing, offline TO vehitrack_app;

GRANT SELECT ON
    public.route_profile, public.artifact_kind, public.package_status, public.package_operation,
    routing.route_cache, offline.region, offline.region_municipality,
    offline.package, offline.package_artifact, offline.package_delta,
    device.device_package
TO vehitrack_app;

GRANT EXECUTE ON FUNCTION
    routing.fnc_waypoints_hash(jsonb, text),
    routing.fnc_get_route(jsonb, text),
    offline.fnc_region_manifest(text, int),
    offline.fnc_regions_for_route(jsonb),
    device.fnc_list_device_package(uuid)
TO vehitrack_app;

GRANT EXECUTE ON PROCEDURE
    routing.prc_store_route(uuid, jsonb, jsonb, numeric, int, text, jsonb, jsonb, jsonb),
    routing.prc_record_route_hit(uuid, bigint),
    device.prc_track_device_package(uuid, text, text, int, bigint, boolean, jsonb),
    ops.prc_log_api_request(uuid, text, text, int, int, text, text, jsonb)
TO vehitrack_app;

-- administracion: no van al rol de la app
REVOKE EXECUTE ON PROCEDURE ops.prc_daily_maintenance(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE offline.prc_publish_package(text, int, jsonb, date, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION ops.fnc_route_cache_stats(timestamptz, timestamptz) FROM PUBLIC;

COMMIT;

-- =====================================================================================
-- 7. CRON — reemplaza la linea de particiones del 001
--
--   0 4 * * *  psql "$POSTGRES_DSN" -c "CALL ops.prc_daily_maintenance(NULL);"
--
-- Quita del crontab la llamada suelta a ops.prc_maintain_partitions: ahora la invoca el
-- mantenimiento diario. Dejar las dos no rompe nada (son idempotentes), pero duplica el
-- registro en ops.pipeline_run y ensucia la alerta.
--
-- ALERTA: ops.pipeline_run sin 'success' de daily_maintenance en 48 horas. Si el timer se
-- cae, en unos dias se acaban las particiones futuras y la INGESTA EMPIEZA A FALLAR.
--
-- VERIFICACION:
--   CALL ops.prc_daily_maintenance(NULL);
--   SELECT ops.fnc_route_cache_stats(now() - interval '7 day', now());
--   SELECT * FROM geo.fnc_geocode_stats(now() - interval '7 day', now());
--   SELECT * FROM public.db_routine ORDER BY schema_name, routine_name;
-- =====================================================================================
