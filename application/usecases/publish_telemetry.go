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
	publisher ports.TelemetryPublisherPort
	store     ports.TelemetryStorePort
	maxAge    time.Duration
	maxSkew   time.Duration
}

// NewPublishTelemetryUseCase creates a PublishTelemetryUseCase.
// store may be nil when BigQuery persistence is disabled.
func NewPublishTelemetryUseCase(
	publisher ports.TelemetryPublisherPort,
	store ports.TelemetryStorePort,
	maxAge, maxSkew time.Duration,
) PublishTelemetryUseCase {
	return &publishTelemetryUseCase{
		publisher: publisher,
		store:     store,
		maxAge:    maxAge,
		maxSkew:   maxSkew,
	}
}

// Execute validates telemetry, publishes to messaging, and optionally stores in analytics.
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

	if uc.store != nil {
		if err := uc.store.Save(ctx, telemetry); err != nil {
			log.Printf("[PUBLISH_TELEMETRY_USECASE] operation=Store error=%v", err)
			return fmt.Errorf("store telemetry for device %s: %w", telemetry.DeviceID, err)
		}
	}

	log.Printf(
		"[PUBLISH_TELEMETRY_USECASE] operation=Publish status=success deviceId=%s latency=%s",
		telemetry.DeviceID,
		time.Since(start),
	)

	return nil
}
