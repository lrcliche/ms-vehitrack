package ports

import (
	"context"
	"encoding/json"
	"time"

	"ms-vehitrack/domain/entities"
)

type DriverAppStore interface {
	Profile(ctx context.Context, tenantID, actorUserID, actorTenantUserID string) (json.RawMessage, error)
	Documents(ctx context.Context, tenantID, actorUserID, actorTenantUserID, owner string) (json.RawMessage, error)
	DaySummary(ctx context.Context, tenantID, actorUserID, actorTenantUserID string, date string) (json.RawMessage, error)
	Services(ctx context.Context, tenantID, actorUserID, actorTenantUserID string) (json.RawMessage, error)
	IngestTelemetry(ctx context.Context, tenantID, actorUserID, actorTenantUserID, deviceID, batchID string, samples json.RawMessage, clientCreatedAt *time.Time) (json.RawMessage, error)
	StartService(ctx context.Context, tenantID, actorUserID, actorTenantUserID, serviceID string) (json.RawMessage, error)
	FinishService(ctx context.Context, tenantID, actorUserID, actorTenantUserID, serviceID string) (json.RawMessage, error)
	DocumentFile(ctx context.Context, tenantID, actorUserID, actorTenantUserID, owner, documentID string) (*entities.DriverAppDocumentFile, error)
}
