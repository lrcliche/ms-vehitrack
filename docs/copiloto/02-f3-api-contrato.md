# Copiloto — contrato API colaborativo (ms-vehitrack)

App y backend coordinados.

## Endpoints

### `POST /api/v1/traffic/batches`
- Body: `{ "batchId": "...", "samples": [ { "cell", "speedKmh", "at", "accuracyM", "sessionId" } ] }`
- Idempotente por `batchId` (`tracking.ingest_batch` vía `tracking.prc_ingest_telemetry`)
- Persiste posiciones + observaciones de tráfico en Postgres (sin DML directo desde Go)
- Refresca agregados con `traffic.prc_rollup_live` + invalida Redis
- Auth: `X-API-Key` + rate limit

### `GET /api/v1/traffic/aggregates?corridor=&slot=`
- Estrategia: **Redis (TTL ~10 min) → miss → `traffic.fnc_aggregates_by_corridor` → set Redis**
- Solo celdas con densidad ≥ `TRAFFIC_MIN_SAMPLES` / `TRAFFIC_MIN_DEVICES` (k-anonimato en BD)
- Respuesta vacía (`cells: []`) si no hay densidad → app cae a histórico personal

## Almacén
- **Postgres** (`migrations/001_vehitrack.sql`): telemetría + tráfico vía `fnc_` / `prc_`
- Telemetría OBD: `tracking.prc_ingest_telemetry` (reemplaza insert BigQuery)
- **Redis**: caché de lectura de agregados (`REDIS_ADDR`)
- Job en proceso: `CALL traffic.prc_rollup_live` cada ~10 min

## Opt-in app
App envía lotes solo si `share_traffic=true` (default false).

## Local
```env
POSTGRES_ENABLED=true
POSTGRES_DSN=postgres://vehitrack:vehitrack@localhost:15433/vehitrack?sslmode=disable
REDIS_ENABLED=true
REDIS_ADDR=localhost:6379
```

Aplicar migración **manualmente**:
```bash
psql "$POSTGRES_DSN" -f migrations/001_vehitrack.sql
```
