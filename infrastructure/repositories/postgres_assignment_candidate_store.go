package repositories

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/infrastructure/database"
)

type PostgresAssignmentCandidateStore struct {
	pool *database.Pool
}

func NewPostgresAssignmentCandidateStore(pool *database.Pool) *PostgresAssignmentCandidateStore {
	return &PostgresAssignmentCandidateStore{pool: pool}
}

func (s *PostgresAssignmentCandidateStore) FindAssignmentCandidates(
	ctx context.Context, tenantID, actorUserID, tenantUserID, serviceRequestID string,
) (*entities.AssignmentServiceRequest, []entities.AssignmentVehicle, error) {
	var raw []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT business.fnc_get_assignment_candidates($1::uuid, $2::uuid, $3::uuid, $4::uuid)`,
			tenantID, actorUserID, tenantUserID, serviceRequestID,
		).Scan(&raw)
	})
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) {
			switch pgErr.Code {
			case "VT070":
				return nil, nil, entities.ErrAssignmentCandidatesForbidden
			case "VT073":
				return nil, nil, entities.ErrAssignmentRequestNotPending
			case "P0002":
				return nil, nil, entities.ErrAssignmentRequestNotFound
			}
		}
		return nil, nil, fmt.Errorf("find business assignment candidates: %w", err)
	}

	var result struct {
		ServiceRequest *entities.AssignmentServiceRequest `json:"service_request"`
		Candidates     []entities.AssignmentVehicle       `json:"candidates"`
	}
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil, nil, fmt.Errorf("decode business assignment candidates: %w", err)
	}
	if result.ServiceRequest == nil {
		return nil, nil, fmt.Errorf("decode business assignment candidates: service request missing")
	}
	return result.ServiceRequest, result.Candidates, nil
}
