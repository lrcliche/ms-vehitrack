package dto

import (
	"encoding/json"
	"time"
)

// TelemetryBatchRequest = POST /v1/telemetry/batch. samples es el array crudo que consume
// tracking.prc_ingest_telemetry [{lat,lon,recorded_at,speed_gps_kmh,...}]. batchId (uuid v7)
// da idempotencia: reenviar el mismo lote no reinserta.
type TelemetryBatchRequest struct {
	BatchID         string          `json:"batchId" binding:"required"`
	Samples         json.RawMessage `json:"samples" binding:"required"`
	ClientCreatedAt *time.Time      `json:"clientCreatedAt"`
}

// UpsertTripRequest = POST /v1/trips. El tripId (uuid v7) lo genera la app para crear sin
// conexion. status vacio -> 'active' lo pone el servicio.
type UpsertTripRequest struct {
	TripID     string     `json:"tripId" binding:"required"`
	StartedAt  *time.Time `json:"startedAt"`
	EndedAt    *time.Time `json:"endedAt"`
	Status     string     `json:"status"`
	FuelLiters *float64   `json:"fuelLiters"`
	CostCOP    *float64   `json:"costCop"`
}

// UpsertObdSessionRequest = POST /v1/obd/sessions. protocol se resuelve contra obd_protocol.
type UpsertObdSessionRequest struct {
	SessionID   string     `json:"sessionId" binding:"required"`
	Protocol    string     `json:"protocol" binding:"required"`
	TripID      *string    `json:"tripId"`
	AdapterName *string    `json:"adapterName"`
	StartedAt   *time.Time `json:"startedAt"`
	EndedAt     *time.Time `json:"endedAt"`
}
