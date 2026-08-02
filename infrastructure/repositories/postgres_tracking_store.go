package repositories

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/infrastructure/database"
)

// PostgresTrackingStore implementa ports.TrackingStore contra las rutinas de tracking.* y
// device.*. Todo es TENANT-SCOPED (RLS): cada metodo corre dentro de pool.WithTenantTx, que
// fija app.tenant_id con set_config(...,true) antes de la rutina. El tenantID lo resuelve el
// middleware TenantContext y llega por parametro; el store nunca lo inventa.
//
// Los errores se envuelven con %w sobre el error crudo para NO romper la cadena: asi
// presentationerrors.Map (errors.As) sigue viendo el *pgconn.PgError con SQLSTATE VT* (VT001,
// VT002, VT003, VT024, VT025, VT026, VT027) y lo traduce al HTTP correcto.
type PostgresTrackingStore struct {
	pool *database.Pool
}

func NewPostgresTrackingStore(pool *database.Pool) *PostgresTrackingStore {
	return &PostgresTrackingStore{pool: pool}
}

// IngestTelemetry = tracking.prc_ingest_telemetry (TENANT-SCOPED, INOUT p_result). Idempotente
// por batchID: reenviar el mismo lote devuelve {duplicate:true} sin reinsertar.
func (s *PostgresTrackingStore) IngestTelemetry(
	ctx context.Context, tenantID, deviceID, batchID string,
	samples json.RawMessage, clientCreatedAt *time.Time,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL tracking.prc_ingest_telemetry($1, $2, $3, $4, $5)`,
			deviceID, batchID, []byte(samples), clientCreatedAt, nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("tracking ingest_telemetry: %w", err)
	}
	return out, nil
}

// UpsertTrip = tracking.prc_upsert_trip (TENANT-SCOPED, INOUT p_result).
func (s *PostgresTrackingStore) UpsertTrip(
	ctx context.Context, tenantID, deviceID, tripID string, in entities.TripUpsert,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL tracking.prc_upsert_trip($1, $2, $3, $4, $5, $6, $7, $8)`,
			tripID, deviceID, in.StartedAt, in.EndedAt, in.Status,
			in.FuelLiters, in.CostCOP, nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("tracking upsert_trip: %w", err)
	}
	return out, nil
}

// CloseTrip = tracking.prc_close_trip (TENANT-SCOPED, INOUT p_result). Materializa la traza.
func (s *PostgresTrackingStore) CloseTrip(
	ctx context.Context, tenantID, tripID string,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL tracking.prc_close_trip($1, $2)`, tripID, nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("tracking close_trip: %w", err)
	}
	return out, nil
}

// UpsertObdSession = device.prc_upsert_obd_session (TENANT-SCOPED, INOUT p_result).
func (s *PostgresTrackingStore) UpsertObdSession(
	ctx context.Context, tenantID, deviceID, sessionID string, in entities.ObdSessionUpsert,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL device.prc_upsert_obd_session($1, $2, $3, $4, $5, $6, $7, $8)`,
			sessionID, deviceID, in.Protocol, in.TripID, in.AdapterName,
			in.StartedAt, in.EndedAt, nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("tracking upsert_obd_session: %w", err)
	}
	return out, nil
}
