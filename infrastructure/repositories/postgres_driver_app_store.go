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

type PostgresDriverAppStore struct{ pool *database.Pool }

func NewPostgresDriverAppStore(pool *database.Pool) *PostgresDriverAppStore {
	return &PostgresDriverAppStore{pool: pool}
}

func (s *PostgresDriverAppStore) Profile(ctx context.Context, tenantID, userID, tenantUserID string) (json.RawMessage, error) {
	return s.function(ctx, tenantID, `SELECT business.fnc_driver_me($1::uuid,$2::uuid,$3::uuid)`, tenantID, userID, tenantUserID)
}

func (s *PostgresDriverAppStore) Documents(ctx context.Context, tenantID, userID, tenantUserID, owner string) (json.RawMessage, error) {
	return s.function(ctx, tenantID, `SELECT business.fnc_driver_me_documents($1::uuid,$2::uuid,$3::uuid,$4)`, tenantID, userID, tenantUserID, owner)
}

func (s *PostgresDriverAppStore) DaySummary(ctx context.Context, tenantID, userID, tenantUserID, date string) (json.RawMessage, error) {
	return s.function(ctx, tenantID, `SELECT business.fnc_driver_me_day_summary($1::uuid,$2::uuid,$3::uuid,$4::date)`, tenantID, userID, tenantUserID, date)
}

func (s *PostgresDriverAppStore) Services(ctx context.Context, tenantID, userID, tenantUserID string) (json.RawMessage, error) {
	return s.function(ctx, tenantID, `SELECT business.fnc_driver_me_services($1::uuid,$2::uuid,$3::uuid)`, tenantID, userID, tenantUserID)
}

func (s *PostgresDriverAppStore) IngestTelemetry(ctx context.Context, tenantID, userID, tenantUserID, deviceID, batchID string, samples json.RawMessage, clientCreatedAt *time.Time) (json.RawMessage, error) {
	return s.function(ctx, tenantID, `SELECT business.fnc_driver_me_ingest_telemetry($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6::jsonb,$7::timestamptz)`,
		tenantID, userID, tenantUserID, deviceID, batchID, samples, clientCreatedAt)
}

func (s *PostgresDriverAppStore) StartService(ctx context.Context, tenantID, userID, tenantUserID, serviceID string) (json.RawMessage, error) {
	return s.function(ctx, tenantID, `SELECT business.fnc_driver_me_service_start($1::uuid,$2::uuid,$3::uuid,$4::uuid)`, tenantID, userID, tenantUserID, serviceID)
}

func (s *PostgresDriverAppStore) FinishService(ctx context.Context, tenantID, userID, tenantUserID, serviceID string) (json.RawMessage, error) {
	return s.function(ctx, tenantID, `SELECT business.fnc_driver_me_service_finish($1::uuid,$2::uuid,$3::uuid,$4::uuid)`, tenantID, userID, tenantUserID, serviceID)
}

func (s *PostgresDriverAppStore) DocumentFile(ctx context.Context, tenantID, userID, tenantUserID, owner, documentID string) (*entities.DriverAppDocumentFile, error) {
	raw, err := s.function(ctx, tenantID, `SELECT business.fnc_driver_me_document_file($1::uuid,$2::uuid,$3::uuid,$4,$5::uuid)`,
		tenantID, userID, tenantUserID, owner, documentID)
	if err != nil {
		return nil, err
	}
	var file entities.DriverAppDocumentFile
	if err := json.Unmarshal(raw, &file); err != nil {
		return nil, fmt.Errorf("decode driver document metadata: %w", err)
	}
	return &file, nil
}

func (s *PostgresDriverAppStore) function(ctx context.Context, tenantID, query string, args ...any) (json.RawMessage, error) {
	var raw []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, query, args...).Scan(&raw)
	})
	if err != nil {
		return nil, fmt.Errorf("driver app database function: %w", err)
	}
	return json.RawMessage(raw), nil
}
