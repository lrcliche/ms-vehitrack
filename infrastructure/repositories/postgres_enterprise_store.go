package repositories

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/infrastructure/database"
)

type PostgresEnterpriseStore struct{ pool *database.Pool }

func NewPostgresEnterpriseStore(pool *database.Pool) *PostgresEnterpriseStore {
	return &PostgresEnterpriseStore{pool: pool}
}

func (s *PostgresEnterpriseStore) DashboardKPIs(ctx context.Context, tenantID, actorID, tenantUserID string, from, to *time.Time) (*entities.EnterpriseDashboardKPIs, error) {
	raw, err := s.function(ctx, tenantID, `SELECT business.fnc_enterprise_dashboard_kpis($1::uuid,$2::uuid,$3::uuid,$4::date,$5::date)`, tenantID, actorID, tenantUserID, from, to)
	if err != nil {
		return nil, err
	}
	return decodeEnterprise[entities.EnterpriseDashboardKPIs](raw, "enterprise dashboard kpis")
}
func (s *PostgresEnterpriseStore) FinancialSummary(ctx context.Context, tenantID, actorID, tenantUserID, period string) (*entities.EnterpriseFinancialSummary, error) {
	raw, err := s.function(ctx, tenantID, `SELECT business.fnc_enterprise_financial_summary($1::uuid,$2::uuid,$3::uuid,$4)`, tenantID, actorID, tenantUserID, period)
	if err != nil {
		return nil, err
	}
	return decodeEnterprise[entities.EnterpriseFinancialSummary](raw, "enterprise financial summary")
}
func (s *PostgresEnterpriseStore) UpsertVehicle(ctx context.Context, tenantID, actorID, tenantUserID string, value entities.EnterpriseVehicleCommand) (*entities.EnterpriseVehicle, error) {
	payload, err := json.Marshal(map[string]any{"id": value.ID, "placa": value.Plate, "tipo": value.Type, "marca": value.Brand, "modelo": value.Model,
		"anio_modelo": value.ModelYear, "capacidad_pasajeros": value.PassengerCapacity, "rendimiento_km_gal": value.FuelEfficiencyKMPerGal,
		"costo_por_km": value.CostPerKMCOP, "costo_despacho": value.DispatchCostCOP, "estado": value.Status})
	if err != nil {
		return nil, fmt.Errorf("encode enterprise vehicle: %w", err)
	}
	raw, err := s.procedure(ctx, tenantID, `CALL business.prc_upsert_enterprise_vehicle($1::uuid,$2::uuid,$3::uuid,$4::jsonb,$5::jsonb)`, tenantID, actorID, tenantUserID, payload, nil)
	if err != nil {
		return nil, err
	}
	return decodeEnterprise[entities.EnterpriseVehicle](raw, "enterprise vehicle")
}
func (s *PostgresEnterpriseStore) ListVehicles(ctx context.Context, tenantID, actorID, tenantUserID string, filter entities.EnterpriseVehicleFilter) (*entities.EnterprisePage[entities.EnterpriseVehicle], error) {
	raw, err := s.function(ctx, tenantID, `SELECT business.fnc_list_enterprise_vehicles($1::uuid,$2::uuid,$3::uuid,$4,$5::integer,$6,$7::integer,$8::integer)`,
		tenantID, actorID, tenantUserID, nullableText(filter.Status), nullableInt(filter.MinimumCapacity), nullableText(filter.Search), filter.Page, filter.Limit)
	if err != nil {
		return nil, err
	}
	return decodeEnterprise[entities.EnterprisePage[entities.EnterpriseVehicle]](raw, "enterprise vehicles")
}
func (s *PostgresEnterpriseStore) UpdateVehicleStatus(ctx context.Context, tenantID, actorID, tenantUserID, id, status, reason string) (*entities.EnterpriseVehicle, error) {
	raw, err := s.procedure(ctx, tenantID, `CALL business.prc_update_enterprise_vehicle_status($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5,$6,$7::jsonb)`, tenantID, actorID, tenantUserID, id, status, reason, nil)
	if err != nil {
		return nil, err
	}
	return decodeEnterprise[entities.EnterpriseVehicle](raw, "enterprise vehicle status")
}
func (s *PostgresEnterpriseStore) UpsertDriver(ctx context.Context, tenantID, actorID, tenantUserID string, value entities.EnterpriseDriverCommand) (*entities.EnterpriseDriver, error) {
	var expires any
	if value.LicenseExpiresAt != nil {
		expires = value.LicenseExpiresAt.Format("2006-01-02")
	}
	payload, err := json.Marshal(map[string]any{"id": value.ID, "nombre_completo": value.FullName, "numero_identificacion": value.IdentificationNumber,
		"tenant_user_id": value.TenantUserID,
		"telefono":       value.Phone, "numero_licencia": value.LicenseNumber, "categoria_licencia": value.LicenseCategory,
		"vencimiento_licencia": expires, "viatico_diario": value.DailyAllowanceCOP, "estado": value.Status})
	if err != nil {
		return nil, fmt.Errorf("encode enterprise driver: %w", err)
	}
	raw, err := s.procedure(ctx, tenantID, `CALL business.prc_upsert_enterprise_driver($1::uuid,$2::uuid,$3::uuid,$4::jsonb,$5::jsonb)`, tenantID, actorID, tenantUserID, payload, nil)
	if err != nil {
		return nil, err
	}
	return decodeEnterprise[entities.EnterpriseDriver](raw, "enterprise driver")
}
func (s *PostgresEnterpriseStore) ListDrivers(ctx context.Context, tenantID, actorID, tenantUserID string, filter entities.EnterpriseDriverFilter) (*entities.EnterprisePage[entities.EnterpriseDriver], error) {
	raw, err := s.function(ctx, tenantID, `SELECT business.fnc_list_enterprise_drivers($1::uuid,$2::uuid,$3::uuid,$4,$5,$6::integer,$7::integer)`,
		tenantID, actorID, tenantUserID, nullableText(filter.Status), nullableText(filter.Search), filter.Page, filter.Limit)
	if err != nil {
		return nil, err
	}
	return decodeEnterprise[entities.EnterprisePage[entities.EnterpriseDriver]](raw, "enterprise drivers")
}
func (s *PostgresEnterpriseStore) UpdateDriverAvailability(ctx context.Context, tenantID, actorID, tenantUserID string, command entities.EnterpriseDriverAvailabilityCommand) (*entities.EnterpriseDriver, error) {
	raw, err := s.procedure(ctx, tenantID, `CALL business.prc_update_enterprise_driver_availability($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5,$6,$7::timestamptz,$8::timestamptz,$9::jsonb)`,
		tenantID, actorID, tenantUserID, command.DriverID, command.Status, command.Notes, command.StartsAt, command.EndsAt, nil)
	if err != nil {
		return nil, err
	}
	return decodeEnterprise[entities.EnterpriseDriver](raw, "enterprise driver availability")
}
func (s *PostgresEnterpriseStore) ListServiceRequests(ctx context.Context, tenantID, actorID, tenantUserID string, filter entities.EnterpriseServiceRequestFilter) (*entities.EnterprisePage[entities.EnterpriseServiceRequest], error) {
	raw, err := s.function(ctx, tenantID, `SELECT business.fnc_list_enterprise_requests($1::uuid,$2::uuid,$3::uuid,$4,$5::date,$6,$7::integer,$8::integer)`,
		tenantID, actorID, tenantUserID, nullableText(filter.Status), filter.Date, nullableText(filter.Customer), filter.Page, filter.Limit)
	if err != nil {
		return nil, err
	}
	return decodeEnterprise[entities.EnterprisePage[entities.EnterpriseServiceRequest]](raw, "enterprise service requests")
}
func (s *PostgresEnterpriseStore) ChangeServiceRequestStatus(ctx context.Context, tenantID, actorID, tenantUserID string, command entities.EnterpriseRequestStatusCommand) (*entities.EnterpriseServiceRequest, error) {
	raw, err := s.procedure(ctx, tenantID, `CALL business.prc_change_enterprise_request_status($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5,$6,$7::jsonb)`,
		tenantID, actorID, tenantUserID, command.RequestID, command.Status, command.Reason, nil)
	if err != nil {
		return nil, err
	}
	return decodeEnterprise[entities.EnterpriseServiceRequest](raw, "enterprise request status")
}
func (s *PostgresEnterpriseStore) CloseTripExpenses(ctx context.Context, tenantID, actorID, tenantUserID string, command entities.EnterpriseTripCloseCommand) (*entities.EnterpriseTripCloseResult, error) {
	raw, err := s.procedure(ctx, tenantID, `CALL business.prc_close_enterprise_trip_expenses($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::numeric,$6::numeric,$7::numeric,$8::numeric,$9::numeric,$10::numeric,$11,$12::jsonb)`,
		tenantID, actorID, tenantUserID, command.AssignmentID, command.ActualKM, command.FuelCOP, command.TollsCOP,
		command.MaintenanceCOP, command.DriverCOP, command.OtherCOP, command.Notes, nil)
	if err != nil {
		return nil, err
	}
	return decodeEnterprise[entities.EnterpriseTripCloseResult](raw, "enterprise trip close")
}
func (s *PostgresEnterpriseStore) ProfitabilityReport(ctx context.Context, tenantID, actorID, tenantUserID string, filter entities.EnterpriseProfitabilityFilter) (*entities.EnterpriseProfitabilityReport, error) {
	raw, err := s.function(ctx, tenantID, `SELECT business.fnc_enterprise_profitability_report($1::uuid,$2::uuid,$3::uuid,$4::date,$5::date,$6::uuid,$7::uuid,$8::integer,$9::integer)`,
		tenantID, actorID, tenantUserID, filter.From, filter.To, nullableText(filter.VehicleID), nullableText(filter.DriverID), filter.Page, filter.Limit)
	if err != nil {
		return nil, err
	}
	return decodeEnterprise[entities.EnterpriseProfitabilityReport](raw, "enterprise profitability report")
}

func (s *PostgresEnterpriseStore) function(ctx context.Context, tenantID, query string, args ...any) ([]byte, error) {
	var raw []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error { return tx.QueryRow(ctx, query, args...).Scan(&raw) })
	if err != nil {
		return nil, fmt.Errorf("enterprise database function: %w", err)
	}
	return raw, nil
}
func (s *PostgresEnterpriseStore) procedure(ctx context.Context, tenantID, query string, args ...any) ([]byte, error) {
	var raw []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error { return tx.QueryRow(ctx, query, args...).Scan(&raw) })
	if err != nil {
		return nil, fmt.Errorf("enterprise database procedure: %w", err)
	}
	return raw, nil
}
func decodeEnterprise[T any](raw []byte, operation string) (*T, error) {
	var value T
	if err := json.Unmarshal(raw, &value); err != nil {
		return nil, fmt.Errorf("decode %s result: %w", operation, err)
	}
	return &value, nil
}
func nullableText(value string) any {
	if value == "" {
		return nil
	}
	return value
}
func nullableInt(value int) any {
	if value < 1 {
		return nil
	}
	return value
}
