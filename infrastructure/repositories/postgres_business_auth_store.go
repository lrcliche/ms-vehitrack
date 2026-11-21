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

type PostgresBusinessAuthStore struct {
	pool *database.Pool
}

func NewPostgresBusinessAuthStore(pool *database.Pool) *PostgresBusinessAuthStore {
	return &PostgresBusinessAuthStore{pool: pool}
}

func (s *PostgresBusinessAuthStore) FindActiveCredential(
	ctx context.Context, email, tenantID string,
) (*entities.BusinessUserCredential, error) {
	var credential entities.BusinessUserCredential
	err := s.pool.QueryRow(ctx, `
		SELECT u.id::text, tu.id::text, tu.tenant_id::text, u.email, u.password_hash
		FROM business."user" u
		JOIN business.tenant_user tu ON tu.user_id = u.id
		WHERE lower(u.email) = lower($1)
		  AND tu.tenant_id = $2::uuid
		  AND u.is_active
		  AND tu.is_active
		  AND u.password_hash IS NOT NULL`, email, tenantID).Scan(
		&credential.UserID, &credential.TenantUserID, &credential.TenantID,
		&credential.Email, &credential.PasswordHash,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("query active business credential: %w", err)
	}
	return &credential, nil
}

func (s *PostgresBusinessAuthStore) CreateUser(
	ctx context.Context, command entities.CreateBusinessUserCommand,
) (*entities.CreatedBusinessUser, error) {
	var raw []byte
	err := s.pool.WithTenantTx(ctx, command.TenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			CALL business.prc_create_user($1,$2,$3,$4,$5,$6,$7,$8)`,
			command.TenantID, command.ActorUserID, command.ActorTenantUserID,
			command.Email, command.FullName, command.PasswordHash, command.RoleCode, nil,
		).Scan(&raw)
	})
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) {
			switch {
			case pgErr.Code == "23505":
				return nil, entities.ErrBusinessEmailAlreadyExists
			case pgErr.Code == "VT070":
				return nil, entities.ErrBusinessUserForbidden
			case pgErr.Code == "VT072":
				return nil, entities.ErrBusinessUserForbidden
			case pgErr.Code == "VT071":
				return nil, entities.ErrBusinessRoleNotAssignable
			}
		}
		return nil, fmt.Errorf("create business user: %w", err)
	}
	var result struct {
		ID           string `json:"id"`
		TenantUserID string `json:"tenant_user_id"`
		RoleCode     string `json:"role_code"`
		Email        string `json:"email"`
		FullName     string `json:"full_name"`
	}
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil, fmt.Errorf("decode created business user: %w", err)
	}
	return &entities.CreatedBusinessUser{
		ID: result.ID, TenantUserID: result.TenantUserID, RoleCode: result.RoleCode,
		Email: result.Email, FullName: result.FullName,
	}, nil
}
