package ports

import (
	"context"

	"ms-vehitrack/domain/entities"
)

type BusinessAuthStore interface {
	FindActiveCredential(ctx context.Context, email, tenantID string) (*entities.BusinessUserCredential, error)
	CreateUser(ctx context.Context, command entities.CreateBusinessUserCommand) (*entities.CreatedBusinessUser, error)
}
