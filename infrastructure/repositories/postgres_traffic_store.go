package repositories

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
	"ms-vehitrack/infrastructure/database"
	"ms-vehitrack/infrastructure/stores"
)

// PostgresTrafficStore implements TrafficStorePort using schema routines
// (prc_ingest_telemetry / prc_rollup_live / fnc_aggregates_by_corridor).
// No DML directo contra tablas crudas.
type PostgresTrafficStore struct {
	pool     *database.Pool
	tenantID uuid.UUID
}

func NewPostgresTrafficStore(pool *database.Pool) *PostgresTrafficStore {
	return &PostgresTrafficStore{pool: pool, tenantID: stores.DefaultTenantID}
}

func (s *PostgresTrafficStore) IngestBatch(
	ctx context.Context,
	batch entities.TrafficBatch,
) (bool, error) {
	batchID, err := parseOrNewUUID(batch.BatchID)
	if err != nil {
		return false, fmt.Errorf("%w: batchId: %v", ports.ErrTrafficStoreFailed, err)
	}

	deviceKey := batch.BatchID
	if len(batch.Samples) > 0 && batch.Samples[0].SessionID != "" {
		deviceKey = batch.Samples[0].SessionID
	}
	deviceID := stores.StableDeviceUUID(deviceKey)

	samples, err := s.samplesToIngestJSON(ctx, batch.Samples)
	if err != nil {
		return false, err
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return false, fmt.Errorf("%w: begin: %v", ports.ErrTrafficStoreFailed, err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `SELECT set_config('app.tenant_id', $1, true)`, s.tenantID.String()); err != nil {
		return false, fmt.Errorf("%w: set tenant: %v", ports.ErrTrafficStoreFailed, err)
	}

	_, err = tx.Exec(ctx, `
		CALL device.prc_register_device(
			$1::uuid, $2::uuid, $3::text, 'android', NULL, NULL, NULL, NULL, NULL)`,
		deviceID, s.tenantID, deviceKey,
	)
	if err != nil {
		return false, fmt.Errorf("%w: register device: %v", ports.ErrTrafficStoreFailed, err)
	}

	var resultJSON []byte
	err = tx.QueryRow(ctx, `
		CALL tracking.prc_ingest_telemetry($1::uuid, $2::uuid, $3::jsonb, $4::timestamptz, NULL)`,
		deviceID, batchID, samples, time.Now().UTC(),
	).Scan(&resultJSON)
	if err != nil {
		_, execErr := tx.Exec(ctx, `
			CALL tracking.prc_ingest_telemetry($1::uuid, $2::uuid, $3::jsonb, $4::timestamptz, NULL)`,
			deviceID, batchID, samples, time.Now().UTC(),
		)
		if execErr != nil {
			return false, fmt.Errorf("%w: ingest: %v", ports.ErrTrafficStoreFailed, execErr)
		}
	}

	duplicate := false
	if len(resultJSON) > 0 {
		var parsed map[string]any
		if json.Unmarshal(resultJSON, &parsed) == nil {
			if d, ok := parsed["duplicate"].(bool); ok {
				duplicate = d
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return false, fmt.Errorf("%w: commit: %v", ports.ErrTrafficStoreFailed, err)
	}
	return duplicate, nil
}

// samplesToIngestJSON decodes geohash cell centers in SQL and builds the
// jsonb payload expected by tracking.prc_ingest_telemetry.
func (s *PostgresTrafficStore) samplesToIngestJSON(
	ctx context.Context,
	samples []entities.TrafficSample,
) ([]byte, error) {
	out := make([]map[string]any, 0, len(samples))
	for _, sample := range samples {
		var lat, lon float64
		err := s.pool.QueryRow(ctx, `
			SELECT ST_Y(ST_Centroid(ST_GeomFromGeoHash($1))),
			       ST_X(ST_Centroid(ST_GeomFromGeoHash($1)))`,
			sample.Cell,
		).Scan(&lat, &lon)
		if err != nil {
			return nil, fmt.Errorf("%w: geohash %s: %v", ports.ErrTrafficStoreFailed, sample.Cell, err)
		}
		row := map[string]any{
			"lat":           lat,
			"lon":           lon,
			"recorded_at":   sample.At.UTC().Format(time.RFC3339Nano),
			"speed_gps_kmh": sample.SpeedKmh,
			"accuracy_m":    nullIfNonPositive(sample.AccuracyM),
			"source":        "gps",
		}
		out = append(out, row)
	}
	b, err := json.Marshal(out)
	if err != nil {
		return nil, fmt.Errorf("%w: marshal: %v", ports.ErrTrafficStoreFailed, err)
	}
	return b, nil
}

func nullIfNonPositive(v float64) any {
	if v <= 0 {
		return nil
	}
	return v
}

func parseOrNewUUID(raw string) (uuid.UUID, error) {
	if u, err := uuid.Parse(raw); err == nil {
		return u, nil
	}
	// Batch ids from the app may be non-UUID strings; hash to uuid v5.
	return uuid.NewSHA1(uuid.NameSpaceOID, []byte(raw)), nil
}

func (s *PostgresTrafficStore) RefreshAggregates(
	ctx context.Context,
	_ []string,
	lookbackMinutes int,
) error {
	window := lookbackMinutes
	if window <= 0 {
		window = 30
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("%w: begin rollup: %v", ports.ErrTrafficStoreFailed, err)
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `CALL traffic.prc_rollup_live($1::int, NULL)`, window)
	if err != nil {
		return fmt.Errorf("%w: prc_rollup_live: %v", ports.ErrTrafficStoreFailed, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("%w: commit rollup: %v", ports.ErrTrafficStoreFailed, err)
	}
	return nil
}

func (s *PostgresTrafficStore) AggregatesByCorridor(
	ctx context.Context,
	corridor string,
	slot int,
) ([]entities.TrafficAggregate, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT cell, slot, corridor, median_speed_kmh, sample_count, device_count
		FROM traffic.fnc_aggregates_by_corridor($1, $2::smallint, NULL)`,
		corridor, slot,
	)
	if err != nil {
		return nil, fmt.Errorf("%w: fnc_aggregates_by_corridor: %v", ports.ErrTrafficStoreFailed, err)
	}
	defer rows.Close()

	out := make([]entities.TrafficAggregate, 0)
	for rows.Next() {
		var a entities.TrafficAggregate
		if err := rows.Scan(
			&a.Cell, &a.Slot, &a.Corridor,
			&a.MedianSpeedKmh, &a.SampleCount, &a.DeviceCount,
		); err != nil {
			return nil, fmt.Errorf("%w: scan: %v", ports.ErrTrafficStoreFailed, err)
		}
		out = append(out, a)
	}
	return out, rows.Err()
}
