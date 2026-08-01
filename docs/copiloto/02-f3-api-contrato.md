# Copiloto — contrato API colaborativo (ms-vehitrack)

App y backend coordinados.

## Endpoints

### `POST /api/v1/traffic/batches`
- Body: `{ "batchId": "...", "samples": [ { "cell", "speedKmh", "at", "accuracyM", "sessionId" } ] }`
- Idempotente por `batchId` (tabla `traffic_batches`)
- Persiste muestras en Postgres (`traffic_samples`)
- Refresca agregados afectados + invalida Redis
- Auth: `X-API-Key` + rate limit

### `GET /api/v1/traffic/aggregates?corridor=&slot=`
- Estrategia: **Redis (TTL ~10 min) → miss → Postgres → set Redis**
- Solo celdas con densidad ≥ `TRAFFIC_MIN_SAMPLES` (5) y `TRAFFIC_MIN_DEVICES` (3)
- Respuesta vacía (`cells: []`) si no hay densidad → app cae a histórico personal

## Almacén
- **Postgres** (crudo + agregados): `migrations/001_traffic.sql`
- **Redis**: caché de lectura de agregados (`REDIS_ADDR`)
- Job en proceso: refresh agregados cada 10 min

## Opt-in app
App envía lotes solo si `share_traffic=true` (default false).

## Local
```env
POSTGRES_ENABLED=true
POSTGRES_DSN=postgres://vehitrack:vehitrack@localhost:15433/vehitrack?sslmode=disable
REDIS_ENABLED=true
REDIS_ADDR=localhost:6379
```
