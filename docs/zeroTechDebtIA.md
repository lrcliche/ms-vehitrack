# Zero Tech Debt IA Guide (ms-vehitrack)

Documento de gobernanza para **desarrolladores y agentes de IA**.
Objetivo: mantener **deuda técnica cercana a cero** sin romper la arquitectura hexagonal.

Complementa:

- `docs/architectureIA.md`
- `docs/AddFeatureIA.md`
- `.cursor/rules/*`

---

## 1) Definición de “cero deuda” en este repo

Una entrega se considera aceptable solo si:

1. Respeta el flujo `Handler → Service → UseCase → Port → Adapter`.
2. No introduce acoplamientos prohibidos entre capas.
3. No agrega superficie de seguridad abierta.
4. No deja código muerto, scaffold o dependencias obligatorias sin uso.
5. No hardcodea secretos, project IDs ni configuración de entorno.
6. Incluye tests del comportamiento tocado.
7. Actualiza `.env.example` y docs si cambia contratos/env.

Si algo “funciona” pero viola estas reglas, **no se mergea**.

---

## 2) Estructura canónica

```text
cmd/api/                  # bootstrap únicamente
domain/
  entities/               # reglas de negocio puras
  ports/                  # contratos de salida/entrada de dominio
application/
  config/                 # env de aplicación (HTTP, API key, PG opcional)
  services/               # fachada que orquesta use cases
  usecases/               # casos de uso (validar + puerto)
infrastructure/
  database/               # Postgres opcional (wrapper, sin filtrar driver a presentation)
  gcp/
    config/               # env GCP
    bigquery/             # cliente reutilizable (opcional)
    pubsub/               # cliente reutilizable (requerido para telemetría)
    storage/              # cliente reutilizable (opcional)
  publishers/             # adapters de ports (ej. Pub/Sub telemetry)
  repositories/           # adapters de persistencia cuando existan
presentation/
  container/              # único composition root
  handlers/               # HTTP → service
  dto/                    # contratos HTTP ≠ domain entities
  routes/
  middleware/             # auth, rate limit, recovery, trace, body limit
  errors/
  responses/
  logging/
  server/
migrations/               # SQL manual en raíz; NUNCA auto-migrate al boot
tests/
docs/
scripts/
.cursor/rules/
```

### Carpetas prohibidas

- `utils/`, `common/`, `helpers/`, `shared/`, `misc/` genéricos
- lógica de negocio dentro de `infrastructure/` o `presentation/handlers`
- clientes GCP/DB usados desde handlers

---

## 3) Flujo de dependencias (obligatorio)

```text
HTTP
  ↓
Handler          (presentation)  — bind DTO, map domain, llama service
  ↓
Service          (application)   — orquesta use cases
  ↓
UseCase          (application)   — valida + puerto
  ↓
Port             (domain)        — interfaz
  ↓
Adapter          (infrastructure)— Pub/Sub, DB, etc.
```

### Condiciones de aceptación por capa

| Capa | Puede | No puede |
|------|-------|----------|
| Handler | DTO, status HTTP, logging de request, service | ports, repos, SQL, SDK GCP |
| Service | llamar use cases | importar infrastructure |
| UseCase | entities + ports | Gin, pgx, bigquery, pubsub SDK |
| Port | tipos de domain | detalles técnicos |
| Adapter | SDK, retries técnicos, serialize | reglas de negocio |
| Container | cablear todo | exponer clientes concretos a handlers |

---

## 4) Condiciones anti-deuda (checklist de PR)

### Arquitectura

- [ ] No hay imports `infrastructure` en `domain` ni `application`
- [ ] No hay `pgxpool` / SQL driver en `presentation`
- [ ] Nuevos features: port + adapter + use case + service + handler + wiring en container
- [ ] `var _ ports.X = (*Adapter)(nil)` en adapters
- [ ] Solo `presentation/container` instancia services/usecases de runtime

### Seguridad

- [ ] `/api/v1/*` protegido con `X-API-Key`
- [ ] Rate limit activo
- [ ] Body limit activo
- [ ] Recovery loguea panics
- [ ] Sin DSN/API keys/VIN/tokens en logs
- [ ] Attributes Pub/Sub sin PII; incluir `idempotencyKey`

### Performance / escalabilidad

- [ ] Publish de telemetría no bloquea ACK remoto en el request HTTP
- [ ] Timeouts configurables por env
- [ ] Dependencias no usadas no se inicializan (BQ/Storage/PG opcionales)
- [ ] `/ready` valida deps reales; `/health` es liveness

### Calidad de código

- [ ] Sin TODOs permanentes, código comentado o scaffold de plantilla
- [ ] Sin magic strings de infra (topics, project IDs) en código
- [ ] Errores tipados de domain/ports + wrap `%w`
- [ ] DTOs separados de entities
- [ ] Nombres claros; archivos cohesivos; sin God objects

### Testing / DevOps

- [ ] Tests del service/use case tocado
- [ ] `go test ./...` verde
- [ ] `scripts/check_architecture.sh` verde
- [ ] `.env.example` actualizado
- [ ] CI (`Dockerfile` + GitHub Actions) no roto

---

## 5) Configuración por entorno (sin hardcode)

### App (`application/config`)

- `API_KEY` (requerida)
- `HTTP_PORT`, timeouts, `MAX_BODY_BYTES`
- `RATE_LIMIT_RPS`, `RATE_LIMIT_BURST`
- `POSTGRES_ENABLED`, `POSTGRES_DSN` (opcional)
- `TELEMETRY_MAX_AGE_SECONDS`, `TELEMETRY_MAX_SKEW_SECONDS`

### GCP (`infrastructure/gcp/config`)

- `GCP_PROJECT_ID`, `GCP_PUBSUB_TOPIC` (requeridos)
- `GOOGLE_APPLICATION_CREDENTIALS` (opcional si hay ADC)
- `GCP_BIGQUERY_ENABLED` + dataset
- `GCP_STORAGE_ENABLED` + bucket
- timeouts/retries Pub/Sub

Toda variable nueva **debe** aparecer en `.env.example` vacía o con placeholder no secreto.

---

## 6) Patrones obligatorios

### Telemetría

1. DTO HTTP → `ToDomain()`
2. Service.Publish → UseCase.Execute
3. ValidateWithClock (frescura)
4. Port.Publish → adapter Pub/Sub async + idempotency key

### Nuevos adapters externos

1. Cliente técnico en `infrastructure/gcp/...` o paquete infra
2. Port en `domain/ports`
3. Adapter en `infrastructure/publishers` o `repositories`
4. Use case + service
5. Handler + route
6. Wire en container

### Postgres

- Deshabilitado por defecto
- Si se habilita: wrapper `infrastructure/database`, sin filtrar `pgxpool` a presentation

---

## 7) Deuda explícitamente prohibida

| Deuda | Por qué está prohibida |
|-------|------------------------|
| Endpoint sin auth | abuso Pub/Sub / costos / datos falsos |
| Publish sync en HTTP | no escala a 1 Hz × N devices |
| Clientes BQ/Storage obligatorios sin uso | fragilidad de boot |
| Scaffold `products` u otros demos | contaminan dominio |
| Logs con secretos/PII | seguridad y compliance |
| Health mentiroso | tráfico a instancias rotas |
| Lógica en handlers | rompe testabilidad y hexagonal |
| `utils` genéricos | basurero de acoplamiento |
| Auto-migrate al boot | riesgo de prod |

---

## 8) Cómo agregar un feature sin deuda

1. Leer este doc + `architectureIA.md` + `AddFeatureIA.md`
2. Diseñar entity + port primero
3. Implementar use case y tests con fake del port
4. Adapter infra
5. Service + handler + DTO
6. Route + middleware (auth ya aplica a `/api/v1`)
7. Wire en container
8. Actualizar `.env.example` si hay config
9. Correr:

```bash
go test ./...
go vet ./...
bash ./scripts/check_architecture.sh
```

---

## 9) DoD (Definition of Done)

Una tarea está terminada solo si:

- Compila y tests pasan
- Arquitectura check pasa
- No hay hallazgos de seguridad del checklist
- No queda código muerto del cambio
- Docs/rules actualizados si cambió una convención

---

## 10) Precedencia

Si hay conflicto:

1. Este documento + `.cursor/rules`
2. `docs/architectureIA.md`
3. Preferencias ad-hoc del chat

Los agentes **no** deben “simplificar” saltándose capas para ir más rápido.
