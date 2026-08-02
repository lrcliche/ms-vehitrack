// Package tracking orquesta la ingesta de telemetria por lote, los viajes (upsert/close) y las
// sesiones OBD (doc 03 §3). Todo el trabajo real vive en rutinas PG de tracking.*/device.*; el
// servicio valida entradas baratas (campos obligatorios) y delega en el store. La idempotencia,
// el last-write-wins y la geometria las fuerza la BD con SQLSTATE VT*.
package tracking

import (
	"context"
	"encoding/json"
	"time"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

// Service implementa los casos de uso de ingesta y viajes sobre el store PG.
type Service struct {
	store ports.TrackingStore
}

func NewService(store ports.TrackingStore) *Service {
	return &Service{store: store}
}

// IngestTelemetry = tracking.prc_ingest_telemetry. Idempotente por batchID. samples debe ser
// un array no vacio; la BD valida cada muestra y rechaza device inexistente/bloqueado (VT001/2).
func (s *Service) IngestTelemetry(
	ctx context.Context, tenantID, deviceID, batchID string,
	samples json.RawMessage, clientCreatedAt *time.Time,
) (json.RawMessage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	if batchID == "" {
		return nil, entities.ErrBatchIDRequired
	}
	if entities.IsEmptyJSON(samples) {
		return nil, entities.ErrSamplesRequired
	}
	return s.store.IngestTelemetry(ctx, tenantID, deviceID, batchID, samples, clientCreatedAt)
}

// UpsertTrip = tracking.prc_upsert_trip. status vacio -> 'active'. El id (uuid) lo trae la app.
func (s *Service) UpsertTrip(
	ctx context.Context, tenantID, deviceID, tripID string, in entities.TripUpsert,
) (json.RawMessage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	if tripID == "" {
		return nil, entities.ErrTripIDRequired
	}
	if in.Status == "" {
		in.Status = "active"
	}
	return s.store.UpsertTrip(ctx, tenantID, deviceID, tripID, in)
}

// CloseTrip = tracking.prc_close_trip. Materializa la traza; la BD exige >=2 puntos (VT027).
func (s *Service) CloseTrip(
	ctx context.Context, tenantID, tripID string,
) (json.RawMessage, error) {
	if tripID == "" {
		return nil, entities.ErrTripIDRequired
	}
	return s.store.CloseTrip(ctx, tenantID, tripID)
}

// UpsertObdSession = device.prc_upsert_obd_session. El session_id (uuid) lo trae la app.
func (s *Service) UpsertObdSession(
	ctx context.Context, tenantID, deviceID, sessionID string, in entities.ObdSessionUpsert,
) (json.RawMessage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	if sessionID == "" {
		return nil, entities.ErrSessionIDRequired
	}
	if in.Protocol == "" {
		return nil, entities.ErrProtocolRequired
	}
	return s.store.UpsertObdSession(ctx, tenantID, deviceID, sessionID, in)
}
