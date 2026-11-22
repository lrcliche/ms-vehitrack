package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/application/businessauth"
	"ms-vehitrack/application/enterprise"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"
)

type EnterpriseServiceResolver interface {
	ResolveEnterpriseService() (*enterprise.Service, bool)
}
type EnterpriseOperationsHandler struct{ resolver EnterpriseServiceResolver }

func NewEnterpriseOperationsHandler(resolver EnterpriseServiceResolver) *EnterpriseOperationsHandler {
	return &EnterpriseOperationsHandler{resolver: resolver}
}

func (h *EnterpriseOperationsHandler) DashboardKPIs(c *gin.Context) {
	claims, svc, ok := h.context(c)
	if !ok {
		return
	}
	from, err := parseOptionalDate(c.Query("desde"))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("desde debe usar YYYY-MM-DD"))
		return
	}
	to, err := parseOptionalDate(c.Query("hasta"))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("hasta debe usar YYYY-MM-DD"))
		return
	}
	result, err := svc.DashboardKPIs(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, from, to)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, result)
}
func (h *EnterpriseOperationsHandler) FinancialSummary(c *gin.Context) {
	claims, svc, ok := h.context(c)
	if !ok {
		return
	}
	result, err := svc.FinancialSummary(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, c.Query("periodo"))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, result)
}
func (h *EnterpriseOperationsHandler) UpsertVehicle(c *gin.Context) {
	claims, svc, ok := h.context(c)
	if !ok {
		return
	}
	var req dto.EnterpriseVehicleRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.CostPerKMCOP == nil || req.DispatchCostCOP == nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid vehicle request"))
		return
	}
	id := ""
	if c.Request.Method == http.MethodPut {
		var uri dto.EnterpriseIDURI
		if err := c.ShouldBindUri(&uri); err != nil {
			responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid vehicle id"))
			return
		}
		id = uri.ID
	}
	status := req.Status
	if status == "" {
		status = "disponible"
	}
	value, err := svc.UpsertVehicle(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, entities.EnterpriseVehicleCommand{
		ID: id, Plate: req.Plate, Type: req.Type, Brand: req.Brand, Model: req.Model, ModelYear: req.ModelYear, PassengerCapacity: req.PassengerCapacity,
		FuelEfficiencyKMPerGal: req.FuelEfficiencyKMPerGal, CostPerKMCOP: *req.CostPerKMCOP, DispatchCostCOP: *req.DispatchCostCOP, Status: status})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	code := http.StatusCreated
	if id != "" {
		code = http.StatusOK
	}
	responses.Success(c, code, value)
}
func (h *EnterpriseOperationsHandler) ListVehicles(c *gin.Context) {
	claims, svc, ok := h.context(c)
	if !ok {
		return
	}
	capacity, err := queryInt(c, "capacidad_minima", 0)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("capacidad_minima debe ser un entero positivo"))
		return
	}
	page, err := queryInt(c, "pagina", 1)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("pagina debe ser un entero positivo"))
		return
	}
	limit, err := queryInt(c, "limite", 25)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("limite debe ser un entero positivo"))
		return
	}
	result, err := svc.ListVehicles(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, entities.EnterpriseVehicleFilter{Status: c.Query("estado"), MinimumCapacity: capacity, Search: c.Query("buscar"), Page: page, Limit: limit})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, result)
}
func (h *EnterpriseOperationsHandler) UpdateVehicleStatus(c *gin.Context) {
	claims, svc, ok := h.context(c)
	if !ok {
		return
	}
	var uri dto.EnterpriseIDURI
	var req dto.EnterpriseVehicleStatusRequest
	if c.ShouldBindUri(&uri) != nil || c.ShouldBindJSON(&req) != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid vehicle status request"))
		return
	}
	result, err := svc.UpdateVehicleStatus(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, uri.ID, req.Status, req.Reason)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, result)
}
func (h *EnterpriseOperationsHandler) UpsertDriver(c *gin.Context) {
	claims, svc, ok := h.context(c)
	if !ok {
		return
	}
	var req dto.EnterpriseDriverRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.DailyAllowanceCOP == nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid driver request"))
		return
	}
	id := ""
	if c.Request.Method == http.MethodPut {
		var uri dto.EnterpriseIDURI
		if c.ShouldBindUri(&uri) != nil {
			responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid driver id"))
			return
		}
		id = uri.ID
	}
	var expires *time.Time
	if req.LicenseExpiresAt != nil {
		parsed, err := time.Parse("2006-01-02", *req.LicenseExpiresAt)
		if err != nil {
			responses.ErrorFromApp(c, presentationerrors.BadRequest("vencimiento_licencia debe usar YYYY-MM-DD"))
			return
		}
		expires = &parsed
	}
	status := req.Status
	if status == "" {
		status = "disponible"
	}
	value, err := svc.UpsertDriver(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, entities.EnterpriseDriverCommand{
		ID: id, TenantUserID: req.TenantUserID, FullName: req.FullName, IdentificationNumber: req.IdentificationNumber, Phone: req.Phone, LicenseNumber: req.LicenseNumber,
		LicenseCategory: req.LicenseCategory, LicenseExpiresAt: expires, DailyAllowanceCOP: *req.DailyAllowanceCOP, Status: status})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	code := http.StatusCreated
	if id != "" {
		code = http.StatusOK
	}
	responses.Success(c, code, value)
}
func (h *EnterpriseOperationsHandler) ListDrivers(c *gin.Context) {
	claims, svc, ok := h.context(c)
	if !ok {
		return
	}
	page, err := queryInt(c, "pagina", 1)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("pagina debe ser un entero positivo"))
		return
	}
	limit, err := queryInt(c, "limite", 25)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("limite debe ser un entero positivo"))
		return
	}
	result, err := svc.ListDrivers(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, entities.EnterpriseDriverFilter{Status: c.Query("estado"), Search: c.Query("buscar"), Page: page, Limit: limit})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, result)
}
func (h *EnterpriseOperationsHandler) UpdateDriverAvailability(c *gin.Context) {
	claims, svc, ok := h.context(c)
	if !ok {
		return
	}
	var uri dto.EnterpriseIDURI
	var req dto.EnterpriseDriverAvailabilityRequest
	if c.ShouldBindUri(&uri) != nil || c.ShouldBindJSON(&req) != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid driver availability request"))
		return
	}
	var startsAt, endsAt *time.Time
	if req.StartsAt != nil {
		parsed, err := time.Parse(time.RFC3339, *req.StartsAt)
		if err != nil {
			responses.ErrorFromApp(c, presentationerrors.BadRequest("desde debe usar RFC3339"))
			return
		}
		startsAt = &parsed
	}
	if req.EndsAt != nil {
		parsed, err := time.Parse(time.RFC3339, *req.EndsAt)
		if err != nil {
			responses.ErrorFromApp(c, presentationerrors.BadRequest("hasta debe usar RFC3339"))
			return
		}
		endsAt = &parsed
	}
	result, err := svc.UpdateDriverAvailability(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID,
		entities.EnterpriseDriverAvailabilityCommand{DriverID: uri.ID, Status: req.Status, Notes: req.Notes, StartsAt: startsAt, EndsAt: endsAt})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, result)
}
func (h *EnterpriseOperationsHandler) ListServiceRequests(c *gin.Context) {
	claims, svc, ok := h.context(c)
	if !ok {
		return
	}
	page, err := queryInt(c, "pagina", 1)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("pagina debe ser un entero positivo"))
		return
	}
	limit, err := queryInt(c, "limite", 25)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("limite debe ser un entero positivo"))
		return
	}
	date, err := parseOptionalDate(c.Query("fecha"))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("fecha debe usar YYYY-MM-DD"))
		return
	}
	result, err := svc.ListServiceRequests(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, entities.EnterpriseServiceRequestFilter{Status: c.Query("estado"), Date: date, Customer: c.Query("cliente"), Page: page, Limit: limit})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, result)
}
func (h *EnterpriseOperationsHandler) ChangeServiceRequestStatus(c *gin.Context) {
	claims, svc, ok := h.context(c)
	if !ok {
		return
	}
	var uri dto.EnterpriseServiceRequestURI
	var req dto.EnterpriseRequestStatusRequest
	if c.ShouldBindUri(&uri) != nil || c.ShouldBindJSON(&req) != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid service request status"))
		return
	}
	result, err := svc.ChangeServiceRequestStatus(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, entities.EnterpriseRequestStatusCommand{RequestID: uri.ServiceRequestID, Status: req.Status, Reason: req.Reason})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, result)
}
func (h *EnterpriseOperationsHandler) CloseTripExpenses(c *gin.Context) {
	claims, svc, ok := h.context(c)
	if !ok {
		return
	}
	var uri dto.EnterpriseAssignmentURI
	var req dto.EnterpriseTripCloseRequest
	if c.ShouldBindUri(&uri) != nil || c.ShouldBindJSON(&req) != nil || req.ActualKM == nil || req.FuelCOP == nil || req.TollsCOP == nil || req.MaintenanceCOP == nil || req.DriverCOP == nil || req.OtherCOP == nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid trip expense close request"))
		return
	}
	result, err := svc.CloseTripExpenses(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, entities.EnterpriseTripCloseCommand{AssignmentID: uri.AssignmentID, ActualKM: *req.ActualKM, FuelCOP: *req.FuelCOP, TollsCOP: *req.TollsCOP, MaintenanceCOP: *req.MaintenanceCOP, DriverCOP: *req.DriverCOP, OtherCOP: *req.OtherCOP, Notes: req.Notes})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, result)
}
func (h *EnterpriseOperationsHandler) ProfitabilityReport(c *gin.Context) {
	claims, svc, ok := h.context(c)
	if !ok {
		return
	}
	from, err := parseOptionalDate(c.Query("desde"))
	if err != nil || from == nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("desde requerido en formato YYYY-MM-DD"))
		return
	}
	to, err := parseOptionalDate(c.Query("hasta"))
	if err != nil || to == nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("hasta requerido en formato YYYY-MM-DD"))
		return
	}
	page, err := queryInt(c, "pagina", 1)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("pagina debe ser un entero positivo"))
		return
	}
	limit, err := queryInt(c, "limite", 25)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("limite debe ser un entero positivo"))
		return
	}
	result, err := svc.ProfitabilityReport(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, entities.EnterpriseProfitabilityFilter{From: *from, To: *to, VehicleID: c.Query("vehiculo_id"), DriverID: c.Query("conductor_id"), Page: page, Limit: limit})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, result)
}
func (h *EnterpriseOperationsHandler) context(c *gin.Context) (*businessauth.TokenClaims, *enterprise.Service, bool) {
	claims, ok := middleware.BusinessClaimsFromContext(c)
	if !ok {
		responses.Error(c, http.StatusUnauthorized, "unauthorized", "valid business token required")
		return nil, nil, false
	}
	svc, ok := h.resolver.ResolveEnterpriseService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "enterprise-unavailable", "enterprise service is not configured")
		return nil, nil, false
	}
	return claims, svc, true
}
func parseOptionalDate(value string) (*time.Time, error) {
	if strings.TrimSpace(value) == "" {
		return nil, nil
	}
	parsed, err := time.Parse("2006-01-02", value)
	if err != nil {
		return nil, err
	}
	return &parsed, nil
}
func queryInt(c *gin.Context, key string, fallback int) (int, error) {
	value := c.Query(key)
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 1 {
		return 0, fmt.Errorf("invalid %s", key)
	}
	return parsed, nil
}
