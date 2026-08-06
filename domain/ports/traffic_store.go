package ports

import (
	"context"
	"errors"

	"ms-vehitrack/domain/entities"
)

var (
	ErrTrafficStoreFailed = errors.New("traffic store failed")
	ErrTrafficCacheFailed = errors.New("traffic cache failed")
)

// TrafficStorePort persists raw batches/samples and aggregates (Postgres).
type TrafficStorePort interface {
	// IngestBatch is idempotent by batchID. Returns (duplicate, error).
	IngestBatch(ctx context.Context, batch entities.TrafficBatch) (duplicate bool, err error)
	// RefreshAggregates recomputes aggregates for cells (or all recent if empty)
	// within the lookback window.
	RefreshAggregates(ctx context.Context, cells []string, lookbackMinutes int) error
	// RecomputeFreeFlow recalcula la velocidad de flujo libre (p85 nocturno) de
	// cada link sobre los ultimos lookbackDays. Es prerequisito para que el ETA
	// con trafico crowd produzca factor: sin free_flow, fnc_route_eta cae a flujo
	// libre. Antes solo lo corria un cron externo; ahora el servicio lo agenda.
	RecomputeFreeFlow(ctx context.Context, lookbackDays int) error
	// AggregatesByCorridor returns rows for corridor+slot (may be empty).
	AggregatesByCorridor(ctx context.Context, corridor string, slot int) ([]entities.TrafficAggregate, error)
}

// TrafficCachePort is a short-TTL cache in front of aggregates (Redis).
type TrafficCachePort interface {
	GetAggregates(ctx context.Context, corridor string, slot int) ([]entities.TrafficAggregate, bool, error)
	SetAggregates(ctx context.Context, corridor string, slot int, rows []entities.TrafficAggregate, ttlSeconds int) error
	InvalidateCorridor(ctx context.Context, corridor string, slot int) error
}
