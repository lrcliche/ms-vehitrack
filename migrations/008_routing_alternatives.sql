-- =====================================================================================
-- VehiTrack · migrations/008_routing_alternatives.sql
-- Alternativas reales en POST /api/v1/routes: fnc_get_route devuelve un array `routes`
-- (principal + alternativas), cada una con su ETA de trafico.
--
-- Depende de 004 (routing.route_cache.alternatives ya existe) y 007 (traffic.fnc_route_eta).
-- Aplicar manualmente:  psql "$POSTGRES_DSN" -f migrations/008_routing_alternatives.sql
--
-- -------------------------------------------------------------------------------------
-- POR QUE EXISTE ESTE ARCHIVO
-- -------------------------------------------------------------------------------------
-- La app pide alternatives=true y rankea "la mas rapida ahora" entre varias rutas, pero el
-- endpoint devolvia una sola. El motor OSRM del ms ya calcula alternativas (client.RouteAll,
-- alternatives=3) y prc_store_route ya las persiste en route_cache.alternatives (jsonb). Solo
-- faltaba que la LECTURA las exponga. Aqui fnc_get_route pasa de devolver una ruta plana a un
-- objeto con `routes[]`: [principal, ...alternativas]. Cada ruta trae su duration_in_traffic_s
-- (traffic.fnc_route_eta sobre su propia geometria), fresco por lectura como en 007.
--
-- route_cache.alternatives guarda un jsonb array de {geojson, distance_m, duration_s, steps}
-- (lo que serializa infrastructure/osrm/engine.go). route_cache_id sigue en la raiz para que
-- application/routing.Service lo lea en el hit de cache.
--
-- Solo funcion (CREATE OR REPLACE), sin ALTER TABLE, idempotente y reversible.
--
-- Autor  : Lucho · Devitech
-- Version: 1.0.0
-- =====================================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- routing.fnc_get_route  (v2.0.0 — devuelve routes[] con alternativas)
-- Retorna : jsonb {route_cache_id, computed_at, expires_at,
--                  routes:[{geojson, distance_m, duration_s, duration_in_traffic_s, steps}]}
--           routes[0] = principal; el resto = alternativas de route_cache.alternatives.
-- Historial: 1.0.0 2026-08-01 Creacion · 1.1.0 2026-08-03 +duration_in_traffic_s
--            2.0.0 2026-08-03 +routes[] con alternativas (cada una con su ETA de trafico).
-- ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION routing.fnc_get_route(
    p_waypoints jsonb, p_profile text DEFAULT 'car'
) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
             'route_cache_id', r.id,
             'computed_at',    r.computed_at,
             'expires_at',     r.expires_at,
             'routes',
               -- principal
               jsonb_build_array(
                 jsonb_build_object(
                   'geojson',               ST_AsGeoJSON(r.geom)::jsonb,
                   'distance_m',            r.distance_m,
                   'duration_s',            r.duration_s,
                   'duration_in_traffic_s', traffic.fnc_route_eta(r.geom, r.duration_s),
                   'steps',                 r.steps))
               ||
               -- alternativas: cada una con su propio ETA de trafico sobre su geometria.
               COALESCE((
                 SELECT jsonb_agg(
                          jsonb_build_object(
                            'geojson',    a.alt->'geojson',
                            'distance_m', (a.alt->>'distance_m')::numeric,
                            'duration_s', (a.alt->>'duration_s')::int,
                            'duration_in_traffic_s', traffic.fnc_route_eta(
                                ST_SetSRID(ST_GeomFromGeoJSON(a.alt->>'geojson'), 4326),
                                (a.alt->>'duration_s')::int),
                            'steps',      a.alt->'steps')
                          ORDER BY a.ord)
                 FROM jsonb_array_elements(
                        CASE WHEN jsonb_typeof(r.alternatives) = 'array'
                             THEN r.alternatives ELSE '[]'::jsonb END
                      ) WITH ORDINALITY AS a(alt, ord)
               ), '[]'::jsonb))
    FROM routing.route_cache r
    WHERE r.waypoints_hash = routing.fnc_waypoints_hash(p_waypoints, p_profile)
      AND r.route_profile_id = p_profile
      AND r.expires_at > now();
$$;

COMMIT;

-- =====================================================================================
-- VERIFICACION
--   -- routes[] presente y con al menos la principal (sobre una ruta ya cacheada):
--   SELECT jsonb_array_length(routing.fnc_get_route(p_waypoints, 'car') -> 'routes')
--     FROM (SELECT '[{"lat":10.98,"lon":-74.80},{"lat":10.99,"lon":-74.79}]'::jsonb
--             AS p_waypoints) q;   -- >= 1 si esos waypoints estan en cache
--   -- cada ruta trae duration_in_traffic_s:
--   SELECT (routing.fnc_get_route(p_waypoints,'car')->'routes'->0) ? 'duration_in_traffic_s'
--     FROM (SELECT '[{"lat":10.98,"lon":-74.80},{"lat":10.99,"lon":-74.79}]'::jsonb
--             AS p_waypoints) q;   -- t
-- =====================================================================================
