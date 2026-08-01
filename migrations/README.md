# Migraciones SQL — aplicación MANUAL

Las migraciones viven en `/migrations` y **no** se ejecutan al arrancar la API.

## Baseline actual

```bash
psql "$POSTGRES_DSN" -f migrations/001_vehitrack.sql
```

Requisitos: PostgreSQL 16+ con PostGIS 3.4+ (ver `docker-compose.yml` → imagen `postgis/postgis`).

Si la base ya tenía `traffic_batches` / `traffic_samples` / `traffic_aggregates`
del baseline anterior, **recrea la base** antes de aplicar `001_vehitrack.sql`
(no es un ALTER incremental).

```bash
docker compose exec vehitrack-pg psql -U vehitrack -d postgres -c "DROP DATABASE IF EXISTS vehitrack WITH (FORCE);"
docker compose exec vehitrack-pg psql -U vehitrack -d postgres -c "CREATE DATABASE vehitrack OWNER vehitrack;"
psql "$POSTGRES_DSN" -f migrations/001_vehitrack.sql
```
