package publishers

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
	gcpconfig "ms-vehitrack/infrastructure/gcp/config"
	gcppubsub "ms-vehitrack/infrastructure/gcp/pubsub"
)

var _ ports.TelemetryPublisherPort = (*PubSubTelemetryPublisher)(nil)

// PubSubTelemetryPublisher publishes telemetry events through Google Pub/Sub.
type PubSubTelemetryPublisher struct {
	client  *gcppubsub.Client
	topicID string
	retries int
	backoff time.Duration
}

// NewPubSubTelemetryPublisher creates a TelemetryPublisherPort adapter backed by Pub/Sub.
func NewPubSubTelemetryPublisher(client *gcppubsub.Client, cfg gcpconfig.Config) *PubSubTelemetryPublisher {
	return &PubSubTelemetryPublisher{
		client:  client,
		topicID: cfg.PubSubTopic,
		retries: cfg.PubSubPublishRetries,
		backoff: cfg.PubSubPublishRetryBackoff,
	}
}

// Publish serializes telemetry as JSON and enqueues it asynchronously on Pub/Sub.
func (p *PubSubTelemetryPublisher) Publish(ctx context.Context, telemetry entities.Telemetry) error {
	payload, err := json.Marshal(telemetry)
	if err != nil {
		return fmt.Errorf("%w: marshal telemetry: %v", ports.ErrTelemetryPublishFailed, err)
	}

	attributes := map[string]string{
		"deviceId":        telemetry.DeviceID,
		"protocol":        telemetry.Protocol,
		"idempotencyKey":  telemetryIdempotencyKey(telemetry),
		"eventTimestamp":  telemetry.Timestamp.UTC().Format(time.RFC3339Nano),
	}

	var lastErr error
	for attempt := 1; attempt <= p.retries; attempt++ {
		if err := p.client.PublishAsync(ctx, p.topicID, payload, attributes); err != nil {
			lastErr = err
			if attempt == p.retries {
				break
			}

			timer := time.NewTimer(p.backoff)
			select {
			case <-ctx.Done():
				timer.Stop()
				return fmt.Errorf("%w: %v", ports.ErrTelemetryPublishFailed, ctx.Err())
			case <-timer.C:
			}
			continue
		}

		return nil
	}

	return fmt.Errorf("%w: %v", ports.ErrTelemetryPublishFailed, lastErr)
}

func telemetryIdempotencyKey(telemetry entities.Telemetry) string {
	return telemetry.DeviceID + "|" + strconv.FormatInt(telemetry.Timestamp.UTC().UnixNano(), 10)
}
