package services

import (
	"context"

	"ms-vehitrack/application/usecases"
	"ms-vehitrack/domain/entities"
)

// TelemetryService orchestrates telemetry application flows.
type TelemetryService interface {
	Publish(ctx context.Context, telemetry entities.Telemetry) error
}

type telemetryService struct {
	publishTelemetry usecases.PublishTelemetryUseCase
}

// NewTelemetryService creates a TelemetryService backed by use cases.
func NewTelemetryService(publishTelemetry usecases.PublishTelemetryUseCase) TelemetryService {
	return &telemetryService{publishTelemetry: publishTelemetry}
}

// Publish delegates telemetry publishing to the corresponding use case.
func (s *telemetryService) Publish(ctx context.Context, telemetry entities.Telemetry) error {
	return s.publishTelemetry.Execute(ctx, telemetry)
}
