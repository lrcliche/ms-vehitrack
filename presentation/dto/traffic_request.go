package dto

import (
	"time"

	"ms-vehitrack/domain/entities"
)

type TrafficBatchRequest struct {
	BatchID string                 `json:"batchId" binding:"required"`
	Samples []TrafficSampleRequest `json:"samples"`
}

type TrafficSampleRequest struct {
	Cell      string  `json:"cell" binding:"required"`
	SpeedKmh  float64 `json:"speedKmh"`
	At        string  `json:"at" binding:"required"`
	AccuracyM float64 `json:"accuracyM"`
	SessionID string  `json:"sessionId" binding:"required"`
}

func (r TrafficBatchRequest) ToDomain() (entities.TrafficBatch, error) {
	samples := make([]entities.TrafficSample, 0, len(r.Samples))
	for _, s := range r.Samples {
		at, err := time.Parse(time.RFC3339, s.At)
		if err != nil {
			at, err = time.Parse(time.RFC3339Nano, s.At)
			if err != nil {
				return entities.TrafficBatch{}, entities.ErrInvalidTrafficSample
			}
		}
		samples = append(samples, entities.TrafficSample{
			Cell:      s.Cell,
			SpeedKmh:  s.SpeedKmh,
			At:        at.UTC(),
			AccuracyM: s.AccuracyM,
			SessionID: s.SessionID,
		})
	}
	return entities.TrafficBatch{BatchID: r.BatchID, Samples: samples}, nil
}
