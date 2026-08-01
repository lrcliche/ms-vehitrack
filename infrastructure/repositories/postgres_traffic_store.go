package repositories

import (
	"context"
	"fmt"
	"time"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
	"ms-vehitrack/infrastructure/database"
)

// PostgresTrafficStore implements TrafficStorePort.
type PostgresTrafficStore struct {
	pool *database.Pool
}

func NewPostgresTrafficStore(pool *database.Pool) *PostgresTrafficStore {
	return &PostgresTrafficStore{pool: pool}
}

func (s *PostgresTrafficStore) IngestBatch(
	ctx context.Context,
	batch entities.TrafficBatch,
) (bool, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return false, fmt.Errorf("%w: begin: %v", ports.ErrTrafficStoreFailed, err)
	}
	defer tx.Rollback(ctx)

	var exists bool
	err = tx.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM traffic_batches WHERE batch_id = $1)`,
		batch.BatchID,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("%w: exists: %v", ports.ErrTrafficStoreFailed, err)
	}
	if exists {
		return true, tx.Commit(ctx)
	}

	_, err = tx.Exec(ctx,
		`INSERT INTO traffic_batches (batch_id, sample_count, duplicate) VALUES ($1, $2, false)`,
		batch.BatchID, len(batch.Samples),
	)
	if err != nil {
		return false, fmt.Errorf("%w: insert batch: %v", ports.ErrTrafficStoreFailed, err)
	}

	for _, sample := range batch.Samples {
		_, err = tx.Exec(ctx, `
			INSERT INTO traffic_samples (batch_id, cell, speed_kmh, sampled_at, accuracy_m, session_id)
			VALUES ($1, $2, $3, $4, $5, $6)`,
			batch.BatchID,
			sample.Cell,
			sample.SpeedKmh,
			sample.At.UTC(),
			nullIfZero(sample.AccuracyM),
			sample.SessionID,
		)
		if err != nil {
			return false, fmt.Errorf("%w: insert sample: %v", ports.ErrTrafficStoreFailed, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return false, fmt.Errorf("%w: commit: %v", ports.ErrTrafficStoreFailed, err)
	}
	return false, nil
}

func nullIfZero(v float64) any {
	if v <= 0 {
		return nil
	}
	return v
}

func (s *PostgresTrafficStore) RefreshAggregates(
	ctx context.Context,
	cells []string,
	lookbackMinutes int,
) error {
	if lookbackMinutes <= 0 {
		lookbackMinutes = 30
	}
	since := time.Now().UTC().Add(-time.Duration(lookbackMinutes) * time.Minute)

	// Recompute from samples in lookback. If cells empty → all touched recently.
	query := `
WITH recent AS (
  SELECT cell,
         (EXTRACT(HOUR FROM sampled_at)::int * 2 + CASE WHEN EXTRACT(MINUTE FROM sampled_at)::int >= 30 THEN 1 ELSE 0 END) AS slot,
         LEFT(cell, 5) AS corridor,
         speed_kmh,
         session_id
  FROM traffic_samples
  WHERE sampled_at >= $1
`
	args := []any{since}
	if len(cells) > 0 {
		query += ` AND cell = ANY($2)`
		args = append(args, cells)
	}
	query += `
),
agg AS (
  SELECT cell, slot, corridor,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY speed_kmh) AS median_speed_kmh,
         COUNT(*)::int AS sample_count,
         COUNT(DISTINCT session_id)::int AS device_count
  FROM recent
  GROUP BY cell, slot, corridor
)
INSERT INTO traffic_aggregates (cell, slot, corridor, median_speed_kmh, sample_count, device_count, updated_at)
SELECT cell, slot, corridor, median_speed_kmh, sample_count, device_count, now()
FROM agg
ON CONFLICT (cell, slot, corridor) DO UPDATE SET
  median_speed_kmh = EXCLUDED.median_speed_kmh,
  sample_count = EXCLUDED.sample_count,
  device_count = EXCLUDED.device_count,
  updated_at = now()
`
	_, err := s.pool.Exec(ctx, query, args...)
	if err != nil {
		return fmt.Errorf("%w: refresh: %v", ports.ErrTrafficStoreFailed, err)
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
		FROM traffic_aggregates
		WHERE corridor = $1 AND slot = $2
		ORDER BY sample_count DESC
		LIMIT 200`, corridor, slot)
	if err != nil {
		return nil, fmt.Errorf("%w: query: %v", ports.ErrTrafficStoreFailed, err)
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
