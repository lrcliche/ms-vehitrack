-- =====================================================================================
-- VehiTrack · migrations/006_app_grants.sql
-- Grants DML del rol de la app (vehitrack_app) — AUDITORÍA CONSOLIDADA.
--
-- Depende de 001–004. Aplicar como dueño:
--   psql "$POSTGRES_DSN" -f migrations/006_app_grants.sql
--
-- -------------------------------------------------------------------------------------
-- POR QUÉ EXISTE
-- -------------------------------------------------------------------------------------
-- Las rutinas prc_ de la app son SECURITY INVOKER (ADR-006: DEFINER solo en provision).
-- Como corren con los privilegios del que las llama (vehitrack_app), el rol necesita DML
-- sobre las tablas que esas rutinas escriben — y SELECT sobre las que leen. Las migraciones
-- 001–004 solo otorgaron SELECT en las tablas de datos y EXECUTE en las rutinas, así que sin
-- esto los caminos de escritura fallan con "permission denied for table ...".
--
-- Esto NO debilita el aislamiento: RLS sigue filtrando por tenant en las tablas con RLS, y la
-- disciplina de "cero DML crudo en infrastructure/postgres" la sostiene el code review
-- (ADR-004), no la ausencia de privilegio. 002 ya trae los grants de geo.*; aquí van device,
-- tracking, traffic, routing y ops.
--
-- Verificado en BD scratch ejecutando las prc_ como SET ROLE vehitrack_app.
-- =====================================================================================

BEGIN;

SET LOCAL client_min_messages = WARNING;

-- Lecturas que hacen las rutinas (resolver tenant del device, cuenta, grilla/link de tráfico).
GRANT SELECT ON
    device.device, device.account,
    geo.grid_cell, geo.street_segment,
    traffic.link, traffic.live_state, traffic.profile
TO vehitrack_app;

-- device: registro/actualización de equipo y OBD, y los datos sincronizables del usuario
-- (favoritos, POI, geocercas, ajustes, eventos, paquetes instalados). DELETE = soft delete
-- (UPDATE) salvo device_package (remove físico) y device.device (no se borra desde la app).
GRANT INSERT, UPDATE ON
    device.device, device.obd_session
TO vehitrack_app;

GRANT INSERT, UPDATE, DELETE ON
    device.favorite_place, device.place_user, device.geofence,
    device.device_setting, device.geofence_event, device.device_package
TO vehitrack_app;

-- prc_sync_push devuelve next_version leyendo `SELECT last_value FROM device.seq_sync_version`:
-- eso exige SELECT sobre la secuencia (USAGE, otorgado en 003, solo habilita nextval/currval).
GRANT SELECT ON SEQUENCE device.seq_sync_version TO vehitrack_app;

-- tracking: ingesta de telemetría y viajes (prc_ingest_telemetry, prc_upsert_trip,
-- prc_close_trip). position es append-only; trip/trip_track se actualizan al cerrar.
GRANT INSERT, UPDATE, DELETE ON
    tracking.ingest_batch, tracking.trip, tracking.trip_track, tracking.position
TO vehitrack_app;

-- traffic: prc_ingest_telemetry deriva la observación cruda por tenant. Los agregados
-- globales (live_state/profile) los escribe el cron como dueño, no la app.
GRANT INSERT ON traffic.observation TO vehitrack_app;

-- routing: cache de rutas OSRM + registro de peticiones (hit rate).
GRANT INSERT, UPDATE ON routing.route_cache TO vehitrack_app;
GRANT INSERT         ON routing.route_request TO vehitrack_app;

-- ops: el middleware escribe el log de API por request (best-effort; la creación de
-- particiones la hace el mantenimiento diario como dueño). El grant en la tabla particionada
-- se hereda a las particiones.
GRANT INSERT ON ops.api_request_log TO vehitrack_app;

-- -------------------------------------------------------------------------------------
-- fnc_tenant_of_device debe ser SECURITY DEFINER
-- -------------------------------------------------------------------------------------
-- Es lo PRIMERO que hace el middleware: resolver el tenant de un device por su uuid, ANTES
-- de poder setear app.tenant_id. Bajo RLS y como INVOKER, vehitrack_app sin contexto de
-- tenant no ve la fila de device.device y la función devuelve NULL — se rompe TODA la API con
-- tenant (huevo-y-gallina). Va DEFINER (solo lectura, keyed por uuid, sin escalada), con
-- search_path fijado por seguridad (misma regla que provision, ADR-006).
ALTER FUNCTION device.fnc_tenant_of_device(uuid) SECURITY DEFINER;
ALTER FUNCTION device.fnc_tenant_of_device(uuid) SET search_path = pg_catalog, public;

COMMIT;

-- =====================================================================================
-- VERIFICACIÓN (como vehitrack_app, con tenant seteado):
--   SET ROLE vehitrack_app; SELECT set_config('app.tenant_id', '<tenant>', false);
--   CALL device.prc_upsert_favorite_place(...);   -- debe aplicar
--   CALL device.prc_soft_delete('favorite_place', ...);
--   CALL device.prc_track_device_package(...);
--   RESET ROLE;
-- =====================================================================================
