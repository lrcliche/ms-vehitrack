package ports

import (
	"context"
	"errors"

	"ms-vehitrack/domain/entities"
)

var (
	ErrTelemetryStoreFailed = errors.New("telemetry store failed")
)

// TelemetryStorePort persists telemetry events for analytics/query.
type TelemetryStorePort interface {
	Save(ctx context.Context, telemetry entities.Telemetry) error
}
