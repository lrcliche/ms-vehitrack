package ports

import (
	"context"
	"time"

	"ms-vehitrack/domain/entities"
)

type EnterpriseStore interface {
	DashboardKPIs(ctx context.Context, tenantID, actorUserID, tenantUserID string, from, to *time.Time) (*entities.EnterpriseDashboardKPIs, error)
	FinancialSummary(ctx context.Context, tenantID, actorUserID, tenantUserID, period string) (*entities.EnterpriseFinancialSummary, error)
	UpsertVehicle(ctx context.Context, tenantID, actorUserID, tenantUserID string, vehicle entities.EnterpriseVehicleCommand) (*entities.EnterpriseVehicle, error)
	ListVehicles(ctx context.Context, tenantID, actorUserID, tenantUserID string, filter entities.EnterpriseVehicleFilter) (*entities.EnterprisePage[entities.EnterpriseVehicle], error)
	UpdateVehicleStatus(ctx context.Context, tenantID, actorUserID, tenantUserID, vehicleID, status, reason string) (*entities.EnterpriseVehicle, error)
	UpsertDriver(ctx context.Context, tenantID, actorUserID, tenantUserID string, driver entities.EnterpriseDriverCommand) (*entities.EnterpriseDriver, error)
	ListDrivers(ctx context.Context, tenantID, actorUserID, tenantUserID string, filter entities.EnterpriseDriverFilter) (*entities.EnterprisePage[entities.EnterpriseDriver], error)
	UpdateDriverAvailability(ctx context.Context, tenantID, actorUserID, tenantUserID string, command entities.EnterpriseDriverAvailabilityCommand) (*entities.EnterpriseDriver, error)
	ListServiceRequests(ctx context.Context, tenantID, actorUserID, tenantUserID string, filter entities.EnterpriseServiceRequestFilter) (*entities.EnterprisePage[entities.EnterpriseServiceRequest], error)
	ChangeServiceRequestStatus(ctx context.Context, tenantID, actorUserID, tenantUserID string, command entities.EnterpriseRequestStatusCommand) (*entities.EnterpriseServiceRequest, error)
	CloseTripExpenses(ctx context.Context, tenantID, actorUserID, tenantUserID string, command entities.EnterpriseTripCloseCommand) (*entities.EnterpriseTripCloseResult, error)
	ListTrips(ctx context.Context, tenantID, actorUserID, tenantUserID string, filter entities.EnterpriseTripFilter) (*entities.EnterprisePage[entities.EnterpriseTrip], error)
	ProfitabilityReport(ctx context.Context, tenantID, actorUserID, tenantUserID string, filter entities.EnterpriseProfitabilityFilter) (*entities.EnterpriseProfitabilityReport, error)
}
