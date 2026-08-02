package ports

import (
	"context"
	"encoding/json"
	"time"

	"ms-vehitrack/domain/entities"
)

// TrackingStore es el puerto de ingesta y viajes: envuelve las rutinas de tracking.* y
// device.* (doc 03 §3). El store NO hace DML crudo; cada metodo llama a un prc_.
//
// Todo es TENANT-SCOPED: tracking.position/ingest_batch/trip y device.obd_session llevan RLS,
// asi que cada metodo corre dentro de pool.WithTenantTx(tenantID) con el tenant resuelto por
// el middleware TenantContext. Los errores VT* se propagan con %w sobre el error crudo para
// que presentationerrors.Map vea el *pgconn.PgError.
type TrackingStore interface {
	// IngestTelemetry = tracking.prc_ingest_telemetry (INOUT p_result). Idempotente por batchID.
	IngestTelemetry(
		ctx context.Context, tenantID, deviceID, batchID string,
		samples json.RawMessage, clientCreatedAt *time.Time,
	) (json.RawMessage, error)
	// UpsertTrip = tracking.prc_upsert_trip (INOUT p_result).
	UpsertTrip(ctx context.Context, tenantID, deviceID, tripID string, in entities.TripUpsert) (json.RawMessage, error)
	// CloseTrip = tracking.prc_close_trip (INOUT p_result).
	CloseTrip(ctx context.Context, tenantID, tripID string) (json.RawMessage, error)
	// UpsertObdSession = device.prc_upsert_obd_session (INOUT p_result).
	UpsertObdSession(ctx context.Context, tenantID, deviceID, sessionID string, in entities.ObdSessionUpsert) (json.RawMessage, error)
}
