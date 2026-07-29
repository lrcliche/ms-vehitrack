package entities

import (
	"errors"
	"strings"
	"time"
)

var (
	ErrInvalidTelemetryDeviceID   = errors.New("telemetry deviceId is required")
	ErrInvalidTelemetryTimestamp  = errors.New("telemetry timestamp is required")
	ErrInvalidTelemetryLatitude   = errors.New("telemetry latitude must be between -90 and 90")
	ErrInvalidTelemetryLongitude  = errors.New("telemetry longitude must be between -180 and 180")
	ErrInvalidTelemetryProtocol   = errors.New("telemetry protocol is required")
	ErrInvalidTelemetryVIN        = errors.New("telemetry vin is required")
	ErrInvalidTelemetrySpeedGPS   = errors.New("telemetry speedGps must be greater than or equal to zero")
	ErrInvalidTelemetrySpeedOBD   = errors.New("telemetry speedObd must be greater than or equal to zero")
	ErrInvalidTelemetryRPM        = errors.New("telemetry rpm must be greater than or equal to zero")
	ErrInvalidTelemetryFuelLevel  = errors.New("telemetry fuelLevel must be between 0 and 100")
)

// Telemetry represents an OBD-II telemetry event from a vehicle device.
type Telemetry struct {
	DeviceID    string    `json:"deviceId"`
	Timestamp   time.Time `json:"timestamp"`
	Latitude    float64   `json:"latitude"`
	Longitude   float64   `json:"longitude"`
	SpeedGPS    float64   `json:"speedGps"`
	SpeedOBD    float64   `json:"speedObd"`
	RPM         float64   `json:"rpm"`
	CoolantTemp float64   `json:"coolantTemp"`
	FuelLevel   float64   `json:"fuelLevel"`
	Protocol    string    `json:"protocol"`
	VIN         string    `json:"vin"`
}

// Validate checks business rules for a telemetry event.
func (t Telemetry) Validate() error {
	if strings.TrimSpace(t.DeviceID) == "" {
		return ErrInvalidTelemetryDeviceID
	}
	if t.Timestamp.IsZero() {
		return ErrInvalidTelemetryTimestamp
	}
	if t.Latitude < -90 || t.Latitude > 90 {
		return ErrInvalidTelemetryLatitude
	}
	if t.Longitude < -180 || t.Longitude > 180 {
		return ErrInvalidTelemetryLongitude
	}
	if t.SpeedGPS < 0 {
		return ErrInvalidTelemetrySpeedGPS
	}
	if t.SpeedOBD < 0 {
		return ErrInvalidTelemetrySpeedOBD
	}
	if t.RPM < 0 {
		return ErrInvalidTelemetryRPM
	}
	if t.FuelLevel < 0 || t.FuelLevel > 100 {
		return ErrInvalidTelemetryFuelLevel
	}
	if strings.TrimSpace(t.Protocol) == "" {
		return ErrInvalidTelemetryProtocol
	}
	if strings.TrimSpace(t.VIN) == "" {
		return ErrInvalidTelemetryVIN
	}

	return nil
}
