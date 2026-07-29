package ports

import (
	"context"
	"errors"

	"ms-vehitrack/domain/entities"
)

var (
	ErrTelemetryPublishFailed = errors.New("telemetry publish failed")
)

// TelemetryPublisherPort publishes telemetry events to an external messaging system.
type TelemetryPublisherPort interface {
	Publish(ctx context.Context, telemetry entities.Telemetry) error
}
