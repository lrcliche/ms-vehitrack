package usecases

import (
	"context"
	"strconv"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

type IngestTrafficBatchUseCase struct {
	store ports.TrafficStorePort
	cache ports.TrafficCachePort
}

func NewIngestTrafficBatchUseCase(
	store ports.TrafficStorePort,
	cache ports.TrafficCachePort,
) IngestTrafficBatchUseCase {
	return IngestTrafficBatchUseCase{store: store, cache: cache}
}

type IngestTrafficBatchResult struct {
	BatchID    string
	Accepted   bool
	Duplicate  bool
	SampleCount int
}

func (uc IngestTrafficBatchUseCase) Execute(
	ctx context.Context,
	batch entities.TrafficBatch,
) (IngestTrafficBatchResult, error) {
	if uc.store == nil {
		return IngestTrafficBatchResult{}, entities.ErrTrafficStoreUnavailable
	}
	if err := batch.Validate(); err != nil {
		return IngestTrafficBatchResult{}, err
	}

	dup, err := uc.store.IngestBatch(ctx, batch)
	if err != nil {
		return IngestTrafficBatchResult{}, err
	}

	result := IngestTrafficBatchResult{
		BatchID:     batch.BatchID,
		Accepted:    true,
		Duplicate:   dup,
		SampleCount: len(batch.Samples),
	}
	if dup {
		return result, nil
	}

	cells := uniqueCells(batch.Samples)
	_ = uc.store.RefreshAggregates(ctx, cells, 30)

	if uc.cache != nil {
		seen := map[string]struct{}{}
		for _, s := range batch.Samples {
			corridor := entities.CorridorFromCell(s.Cell)
			slot := entities.SlotFor(s.At)
			key := corridor + ":" + strconv.Itoa(slot)
			if _, ok := seen[key]; ok {
				continue
			}
			seen[key] = struct{}{}
			_ = uc.cache.InvalidateCorridor(ctx, corridor, slot)
		}
	}
	return result, nil
}

func uniqueCells(samples []entities.TrafficSample) []string {
	m := map[string]struct{}{}
	out := make([]string, 0, len(samples))
	for _, s := range samples {
		if _, ok := m[s.Cell]; ok {
			continue
		}
		m[s.Cell] = struct{}{}
		out = append(out, s.Cell)
	}
	return out
}
