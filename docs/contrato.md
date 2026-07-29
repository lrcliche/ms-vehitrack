# Contrato API — Telemetría OBD-II

Contrato de consumo para clientes (Flutter / web / app móvil) del microservicio **ms-vehitrack**.

Base URL local por defecto:

```text
http://localhost:8080
```

---

## 1. Autenticación

Todas las rutas bajo `/api/v1/*` exigen API key.

| Header | Requerido | Descripción |
|--------|-----------|-------------|
| `X-API-Key` | Sí | Clave compartida configurada en el backend (`API_KEY`) |
| `Content-Type` | Sí (`POST`) | `application/json` |

Sin `X-API-Key` válida → `401`.

---

## 2. Endpoints públicos (sin API key)

### `GET /health`

Liveness. El proceso está vivo.

**Respuesta `200`**

```json
{
  "errors": [],
  "data": {
    "status": "ok"
  }
}
```

### `GET /ready`

Readiness. Dependencias listas (Pub/Sub; Postgres si está habilitado).

**Respuesta `200`**

```json
{
  "errors": [],
  "data": {
    "status": "ready"
  }
}
```

**Respuesta `503`**

```json
{
  "errors": [
    {
      "code": "not-ready",
      "message": "Service dependencies are not ready"
    }
  ]
}
```

---

## 3. Publicar telemetría

### `POST /api/v1/telemetry`

Ingesta un evento OBD-II. El backend lo encola de forma asíncrona hacia Pub/Sub.

Frecuencia esperada del dispositivo: **~1 evento por segundo**.

#### Request

```http
POST /api/v1/telemetry HTTP/1.1
Host: localhost:8080
Content-Type: application/json
X-API-Key: <API_KEY>
```

```json
{
  "deviceId": "logan2021",
  "timestamp": "2026-07-28T15:30:00Z",
  "latitude": 10.98,
  "longitude": -74.80,
  "speedGps": 82,
  "speedObd": 81,
  "rpm": 2500,
  "coolantTemp": 91,
  "fuelLevel": 44,
  "protocol": "CAN11",
  "vin": "VF1XXXXXXXX"
}
```

#### Campos

| Campo | Tipo | Requerido | Reglas |
|-------|------|-----------|--------|
| `deviceId` | string | Sí | No vacío |
| `timestamp` | string (RFC3339 / ISO-8601) | Sí | UTC recomendado. No más viejo que `TELEMETRY_MAX_AGE_SECONDS` (default 24h). No más de `TELEMETRY_MAX_SKEW_SECONDS` en el futuro (default 5 min) |
| `latitude` | number | Sí | `-90` … `90` (debe enviarse explícitamente; `0` es válido) |
| `longitude` | number | Sí | `-180` … `180` |
| `speedGps` | number | No | `>= 0` |
| `speedObd` | number | No | `>= 0` |
| `rpm` | number | No | `>= 0` |
| `coolantTemp` | number | No | — |
| `fuelLevel` | number | No | `0` … `100` |
| `protocol` | string | Sí | No vacío (ej. `CAN11`) |
| `vin` | string | Sí | No vacío |

Límite de body: **64 KB** por defecto (`MAX_BODY_BYTES`).

#### Respuesta éxito `202 Accepted`

```json
{
  "errors": [],
  "data": {
    "deviceId": "logan2021",
    "timestamp": "2026-07-28T15:30:00Z",
    "status": "accepted"
  }
}
```

`202` significa: el evento fue **aceptado** para publicación. No garantiza ACK remoto final de Pub/Sub en ese mismo request.

---

## 4. Envelope de respuesta

### Éxito

```json
{
  "errors": [],
  "data": { }
}
```

### Error

```json
{
  "errors": [
    {
      "code": "validation-error",
      "message": "telemetry latitude must be between -90 and 90"
    }
  ]
}
```

Siempre consumir `errors[0].code` y `errors[0].message` en el front.

---

## 5. Códigos HTTP / errores

| HTTP | `code` | Cuándo |
|------|--------|--------|
| `202` | — | Evento aceptado |
| `400` | `bad-request` | JSON inválido / body mal formado |
| `401` | `unauthorized` | API key ausente o inválida |
| `422` | `validation-error` | Reglas de negocio (campos, rangos, timestamp viejo/futuro) |
| `429` | `rate-limit-exceeded` | Demasiadas requests desde la misma IP |
| `502` | `telemetry-publish-failed` | Fallo al encolar en Pub/Sub |
| `500` | `internal-server-error` | Error interno |
| `503` | `not-ready` | Solo en `/ready` |

### Mensajes de validación frecuentes (`422`)

- `telemetry deviceId is required`
- `telemetry timestamp is required`
- `telemetry latitude must be between -90 and 90`
- `telemetry longitude must be between -180 and 180`
- `telemetry protocol is required`
- `telemetry vin is required`
- `telemetry speedGps must be greater than or equal to zero`
- `telemetry speedObd must be greater than or equal to zero`
- `telemetry rpm must be greater than or equal to zero`
- `telemetry fuelLevel must be between 0 and 100`
- `telemetry timestamp is too old`
- `telemetry timestamp is too far in the future`

---

## 6. Rate limit

Por IP (defaults):

| Variable | Default |
|----------|---------|
| `RATE_LIMIT_RPS` | `20` |
| `RATE_LIMIT_BURST` | `40` |

Si el device publica a 1 Hz, un solo dispositivo está muy por debajo del límite. Evitar ráfagas grandes de reintentos.

---

## 7. Guía de implementación (Flutter / front)

### Headers mínimos

```dart
{
  'Content-Type': 'application/json',
  'X-API-Key': apiKey,
}
```

### Timestamp

Enviar siempre UTC en ISO-8601:

```text
2026-07-28T15:30:00.123Z
```

### Reintentos recomendados

| Situación | Acción |
|-----------|--------|
| `202` | No reintentar ese evento |
| `400` / `401` / `422` | No reintentar sin corregir el payload/clave |
| `429` | Backoff exponencial + jitter |
| `502` / `500` | Reintentar con backoff (máx. 3) |
| Timeout de red | Reintentar con backoff |

### Idempotencia

El backend genera `idempotencyKey = deviceId|timestampNanos` para Pub/Sub.
Si reenvías el **mismo** `deviceId` + **mismo** `timestamp`, el consumidor downstream puede deduplicar.
Si cambias el `timestamp` en cada reintento, se crea un evento nuevo.

### Ejemplo `curl`

```bash
curl -sS -X POST "http://localhost:8080/api/v1/telemetry" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "deviceId": "logan2021",
    "timestamp": "2026-07-28T15:30:00Z",
    "latitude": 10.98,
    "longitude": -74.80,
    "speedGps": 82,
    "speedObd": 81,
    "rpm": 2500,
    "coolantTemp": 91,
    "fuelLevel": 44,
    "protocol": "CAN11",
    "vin": "VF1XXXXXXXX"
  }'
```

---

## 8. Seguridad para el cliente

- No embeber `API_KEY` de producción en binarios públicos sin protección (usar secretos / backend intermedio si aplica).
- No loguear `vin` ni la API key en consola/crashlytics.
- Preferir HTTPS en ambientes no locales.
- Verificar `/ready` antes de iniciar ráfagas de telemetría al arrancar.

---

## 9. Versionado

- Prefijo actual: `/api/v1`
- Cambios breaking (campos renombrados/eliminados, auth distinta) requerirán `/api/v2`
- Este documento es la fuente de verdad del contrato v1 para el front

Última alineación con el código de `ms-vehitrack` (handler, DTO, validaciones de dominio y middleware).
