package ports

import (
	"context"

	"ms-vehitrack/domain/entities"
)

type ServiceRequestStore interface {
	CreateServiceRequest(ctx context.Context, tenantID, actorUserID, tenantUserID string,
		command entities.CreateServiceRequestCommand) (*entities.CreatedServiceRequest, error)
}
