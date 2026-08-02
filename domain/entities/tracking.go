package entities

import (
	"errors"
	"time"
)

// TripUpsert son los campos de tracking.prc_upsert_trip. El id (uuid v7) lo genera la app para
// crear sin conexion y viaja aparte. status vacio -> 'active' lo pone el servicio.
type TripUpsert struct {
	StartedAt  *time.Time
	EndedAt    *time.Time
	Status     string
	FuelLiters *float64
	CostCOP    *float64
}

// ObdSessionUpsert son los campos de device.prc_upsert_obd_session. El session_id (uuid) lo
// genera la app. protocol se resuelve contra public.obd_protocol (desconocido -> 'unknown').
type ObdSessionUpsert struct {
	Protocol    string
	TripID      *string
	AdapterName *string
	StartedAt   *time.Time
	EndedAt     *time.Time
}

var (
	// ErrBatchIDRequired = falta batch_id en POST /telemetry/batch (idempotencia).
	ErrBatchIDRequired = errors.New("tracking: batchId requerido")
	// ErrSamplesRequired = falta el array de muestras en el lote.
	ErrSamplesRequired = errors.New("tracking: samples requeridos")
	// ErrTripIDRequired = falta el trip_id (upsert/close).
	ErrTripIDRequired = errors.New("tracking: tripId requerido")
	// ErrSessionIDRequired = falta el session_id de la sesion OBD.
	ErrSessionIDRequired = errors.New("tracking: sessionId requerido")
	// ErrProtocolRequired = falta el protocolo OBD.
	ErrProtocolRequired = errors.New("tracking: protocol requerido")
)
