package usecases

import (
	"context"
	"fmt"
	"log"
	"time"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

// PublishTelemetryUseCase validates and publishes telemetry events.
type PublishTelemetryUseCase interface {
	Execute(ctx context.Context, telemetry entities.Telemetry) error
}

type publishTelemetryUseCase struct {
	publisher  ports.TelemetryPublisherPort
	maxAge     time.Duration
	maxSkew    time.Duration
}

// NewPublishTelemetryUseCase creates a PublishTelemetryUseCase.
func NewPublishTelemetryUseCase(publisher ports.TelemetryPublisherPort, maxAge, maxSkew time.Duration) PublishTelemetryUseCase {
	return &publishTelemetryUseCase{
		publisher: publisher,
		maxAge:    maxAge,
		maxSkew:   maxSkew,
	}
}

// Execute validates telemetry and publishes it through the domain port.
func (uc *publishTelemetryUseCase) Execute(ctx context.Context, telemetry entities.Telemetry) error {
	start := time.Now()

	if err := telemetry.ValidateWithClock(time.Now().UTC(), uc.maxAge, uc.maxSkew); err != nil {
		log.Printf("[PUBLISH_TELEMETRY_USECASE] operation=Validate error=%v", err)
		return err
	}

	if err := uc.publisher.Publish(ctx, telemetry); err != nil {
		log.Printf("[PUBLISH_TELEMETRY_USECASE] operation=Publish error=%v", err)
		return fmt.Errorf("publish telemetry for device %s: %w", telemetry.DeviceID, err)
	}

	log.Printf(
		"[PUBLISH_TELEMETRY_USECASE] operation=Publish status=success deviceId=%s latency=%s",
		telemetry.DeviceID,
		time.Since(start),
	)

	return nil
}
