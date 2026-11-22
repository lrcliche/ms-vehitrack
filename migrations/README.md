# Migraciones VehiTrack (`ms-vehitrack`)

Migraciones **manuales**, numeradas, aplicadas con `psql`. Nunca auto-migrate al arrancar
(convención C7 del modelo). Cada archivo es idempotente y trae sus bloques de verificación al
pie.

## Orden de aplicación

```bash
export POSTGRES_DSN="postgres://<owner>@localhost:15433/vehitrack"

psql "$POSTGRES_DSN" -f migrations/001_vehitrack.sql          # baseline: tenant, device, tracking, geo, traffic.*, ops
psql "$POSTGRES_DSN" -f migrations/002_geocoding.sql          # geocoder CO + diccionario versionado
psql "$POSTGRES_DSN" -f migrations/003_device_data.sql        # favoritos, POI, geocercas, motor de sync
psql "$POSTGRES_DSN" -f migrations/004_routing_offline_ops.sql# cache de rutas, paquetes offline, log de API, mantenimiento
psql "$POSTGRES_DSN" -f migrations/005_legacy_traffic_gcp.sql # DDL del path GCP heredado (trafico plano)
psql "$POSTGRES_DSN" -f migrations/006_app_grants.sql        # grants DML/EXECUTE del rol de la app (vehitrack_app)
psql "$POSTGRES_DSN" -f migrations/007_routing_traffic_eta.sql# ETA con trafico vivo en POST /routes (duration_in_traffic)
psql "$POSTGRES_DSN" -f migrations/008_routing_alternatives.sql# alternativas reales: fnc_get_route devuelve routes[]
```

## API empresarial v2

Aplicar en orden después del modelo base existente; estas migraciones son manuales y no se
ejecutan al iniciar la API:

```bash
psql "$POSTGRES_DSN" -f migrations/011_business_model.sql
psql "$POSTGRES_DSN" -f migrations/012_business_seed.sql
psql "$POSTGRES_DSN" -f migrations/013_business_jwt_routes.sql
psql "$POSTGRES_DSN" -f migrations/014_business_assignment_candidates.sql
psql "$POSTGRES_DSN" -f migrations/015_business_service_requests_api.sql
psql "$POSTGRES_DSN" -f migrations/016_business_enterprise_operations.sql
psql "$POSTGRES_DSN" -f migrations/017_driver_app_self_service.sql
psql "$POSTGRES_DSN" -f migrations/018_driver_service_transitions.sql
psql "$POSTGRES_DSN" -f migrations/019_enterprise_driver_user_link.sql
psql "$POSTGRES_DSN" -f migrations/020_driver_services_contact_order.sql
psql "$POSTGRES_DSN" -f migrations/021_driver_app_jwt_location.sql
```

La `014` entrega los candidatos de asignación con datos del vehículo, conductor, ubicación y
estimaciones. La `015` guarda `customer_name` como referencia de la solicitud y agrega la
rutina autorizada para crear solicitudes desde la API. La ruta de creación calcula el recorrido
antes de insertar para no dejar una solicitud creada si OSRM no puede estimarlo.

La `016` implementa lecturas y operaciones empresariales (dashboard, flota, conductores,
solicitudes, asignaciones, cierre de gastos y rentabilidad) para `/api/v2/enterprise`. Las
operaciones requieren JWT v2, las rutinas comprueban tenant/permisos y la API no consulta tablas
empresariales directamente. Requiere los roles PostgreSQL `vehitrack_owner` y `vehitrack_app`.

La `017` agrega las lecturas autenticadas del App Driver (`/api/v2/drivers/me/*`). El conductor
se identifica por el `tenant_user_id` del JWT vinculado en `business.driver`; la API llama solo
funciones `business.fnc_*`. Los adjuntos se descargan por una ruta JWT protegida y no se exponen
claves de almacenamiento. La fecha del resumen usa `America/Bogota` y los documentos vencen
pronto dentro de 30 días. El esquema actual no tiene foto de conductor ni código comercial de
solicitud: `foto_url` devuelve `null` y `codigo` es una referencia estable derivada del UUID.

La `018` agrega las transiciones autenticadas `POST /api/v2/drivers/me/services/{id}/start` y
`POST /api/v2/drivers/me/services/{id}/finish`. El `{id}` es el ID de la solicitud devuelto por
`GET /drivers/me/services`; ambas funciones derivan al conductor del JWT y verifican tenant,
asignación confirmada y estado antes de actualizar la ejecución. `finish` marca la solicitud como
completada y libera conductor y vehículo; los gastos y kilometraje real siguen siendo un cierre
administrativo separado y no se inventan desde la app del conductor.

La `019` permite enviar `tenant_user_id` opcional al crear o actualizar un conductor desde
`/api/v2/enterprise/drivers`. La rutina comprueba que la cuenta esté activa en el mismo tenant,
tenga el rol `driver` y no esté vinculada a otro conductor. Omitir el campo conserva el vínculo
actual; la respuesta y el listado informan `usuario_vinculado`.

La `020` corrige la selección del contacto de servicio: `business.customer_contact` no tiene una
columna `is_primary`, así que el ordenamiento usa el ID del contacto y evita un error SQL al leer
los servicios del conductor.

La `021` agrega `POST /api/v2/drivers/me/telemetry`, autenticado con JWT de conductor y `X-Device-Id`,
con el mismo body de batch que v1. En su primera versión validaba el vínculo del dispositivo del
vehículo; la `024` cambia esa validación para el teléfono de la app y conserva `vehicle_device`
para el tracker instalado en el vehículo. Guarda las muestras en `tracking.position` y actualiza la
posición actual del conductor en `business.driver_location` con la muestra reciente y precisa.
Las recomendaciones usan esa posición si tiene máximo diez minutos y precisión de hasta 100 m;
si no, usan la última posición del dispositivo del vehículo. `POST /api/v1/telemetry/batch`
permanece disponible sin cambios y sigue guardando historial por dispositivo.

La `024` agrega `business.driver_device` con historial de vínculos teléfono↔conductor, más
`POST /api/v2/drivers/me/devices/attach|detach`. La app registra el teléfono por v1 y lo vincula
automáticamente al restaurar/iniciar sesión; al cerrar sesión se cierra el vínculo. Un mismo
conductor puede tener varios teléfonos vinculados. Un teléfono no se puede vincular a más de un
conductor activo ni se puede usar como dispositivo del vehículo mientras tenga ese vínculo.

Las `001`–`004` son el paquete geoespacial canónico. La `005` formaliza las tablas planas
`traffic_batches/samples/aggregates` que el repositorio Go (`postgres_traffic_store.go`) ya
usaba sin DDL versionado. La `006` consolida los grants del rol de la app. La `007` añade el
ETA ajustado a tráfico vivo (`traffic.fnc_route_eta` + `routing.fnc_get_route`) sin tocar tablas.

## Prerrequisito: roles PostgreSQL

`002_geocoding.sql` tiene un **preflight que aborta** si el rol `vehitrack_app` es dueño de
tablas con RLS (el aislamiento por tenant sería decorativo). Crear los roles **antes** de
aplicar migraciones (requiere superusuario, es infra — no va en una migración versionada ni
con credenciales en git):

```sql
-- dueño de las tablas: ejecuta migraciones, rollups y cron. Ignora RLS a propósito.
CREATE ROLE vehitrack_owner LOGIN PASSWORD '<owner-pass>';
-- rol de la app: NOLOGIN, sujeto a RLS. El ms se conecta con un login al que se le hace GRANT.
CREATE ROLE vehitrack_app  NOLOGIN;
CREATE ROLE vehitrack_api  LOGIN PASSWORD '<api-pass>' IN ROLE vehitrack_app;
```

- Las migraciones se aplican **como `vehitrack_owner`** (dueño de las tablas).
- El `ms` se conecta **como `vehitrack_api`** (hereda `vehitrack_app`, sujeto a RLS). Nunca
  como el dueño.

Verificación de que RLS está activo (doc 01 §4):

```sql
SELECT n.nspname, c.relname, pg_get_userbyid(c.relowner) AS owner, c.relrowsecurity
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('device','tracking','traffic','routing') AND c.relkind = 'r';
```

## Reconciliación GCP ↔ PG (decisión 2026-08-01)

El antiguo `001_traffic.sql` (que en realidad era el viejo `004_tenant`, mal nombrado) se
movió a `docs/legacy/001_traffic.legacy.sql`. Se **conserva** el diseño GCP de
telemetría/tráfico (BigQuery/Pub-Sub/Redis + tablas planas de la `005`); el modelo procedural
`traffic.observation/link/live_state` de la `001` queda como objetivo, sin reescribir el
código todavía. Convergencia agendada para las fases 6–7 del roadmap.

## Cron / timers (doc 01 §7)

```
*/3 * * * *  psql -c "CALL traffic.prc_rollup_live(NULL, NULL);"
7   * * * *  psql -c "CALL traffic.prc_rollup_profile(now() - interval '1 hour', now(), NULL);"
30  3 * * 1  psql -c "CALL traffic.prc_recompute_free_flow(28, NULL);"
0   4 * * *  psql -c "CALL ops.prc_daily_maintenance(NULL);"
0   5 1 1 *  psql -c "CALL public.prc_generate_holiday(...);"
```

Todo el cron corre **como dueño**, no como `vehitrack_app`. La única llamada de particiones es
`ops.prc_daily_maintenance` (no la línea suelta de `ops.prc_maintain_partitions`).
