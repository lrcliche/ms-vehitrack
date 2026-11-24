package enterprise

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

type Service struct{ store ports.EnterpriseStore }

func NewService(store ports.EnterpriseStore) *Service { return &Service{store: store} }

func (s *Service) DashboardKPIs(ctx context.Context, tenantID, actorID, tenantUserID string, from, to *time.Time) (*entities.EnterpriseDashboardKPIs, error) {
	if (from == nil) != (to == nil) || (from != nil && to.Before(*from)) {
		return nil, entities.ErrEnterpriseInvalid
	}
	return s.store.DashboardKPIs(ctx, tenantID, actorID, tenantUserID, from, to)
}
func (s *Service) FinancialSummary(ctx context.Context, tenantID, actorID, tenantUserID, period string) (*entities.EnterpriseFinancialSummary, error) {
	if period != "semana" && period != "mes" && period != "trimestre" {
		return nil, entities.ErrEnterpriseInvalid
	}
	return s.store.FinancialSummary(ctx, tenantID, actorID, tenantUserID, period)
}
func (s *Service) UpsertVehicle(ctx context.Context, tenantID, actorID, tenantUserID string, value entities.EnterpriseVehicleCommand) (*entities.EnterpriseVehicle, error) {
	value.Plate = strings.ToUpper(strings.TrimSpace(value.Plate))
	value.Type = strings.ToLower(strings.TrimSpace(value.Type))
	if value.Plate == "" || len(value.Plate) > 16 || value.Type == "" || value.PassengerCapacity < 1 || value.CostPerKMCOP < 0 || value.DispatchCostCOP < 0 ||
		(value.FuelEfficiencyKMPerGal != nil && *value.FuelEfficiencyKMPerGal <= 0) || (value.ModelYear != nil && (*value.ModelYear < 1900 || *value.ModelYear > 2200)) ||
		!oneOf(value.Status, "disponible", "mantenimiento", "inactivo") || (value.ID != "" && !validID(value.ID)) {
		return nil, entities.ErrEnterpriseInvalid
	}
	return s.store.UpsertVehicle(ctx, tenantID, actorID, tenantUserID, value)
}
func (s *Service) ListVehicles(ctx context.Context, tenantID, actorID, tenantUserID string, filter entities.EnterpriseVehicleFilter) (*entities.EnterprisePage[entities.EnterpriseVehicle], error) {
	filter.Status = strings.TrimSpace(filter.Status)
	if filter.Status != "" && !oneOf(filter.Status, "disponible", "en_servicio", "mantenimiento", "inactivo") {
		return nil, entities.ErrEnterpriseInvalid
	}
	if filter.MinimumCapacity < 0 {
		return nil, entities.ErrEnterpriseInvalid
	}
	pageDefaults(&filter.Page, &filter.Limit)
	return s.store.ListVehicles(ctx, tenantID, actorID, tenantUserID, filter)
}
func (s *Service) UpdateVehicleStatus(ctx context.Context, tenantID, actorID, tenantUserID, id, status, reason string) (*entities.EnterpriseVehicle, error) {
	if !validID(id) || !oneOf(status, "disponible", "mantenimiento", "inactivo") || len(reason) > 500 {
		return nil, entities.ErrEnterpriseInvalid
	}
	return s.store.UpdateVehicleStatus(ctx, tenantID, actorID, tenantUserID, id, status, strings.TrimSpace(reason))
}
func (s *Service) UpsertDriver(ctx context.Context, tenantID, actorID, tenantUserID string, value entities.EnterpriseDriverCommand) (*entities.EnterpriseDriver, error) {
	value.FullName = strings.TrimSpace(value.FullName)
	if value.TenantUserID != nil {
		id := strings.TrimSpace(*value.TenantUserID)
		if id == "" {
			value.TenantUserID = nil
		} else if !validID(id) {
			return nil, entities.ErrEnterpriseInvalid
		} else {
			value.TenantUserID = &id
		}
	}
	if value.FullName == "" || len(value.FullName) > 200 || value.DailyAllowanceCOP < 0 || (value.ID != "" && !validID(value.ID)) ||
		(value.Status != "" && !oneOf(value.Status, "disponible", "descanso", "inactivo")) {
		return nil, entities.ErrEnterpriseInvalid
	}
	return s.store.UpsertDriver(ctx, tenantID, actorID, tenantUserID, value)
}
func (s *Service) ListDrivers(ctx context.Context, tenantID, actorID, tenantUserID string, filter entities.EnterpriseDriverFilter) (*entities.EnterprisePage[entities.EnterpriseDriver], error) {
	filter.Status = strings.TrimSpace(filter.Status)
	if filter.Status != "" && !oneOf(filter.Status, "disponible", "asignado", "descanso", "inactivo") {
		return nil, entities.ErrEnterpriseInvalid
	}
	pageDefaults(&filter.Page, &filter.Limit)
	return s.store.ListDrivers(ctx, tenantID, actorID, tenantUserID, filter)
}
func (s *Service) UpdateDriverAvailability(ctx context.Context, tenantID, actorID, tenantUserID string, command entities.EnterpriseDriverAvailabilityCommand) (*entities.EnterpriseDriver, error) {
	if !validID(command.DriverID) || !oneOf(command.Status, "disponible", "descanso", "inactivo") || len(command.Notes) > 1000 ||
		(command.StartsAt == nil) != (command.EndsAt == nil) || (command.StartsAt != nil && !command.EndsAt.After(*command.StartsAt)) {
		return nil, entities.ErrEnterpriseInvalid
	}
	command.Notes = strings.TrimSpace(command.Notes)
	return s.store.UpdateDriverAvailability(ctx, tenantID, actorID, tenantUserID, command)
}
func (s *Service) ListServiceRequests(ctx context.Context, tenantID, actorID, tenantUserID string, filter entities.EnterpriseServiceRequestFilter) (*entities.EnterprisePage[entities.EnterpriseServiceRequest], error) {
	if filter.Status != "" && !oneOf(filter.Status, "pendiente", "asignada", "finalizada", "cancelada") {
		return nil, entities.ErrEnterpriseInvalid
	}
	pageDefaults(&filter.Page, &filter.Limit)
	return s.store.ListServiceRequests(ctx, tenantID, actorID, tenantUserID, filter)
}
func (s *Service) ChangeServiceRequestStatus(ctx context.Context, tenantID, actorID, tenantUserID string, command entities.EnterpriseRequestStatusCommand) (*entities.EnterpriseServiceRequest, error) {
	if !validID(command.RequestID) || !oneOf(command.Status, "cancelada", "finalizada") || len(command.Reason) > 1000 {
		return nil, entities.ErrEnterpriseInvalid
	}
	command.Reason = strings.TrimSpace(command.Reason)
	return s.store.ChangeServiceRequestStatus(ctx, tenantID, actorID, tenantUserID, command)
}
func (s *Service) CloseTripExpenses(ctx context.Context, tenantID, actorID, tenantUserID string, command entities.EnterpriseTripCloseCommand) (*entities.EnterpriseTripCloseResult, error) {
	if !validID(command.AssignmentID) || command.ActualKM < 0 || command.FuelCOP < 0 || command.TollsCOP < 0 || command.MaintenanceCOP < 0 || command.DriverCOP < 0 || command.OtherCOP < 0 || len(command.Notes) > 2000 {
		return nil, entities.ErrEnterpriseInvalid
	}
	return s.store.CloseTripExpenses(ctx, tenantID, actorID, tenantUserID, command)
}
func (s *Service) ListTrips(ctx context.Context, tenantID, actorID, tenantUserID string, filter entities.EnterpriseTripFilter) (*entities.EnterprisePage[entities.EnterpriseTrip], error) {
	if (filter.From == nil) != (filter.To == nil) || (filter.From != nil && filter.To.Before(*filter.From)) ||
		(filter.Status != "" && !oneOf(filter.Status, "en_curso", "finalizado")) {
		return nil, entities.ErrEnterpriseInvalid
	}
	pageDefaults(&filter.Page, &filter.Limit)
	return s.store.ListTrips(ctx, tenantID, actorID, tenantUserID, filter)
}
func (s *Service) ProfitabilityReport(ctx context.Context, tenantID, actorID, tenantUserID string, filter entities.EnterpriseProfitabilityFilter) (*entities.EnterpriseProfitabilityReport, error) {
	if filter.From.IsZero() || filter.To.IsZero() || filter.To.Before(filter.From) || (filter.VehicleID != "" && !validID(filter.VehicleID)) || (filter.DriverID != "" && !validID(filter.DriverID)) {
		return nil, entities.ErrEnterpriseInvalid
	}
	pageDefaults(&filter.Page, &filter.Limit)
	return s.store.ProfitabilityReport(ctx, tenantID, actorID, tenantUserID, filter)
}

func validID(value string) bool { _, err := uuid.Parse(value); return err == nil }
func oneOf(value string, allowed ...string) bool {
	for _, item := range allowed {
		if value == item {
			return true
		}
	}
	return false
}
func pageDefaults(page, limit *int) {
	if *page < 1 {
		*page = 1
	}
	if *limit < 1 {
		*limit = 25
	}
	if *limit > 100 {
		*limit = 100
	}
}
