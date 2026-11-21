package ports

import (
	"context"

	"ms-vehitrack/domain/entities"
)

type AssignmentCandidateStore interface {
	FindAssignmentCandidates(ctx context.Context, tenantID, actorUserID, tenantUserID, serviceRequestID string) (*entities.AssignmentServiceRequest, []entities.AssignmentVehicle, error)
	ConfirmAssignment(ctx context.Context, tenantID, actorUserID, tenantUserID string, command entities.EnterpriseAssignmentCommand) (*entities.EnterpriseAssignmentResult, error)
}
