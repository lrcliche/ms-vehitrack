package repositories

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

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

func (s *PostgresBusinessAuthStore) CreateRefreshToken(ctx context.Context, userID, tenantUserID, tenantID, tokenHash, familyID string, expiresAt time.Time) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO business.auth_refresh_token(user_id,tenant_user_id,tenant_id,token_hash,family_id,expires_at) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5::uuid,$6)`, userID, tenantUserID, tenantID, tokenHash, familyID, expiresAt)
	return err
}

func (s *PostgresBusinessAuthStore) RotateRefreshToken(ctx context.Context, oldHash, newHash string, expiresAt time.Time) (*entities.BusinessUserCredential, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	var id, userID, tenantUserID, tenantID, familyID string
	var tokenExpires time.Time
	var revokedAt *time.Time
	err = tx.QueryRow(ctx, `SELECT id::text,user_id::text,tenant_user_id::text,tenant_id::text,family_id::text,expires_at,revoked_at FROM business.auth_refresh_token WHERE token_hash=$1 FOR UPDATE`, oldHash).Scan(&id, &userID, &tenantUserID, &tenantID, &familyID, &tokenExpires, &revokedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if revokedAt != nil {
		if _, err = tx.Exec(ctx, `UPDATE business.auth_refresh_token SET revoked_at=COALESCE(revoked_at,now()) WHERE family_id=$1::uuid`, familyID); err != nil {
			return nil, err
		}
		return nil, tx.Commit(ctx)
	}
	if !tokenExpires.After(time.Now().UTC()) {
		_, err = tx.Exec(ctx, `UPDATE business.auth_refresh_token SET revoked_at=now() WHERE id=$1::uuid`, id)
		if err != nil {
			return nil, err
		}
		return nil, tx.Commit(ctx)
	}
	var credential entities.BusinessUserCredential
	err = tx.QueryRow(ctx, `SELECT u.id::text,tu.id::text,tu.tenant_id::text,u.email,u.password_hash FROM business."user" u JOIN business.tenant_user tu ON tu.user_id=u.id WHERE u.id=$1::uuid AND tu.id=$2::uuid AND tu.tenant_id=$3::uuid AND u.is_active AND tu.is_active AND u.password_hash IS NOT NULL`, userID, tenantUserID, tenantID).Scan(&credential.UserID, &credential.TenantUserID, &credential.TenantID, &credential.Email, &credential.PasswordHash)
	if errors.Is(err, pgx.ErrNoRows) {
		_, err = tx.Exec(ctx, `UPDATE business.auth_refresh_token SET revoked_at=now() WHERE family_id=$1::uuid`, familyID)
		if err != nil {
			return nil, err
		}
		return nil, tx.Commit(ctx)
	}
	if err != nil {
		return nil, err
	}
	if _, err = tx.Exec(ctx, `UPDATE business.auth_refresh_token SET revoked_at=now(),last_used_at=now() WHERE id=$1::uuid`, id); err != nil {
		return nil, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO business.auth_refresh_token(user_id,tenant_user_id,tenant_id,token_hash,family_id,expires_at) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5::uuid,$6)`, userID, tenantUserID, tenantID, newHash, familyID, expiresAt); err != nil {
		return nil, err
	}
	if err = tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &credential, nil
}

func (s *PostgresBusinessAuthStore) RevokeRefreshToken(ctx context.Context, tokenHash string) error {
	_, err := s.pool.Exec(ctx, `UPDATE business.auth_refresh_token SET revoked_at=COALESCE(revoked_at,now()) WHERE token_hash=$1`, tokenHash)
	return err
}

func (s *PostgresBusinessAuthStore) CreatePasswordResetToken(ctx context.Context, userID, tenantUserID, tenantID, tokenHash string, expiresAt time.Time) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var active bool
	err = tx.QueryRow(ctx, `SELECT is_active FROM business."user" WHERE id=$1::uuid FOR UPDATE`, userID).Scan(&active)
	if errors.Is(err, pgx.ErrNoRows) {
		return errors.New("password reset account is inactive")
	}
	if err != nil {
		return err
	}
	if !active {
		return errors.New("password reset account is inactive")
	}
	if _, err = tx.Exec(ctx, `UPDATE business.auth_password_reset_token SET consumed_at=COALESCE(consumed_at,now()) WHERE user_id=$1::uuid AND tenant_id=$2::uuid AND consumed_at IS NULL`, userID, tenantID); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO business.auth_password_reset_token(user_id,tenant_user_id,tenant_id,token_hash,expires_at) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5)`, userID, tenantUserID, tenantID, tokenHash, expiresAt); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *PostgresBusinessAuthStore) ConsumePasswordResetToken(ctx context.Context, tenantID, tokenHash, passwordHash string) (bool, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return false, err
	}
	defer tx.Rollback(ctx)
	var id, userID, tenantUserID string
	var expiresAt time.Time
	var consumedAt *time.Time
	err = tx.QueryRow(ctx, `SELECT id::text,user_id::text,tenant_user_id::text,expires_at,consumed_at FROM business.auth_password_reset_token WHERE tenant_id=$1::uuid AND token_hash=$2 FOR UPDATE`, tenantID, tokenHash).Scan(&id, &userID, &tenantUserID, &expiresAt, &consumedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if consumedAt != nil || !expiresAt.After(time.Now().UTC()) {
		return false, nil
	}
	var active bool
	err = tx.QueryRow(ctx, `SELECT u.is_active AND tu.is_active FROM business."user" u JOIN business.tenant_user tu ON tu.user_id=u.id WHERE u.id=$1::uuid AND tu.id=$2::uuid AND tu.tenant_id=$3::uuid FOR UPDATE OF u,tu`, userID, tenantUserID, tenantID).Scan(&active)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if !active {
		return false, nil
	}
	if _, err = tx.Exec(ctx, `UPDATE business."user" SET password_hash=$2,updated_at=now() WHERE id=$1::uuid`, userID, passwordHash); err != nil {
		return false, err
	}
	if _, err = tx.Exec(ctx, `UPDATE business.auth_password_reset_token SET consumed_at=now() WHERE user_id=$1::uuid AND consumed_at IS NULL`, userID); err != nil {
		return false, err
	}
	if _, err = tx.Exec(ctx, `UPDATE business.auth_refresh_token SET revoked_at=COALESCE(revoked_at,now()) WHERE user_id=$1::uuid`, userID); err != nil {
		return false, err
	}
	if err = tx.Commit(ctx); err != nil {
		return false, err
	}
	return true, nil
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
