package stores

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
	"ms-vehitrack/infrastructure/database"
)

// DefaultTenantID is the seeded internal tenant from migrations/001_vehitrack.sql.
var DefaultTenantID = uuid.MustParse("00000000-0000-0000-0000-000000000001")

var _ ports.TelemetryStorePort = (*PostgresTelemetryStore)(nil)

// PostgresTelemetryStore persists telemetry via tracking.prc_ingest_telemetry
// (reemplaza el INSERT a BigQuery; sin DML directo desde Go).
type PostgresTelemetryStore struct {
	pool     *database.Pool
	tenantID uuid.UUID
}

// NewPostgresTelemetryStore creates a TelemetryStorePort backed by Postgres routines.
func NewPostgresTelemetryStore(pool *database.Pool) *PostgresTelemetryStore {
	return &PostgresTelemetryStore{pool: pool, tenantID: DefaultTenantID}
}

// Save maps one telemetry event into a single-sample ingest batch and CALLs
// tracking.prc_ingest_telemetry after ensuring the device exists.
func (s *PostgresTelemetryStore) Save(ctx context.Context, telemetry entities.Telemetry) error {
	deviceID := StableDeviceUUID(telemetry.DeviceID)
	batchID := uuid.New()

	if err := s.ensureDevice(ctx, deviceID, telemetry.DeviceID); err != nil {
		return err
	}

	sample := map[string]any{
		"lat":             telemetry.Latitude,
		"lon":             telemetry.Longitude,
		"recorded_at":     telemetry.Timestamp.UTC().Format(time.RFC3339Nano),
		"speed_gps_kmh":   telemetry.SpeedGPS,
		"speed_obd_kmh":   telemetry.SpeedOBD,
		"rpm":             telemetry.RPM,
		"coolant_temp_c":  telemetry.CoolantTemp,
		"fuel_level_pct":  telemetry.FuelLevel,
		"source":          "obd",
	}
	samplesJSON, err := json.Marshal([]map[string]any{sample})
	if err != nil {
		return fmt.Errorf("%w: marshal samples: %v", ports.ErrTelemetryStoreFailed, err)
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("%w: begin: %v", ports.ErrTelemetryStoreFailed, err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `SELECT set_config('app.tenant_id', $1, true)`, s.tenantID.String()); err != nil {
		return fmt.Errorf("%w: set tenant: %v", ports.ErrTelemetryStoreFailed, err)
	}

	var result []byte
	err = tx.QueryRow(ctx, `
		CALL tracking.prc_ingest_telemetry($1::uuid, $2::uuid, $3::jsonb, $4::timestamptz, NULL)`,
		deviceID, batchID, samplesJSON, time.Now().UTC(),
	).Scan(&result)
	// pgx CALL with INOUT: some drivers need different syntax.
	if err != nil {
		// Fallback: CALL without scanning INOUT (procedure still runs).
		_, execErr := tx.Exec(ctx, `
			CALL tracking.prc_ingest_telemetry($1::uuid, $2::uuid, $3::jsonb, $4::timestamptz, NULL)`,
			deviceID, batchID, samplesJSON, time.Now().UTC(),
		)
		if execErr != nil {
			return fmt.Errorf("%w: call ingest: %v (scan: %v)", ports.ErrTelemetryStoreFailed, execErr, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("%w: commit: %v", ports.ErrTelemetryStoreFailed, err)
	}
	return nil
}

func (s *PostgresTelemetryStore) ensureDevice(ctx context.Context, deviceID uuid.UUID, installID string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("%w: begin register: %v", ports.ErrTelemetryStoreFailed, err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `SELECT set_config('app.tenant_id', $1, true)`, s.tenantID.String()); err != nil {
		return fmt.Errorf("%w: set tenant: %v", ports.ErrTelemetryStoreFailed, err)
	}

	_, err = tx.Exec(ctx, `
		CALL device.prc_register_device(
			$1::uuid, $2::uuid, $3::text, 'android', NULL, NULL, NULL, NULL, NULL)`,
		deviceID, s.tenantID, installID,
	)
	if err != nil {
		return fmt.Errorf("%w: register device: %v", ports.ErrTelemetryStoreFailed, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("%w: commit register: %v", ports.ErrTelemetryStoreFailed, err)
	}
	return nil
}

// StableDeviceUUID maps a free-form device id (SSAID, etc.) to a stable UUID.
func StableDeviceUUID(raw string) uuid.UUID {
	if u, err := uuid.Parse(raw); err == nil {
		return u
	}
	return uuid.NewSHA1(uuid.NameSpaceOID, []byte(raw))
}
