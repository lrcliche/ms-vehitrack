# ms-vehitrack

Microservicio Go para tracking de vehículos, con arquitectura hexagonal y API REST.

## Purpose

`ms-vehitrack` separa dominio, aplicación, infraestructura y presentación con límites estrictos, listo para desarrollo local y evolución a producción.

## Architecture Summary

- **domain**: entities and ports (business contracts)
- **application**: use cases/services orchestrating business rules
- **infrastructure**: adapters (database/repository implementations)
- **presentation**: HTTP handlers, middleware, responses, routing, DI container

The architecture guard script (`scripts/check_architecture.sh`) enforces these boundaries.

Reglas anti-deuda (obligatorias para agentes y humanos): `docs/zeroTechDebtIA.md` y `.cursor/rules/`.

Contrato de consumo front (telemetría): `docs/contrato.md`.

## Prerequisites

- Go 1.25+
- Google Cloud credentials (ADC or `GOOGLE_APPLICATION_CREDENTIALS`)
- [Air](https://github.com/air-verse/air) for live reload in dev mode
- PostgreSQL only if `POSTGRES_ENABLED=true`

Install Air:

```bash
go install github.com/air-verse/air@latest
```

## Environment Setup

1. Copy environment template:

```bash
make up
```

2. Set required values in `.env`, especially `API_KEY`, `GCP_PROJECT_ID`, `GCP_PUBSUB_TOPIC`.

## Healthcheck

The API exposes:

- `GET /health` — liveness
- `GET /ready` — readiness (Pub/Sub client; Postgres if enabled)

Protected routes under `/api/v1/*` require header `X-API-Key`.

## Local Development Flow

### Run in development mode (live reload)

```bash
make dev
```

Or directly:

```bash
air
```

### Run normally (no live reload)

```bash
make run
```

### Run tests

```bash
make test
```

### Run architecture checks

```bash
make architecture-check
```

### Run safe lint checks

```bash
make lint-safe
```

## Main Developer Commands

- `make help` — list all commands
- `make up` — bootstrap `.env`
- `make dev` — live reload with Air
- `make run` — run API once
- `make test` — run all tests
- `make test-cover` — test coverage summary
- `make fmt` — format Go code
- `make tidy` — tidy dependencies
- `make lint-safe` — gofmt/go vet/go test checks
- `make architecture-check` — hexagonal boundary checks
- `make build` — build binary in `./bin`
- `make clean` — remove generated artifacts
