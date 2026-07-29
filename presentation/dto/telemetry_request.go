package dto

import (
	"time"

	"ms-vehitrack/domain/entities"
)

// TelemetryRequest is the HTTP transport contract for telemetry ingestion.
type TelemetryRequest struct {
	DeviceID    string    `json:"deviceId" binding:"required"`
	Timestamp   time.Time `json:"timestamp" binding:"required"`
	Latitude    *float64  `json:"latitude" binding:"required"`
	Longitude   *float64  `json:"longitude" binding:"required"`
	SpeedGPS    float64   `json:"speedGps"`
	SpeedOBD    float64   `json:"speedObd"`
	RPM         float64   `json:"rpm"`
	CoolantTemp float64   `json:"coolantTemp"`
	FuelLevel   float64   `json:"fuelLevel"`
	Protocol    string    `json:"protocol" binding:"required"`
	VIN         string    `json:"vin" binding:"required"`
}

// ToDomain maps the HTTP DTO into a domain Telemetry entity.
func (r TelemetryRequest) ToDomain() entities.Telemetry {
	var latitude, longitude float64
	if r.Latitude != nil {
		latitude = *r.Latitude
	}
	if r.Longitude != nil {
		longitude = *r.Longitude
	}

	return entities.Telemetry{
		DeviceID:    r.DeviceID,
		Timestamp:   r.Timestamp.UTC(),
		Latitude:    latitude,
		Longitude:   longitude,
		SpeedGPS:    r.SpeedGPS,
		SpeedOBD:    r.SpeedOBD,
		RPM:         r.RPM,
		CoolantTemp: r.CoolantTemp,
		FuelLevel:   r.FuelLevel,
		Protocol:    r.Protocol,
		VIN:         r.VIN,
	}
}
