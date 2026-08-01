package entities

import (
	"errors"
	"time"
)

var (
	ErrInvalidTrafficBatchID   = errors.New("batchId is required")
	ErrInvalidTrafficSample    = errors.New("invalid traffic sample")
	ErrTrafficStoreUnavailable = errors.New("traffic store unavailable")
)

// TrafficSample is one anonymized cell-speed observation.
type TrafficSample struct {
	Cell      string
	SpeedKmh  float64
	At        time.Time
	AccuracyM float64
	SessionID string
}

// TrafficBatch is an idempotent upload unit.
type TrafficBatch struct {
	BatchID string
	Samples []TrafficSample
}

func (b TrafficBatch) Validate() error {
	if b.BatchID == "" {
		return ErrInvalidTrafficBatchID
	}
	for _, s := range b.Samples {
		if s.Cell == "" || s.SessionID == "" || s.At.IsZero() {
			return ErrInvalidTrafficSample
		}
		if s.SpeedKmh < 0 || s.SpeedKmh > 250 {
			return ErrInvalidTrafficSample
		}
	}
	return nil
}

// TrafficAggregate is the only shape the app should read.
type TrafficAggregate struct {
	Cell            string  `json:"cell"`
	Slot            int     `json:"slot"`
	Corridor        string  `json:"corridor"`
	MedianSpeedKmh  float64 `json:"medianSpeedKmh"`
	SampleCount     int     `json:"sampleCount"`
	DeviceCount     int     `json:"deviceCount"`
}

// SlotFor returns the 30-minute slot index for t (hour*2 + half).
func SlotFor(t time.Time) int {
	slot := t.Hour() * 2
	if t.Minute() >= 30 {
		slot++
	}
	return slot
}

// CorridorFromCell uses geohash prefix length 5 as corridor key.
func CorridorFromCell(cell string) string {
	if len(cell) >= 5 {
		return cell[:5]
	}
	return cell
}
