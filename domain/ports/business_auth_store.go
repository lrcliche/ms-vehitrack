package ports

import (
	"context"
	"time"

	"ms-vehitrack/domain/entities"
)

type BusinessAuthStore interface {
	FindActiveCredential(ctx context.Context, email, tenantID string) (*entities.BusinessUserCredential, error)
	CreateUser(ctx context.Context, command entities.CreateBusinessUserCommand) (*entities.CreatedBusinessUser, error)
	CreateRefreshToken(ctx context.Context, userID, tenantUserID, tenantID, tokenHash, familyID string, expiresAt time.Time) error
	RotateRefreshToken(ctx context.Context, oldHash, newHash string, expiresAt time.Time) (*entities.BusinessUserCredential, error)
	RevokeRefreshToken(ctx context.Context, tokenHash string) error
	CreatePasswordResetToken(ctx context.Context, userID, tenantUserID, tenantID, tokenHash string, expiresAt time.Time) error
	ConsumePasswordResetToken(ctx context.Context, tenantID, tokenHash, passwordHash string) (bool, error)
}

type EmailMessage struct {
	To             string
	Subject        string
	Text           string
	HTML           string
	IdempotencyKey string
}

type EmailSender interface {
	Send(ctx context.Context, message EmailMessage) error
}
