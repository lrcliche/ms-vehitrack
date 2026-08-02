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
```

Las `001`–`004` son el paquete geoespacial canónico. La `005` formaliza las tablas planas
`traffic_batches/samples/aggregates` que el repositorio Go (`postgres_traffic_store.go`) ya
usaba sin DDL versionado.

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
