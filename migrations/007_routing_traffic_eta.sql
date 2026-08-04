-- =====================================================================================
-- VehiTrack · migrations/007_routing_traffic_eta.sql
-- ETA ajustado a trafico en vivo para POST /api/v1/routes (contrato duration_in_traffic).
--
-- Depende de 001_vehitrack.sql (traffic.link / traffic.live_state) y de
-- 004_routing_offline_ops.sql (routing.route_cache / routing.fnc_get_route).
-- Aplicar manualmente:  psql "$POSTGRES_DSN" -f migrations/007_routing_traffic_eta.sql
--
-- -------------------------------------------------------------------------------------
-- POR QUE EXISTE ESTE ARCHIVO
-- -------------------------------------------------------------------------------------
-- La app elegia "la mas rapida" por la duracion en FLUJO LIBRE que devuelve OSRM: no veia
-- atascos. Waze/Google rankean por ETA con trafico. Aqui se anade ese ETA reutilizando el
-- trafico colaborativo que el propio backend ya publica (traffic.live_state sobre
-- traffic.link, F7), SIN tocar tablas ni cache:
--
--   * traffic.fnc_route_eta(geom, free_flow_s): escala la duracion de flujo libre por la
--     congestion viva a lo largo de la ruta. Sin datos vivos -> devuelve el flujo libre.
--   * routing.fnc_get_route: anade la clave `duration_in_traffic_s` calculada al vuelo.
--
-- CLAVE DE DISENO — SE CALCULA EN CADA LECTURA, NO SE CACHEA. routing.route_cache guarda la
-- geometria/steps/duracion de flujo libre con TTL largo (routing.cache_ttl_minutes); el
-- trafico caduca en ~20 min (traffic.live_ttl_minutes). Meter el ETA con trafico en la cache
-- serviria trafico rancio en cada hit. Por eso fnc_route_eta se evalua dentro de
-- fnc_get_route (STABLE, lee traffic.live_state con expires_at > now()): fresco siempre.
--
-- Solo funciones (CREATE OR REPLACE). Sin ALTER TABLE, sin datos, idempotente y reversible.
-- traffic.link / traffic.live_state son GLOBALES (sin RLS): el rol de la app las lee directo.
--
-- Autor  : Lucho · Devitech
-- Version: 1.0.0
-- =====================================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- traffic.fnc_route_eta
-- Proposito : Duracion de la ruta ajustada a trafico en vivo, en segundos.
-- Parametros: p_geom (LineString 4326 de la ruta), p_free_flow_s (duracion OSRM flujo libre)
-- Retorna   : int segundos. >= p_free_flow_s (el trafico nunca acelera por debajo del libre).
-- Metodo    : muestrea 21 puntos equiespaciados a lo largo de la ruta; en cada uno busca el
--             link activo mas cercano (<= 60 m) con estado vivo no vencido y toma su factor de
--             retraso = flujo_libre_kmh / p50_kmh (topado a x3). Los puntos sin dato pesan x1
--             (flujo libre). El ETA = flujo_libre * promedio(factores).
-- Nota      : STABLE (lee traffic.* y now()); no IMMUTABLE. Sin datos vivos -> p_free_flow_s.
-- Autor     : Lucho · Devitech
-- Version   : 1.0.0
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION traffic.fnc_route_eta(
    p_geom geometry, p_free_flow_s int
) RETURNS int
LANGUAGE sql STABLE AS $$
    WITH samples AS (
        -- 21 muestras (fracciones 0..1). Vacio si la geometria no es LineString o no hay
        -- flujo libre positivo -> el CASE final devuelve p_free_flow_s tal cual.
        SELECT ST_LineInterpolatePoint(p_geom, g.i::float / 20) AS pt
        FROM generate_series(0, 20) AS g(i)
        WHERE p_free_flow_s > 0
          AND ST_GeometryType(p_geom) = 'ST_LineString'
    ),
    factors AS (
        SELECT COALESCE((
            SELECT LEAST(3.0, GREATEST(1.0,
                       l.free_flow_speed_kmh / NULLIF(ls.speed_p50_kmh, 0)))
            FROM traffic.link l
            JOIN traffic.live_state ls
              ON ls.traffic_link_id = l.id
             AND ls.expires_at > now()
            WHERE l.is_active
              AND l.free_flow_speed_kmh IS NOT NULL
              AND ST_DWithin(l.geom::geography, s.pt::geography, 60)
            ORDER BY l.geom <-> s.pt
            LIMIT 1
        ), 1.0) AS factor
        FROM samples s
    )
    SELECT CASE
             WHEN p_free_flow_s <= 0 THEN p_free_flow_s
             ELSE GREATEST(
                    p_free_flow_s,
                    round(p_free_flow_s * COALESCE((SELECT AVG(factor) FROM factors), 1.0))::int)
           END;
$$;

COMMENT ON FUNCTION traffic.fnc_route_eta(geometry, int) IS
    'ETA de ruta ajustado a traffic.live_state a lo largo de la geometria. Sin datos -> flujo libre.';

-- ─────────────────────────────────────────────────────────────────────────────────────
-- routing.fnc_get_route  (v1.1.0 — anade duration_in_traffic_s)
-- Proposito : Ruta vigente en cache. NULL = el ms debe llamar a OSRM.
-- Retorna   : jsonb {route_cache_id, geojson, distance_m, duration_s, duration_in_traffic_s,
--             steps, computed_at, expires_at}
-- Cambio    : + duration_in_traffic_s = traffic.fnc_route_eta(geom, duration_s), fresco por
--             lectura (no se persiste). El resto del shape no cambia.
-- Autor     : Lucho · Devitech
-- Version   : 1.1.0
-- Historial : 1.0.0  2026-08-01  Lucho  Creacion.
--             1.1.0  2026-08-03  Lucho  + duration_in_traffic_s (ETA con trafico vivo).
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION routing.fnc_get_route(
    p_waypoints jsonb, p_profile text DEFAULT 'car'
) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
             'route_cache_id',        r.id,
             'geojson',               ST_AsGeoJSON(r.geom)::jsonb,
             'distance_m',            r.distance_m,
             'duration_s',            r.duration_s,
             'duration_in_traffic_s', traffic.fnc_route_eta(r.geom, r.duration_s),
             'steps',                 r.steps,
             'computed_at',           r.computed_at,
             'expires_at',            r.expires_at)
    FROM routing.route_cache r
    WHERE r.waypoints_hash = routing.fnc_waypoints_hash(p_waypoints, p_profile)
      AND r.route_profile_id = p_profile
      AND r.expires_at > now();
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- Grants (mismo estilo per-funcion que 001/004/006). fnc_get_route conserva su grant al ser
-- CREATE OR REPLACE; fnc_route_eta es NUEVA y la app la ejecuta anidada desde fnc_get_route,
-- asi que necesita EXECUTE explicito. Lee traffic.link/live_state, sobre las que vehitrack_app
-- ya tiene SELECT (006). El rol vehitrack_app es prerrequisito (lo crea la infra; ver 006).
-- ─────────────────────────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION traffic.fnc_route_eta(geometry, int) TO vehitrack_app;

COMMIT;

-- =====================================================================================
-- VERIFICACION
--   -- 1) la funcion existe y es STABLE:
--   SELECT proname, provolatile FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'traffic' AND p.proname = 'fnc_route_eta';   -- provolatile = 's'
--
--   -- 2) sin trafico vivo, el ETA = flujo libre (factor 1.0):
--   SELECT traffic.fnc_route_eta(
--            ST_GeomFromText('LINESTRING(-74.80 10.98, -74.79 10.99)', 4326), 600);  -- => 600
--
--   -- 3) fnc_get_route ahora trae duration_in_traffic_s (sobre una ruta ya cacheada):
--   SELECT (routing.fnc_get_route(w, 'car')) ? 'duration_in_traffic_s'
--     FROM (SELECT waypoints_hash FROM routing.route_cache LIMIT 1) x
--    CROSS JOIN LATERAL (SELECT '[]'::jsonb AS w) y;   -- estructura; en runtime pasa waypoints reales
-- =====================================================================================
