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

type PostgresServiceRequestStore struct {
	pool *database.Pool
}

func NewPostgresServiceRequestStore(pool *database.Pool) *PostgresServiceRequestStore {
	return &PostgresServiceRequestStore{pool: pool}
}

func (s *PostgresServiceRequestStore) CreateServiceRequest(
	ctx context.Context, tenantID, actorUserID, tenantUserID string,
	command entities.CreateServiceRequestCommand,
) (*entities.CreatedServiceRequest, error) {
	var raw []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			CALL business.prc_create_service_request(
				$1::uuid,$2::uuid,$3::uuid,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`,
			tenantID, actorUserID, tenantUserID, command.CustomerName,
			command.OriginAddress, command.OriginLatitude, command.OriginLongitude,
			command.DestinationAddress, command.DestinationLatitude, command.DestinationLongitude,
			command.ScheduledAt, command.PassengerCount, command.AgreedFareCOP, command.Notes, nil,
		).Scan(&raw)
	})
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "VT070" {
			return nil, entities.ErrServiceRequestForbidden
		}
		return nil, fmt.Errorf("create enterprise service request: %w", err)
	}
	var request entities.CreatedServiceRequest
	if err := json.Unmarshal(raw, &request); err != nil {
		return nil, fmt.Errorf("decode created enterprise service request: %w", err)
	}
	if request.ID == "" {
		return nil, fmt.Errorf("decode created enterprise service request: id missing")
	}
	return &request, nil
}
