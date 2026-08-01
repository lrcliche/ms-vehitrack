package services

import (
	"context"

	"ms-vehitrack/application/usecases"
	"ms-vehitrack/domain/entities"
)

// TrafficService orchestrates collaborative traffic flows.
type TrafficService interface {
	IngestBatch(ctx context.Context, batch entities.TrafficBatch) (usecases.IngestTrafficBatchResult, error)
	Aggregates(ctx context.Context, corridor string, slot int) (usecases.GetTrafficAggregatesResult, error)
}

type trafficService struct {
	ingest usecases.IngestTrafficBatchUseCase
	get    usecases.GetTrafficAggregatesUseCase
}

func NewTrafficService(
	ingest usecases.IngestTrafficBatchUseCase,
	get usecases.GetTrafficAggregatesUseCase,
) TrafficService {
	return &trafficService{ingest: ingest, get: get}
}

func (s *trafficService) IngestBatch(
	ctx context.Context,
	batch entities.TrafficBatch,
) (usecases.IngestTrafficBatchResult, error) {
	return s.ingest.Execute(ctx, batch)
}

func (s *trafficService) Aggregates(
	ctx context.Context,
	corridor string,
	slot int,
) (usecases.GetTrafficAggregatesResult, error) {
	return s.get.Execute(ctx, corridor, slot)
}
