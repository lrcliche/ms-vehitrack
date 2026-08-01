package usecases

import (
	"context"
	"time"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

type GetTrafficAggregatesUseCase struct {
	store           ports.TrafficStorePort
	cache           ports.TrafficCachePort
	minSamples      int
	minDevices      int
	cacheTTLSeconds int
}

func NewGetTrafficAggregatesUseCase(
	store ports.TrafficStorePort,
	cache ports.TrafficCachePort,
	minSamples, minDevices, cacheTTLSeconds int,
) GetTrafficAggregatesUseCase {
	if minSamples <= 0 {
		minSamples = 5
	}
	if minDevices <= 0 {
		minDevices = 3
	}
	if cacheTTLSeconds <= 0 {
		cacheTTLSeconds = 600
	}
	return GetTrafficAggregatesUseCase{
		store:           store,
		cache:           cache,
		minSamples:      minSamples,
		minDevices:      minDevices,
		cacheTTLSeconds: cacheTTLSeconds,
	}
}

type GetTrafficAggregatesResult struct {
	Corridor string
	Slot     int
	Cells    []entities.TrafficAggregate
	Cached   bool
}

func (uc GetTrafficAggregatesUseCase) Execute(
	ctx context.Context,
	corridor string,
	slot int,
) (GetTrafficAggregatesResult, error) {
	if corridor == "" {
		corridor = "unknown"
	}
	if slot < 0 {
		slot = entities.SlotFor(time.Now().UTC())
	}

	if uc.cache != nil {
		if rows, hit, err := uc.cache.GetAggregates(ctx, corridor, slot); err == nil && hit {
			return GetTrafficAggregatesResult{
				Corridor: corridor,
				Slot:     slot,
				Cells:    filterDense(rows, uc.minSamples, uc.minDevices),
				Cached:   true,
			}, nil
		}
	}

	if uc.store == nil {
		return GetTrafficAggregatesResult{}, entities.ErrTrafficStoreUnavailable
	}

	rows, err := uc.store.AggregatesByCorridor(ctx, corridor, slot)
	if err != nil {
		return GetTrafficAggregatesResult{}, err
	}

	if uc.cache != nil {
		_ = uc.cache.SetAggregates(ctx, corridor, slot, rows, uc.cacheTTLSeconds)
	}

	return GetTrafficAggregatesResult{
		Corridor: corridor,
		Slot:     slot,
		Cells:    filterDense(rows, uc.minSamples, uc.minDevices),
		Cached:   false,
	}, nil
}

func filterDense(rows []entities.TrafficAggregate, minSamples, minDevices int) []entities.TrafficAggregate {
	out := make([]entities.TrafficAggregate, 0, len(rows))
	for _, r := range rows {
		if r.SampleCount >= minSamples && r.DeviceCount >= minDevices {
			out = append(out, r)
		}
	}
	return out
}
