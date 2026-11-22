package dto

type EnterpriseIDURI struct {
	ID string `uri:"id" binding:"required,uuid"`
}
type EnterpriseAssignmentURI struct {
	AssignmentID string `uri:"assignmentID" binding:"required,uuid"`
}
type EnterpriseServiceRequestURI struct {
	ServiceRequestID string `uri:"serviceRequestID" binding:"required,uuid"`
}

type EnterpriseVehicleRequest struct {
	Plate                  string   `json:"placa" binding:"required,max=16"`
	Type                   string   `json:"tipo" binding:"required,max=80"`
	Brand                  *string  `json:"marca" binding:"omitempty,max=100"`
	Model                  *string  `json:"modelo" binding:"omitempty,max=100"`
	ModelYear              *int     `json:"anio_modelo" binding:"omitempty,min=1900,max=2200"`
	PassengerCapacity      int      `json:"capacidad_pasajeros" binding:"required,min=1"`
	FuelEfficiencyKMPerGal *float64 `json:"rendimiento_km_gal" binding:"omitempty,gt=0"`
	CostPerKMCOP           *float64 `json:"costo_por_km" binding:"required,gte=0"`
	DispatchCostCOP        *float64 `json:"costo_despacho" binding:"required,gte=0"`
	Status                 string   `json:"estado" binding:"omitempty,oneof=disponible mantenimiento inactivo"`
}
type EnterpriseVehicleStatusRequest struct {
	Status string `json:"estado" binding:"required,oneof=disponible mantenimiento inactivo"`
	Reason string `json:"motivo" binding:"omitempty,max=500"`
}
type EnterpriseDriverRequest struct {
	TenantUserID         *string  `json:"tenant_user_id" binding:"omitempty,uuid"`
	FullName             string   `json:"nombre_completo" binding:"required,min=1,max=200"`
	IdentificationNumber *string  `json:"numero_identificacion" binding:"omitempty,max=50"`
	Phone                *string  `json:"telefono" binding:"omitempty,max=40"`
	LicenseNumber        *string  `json:"numero_licencia" binding:"omitempty,max=60"`
	LicenseCategory      *string  `json:"categoria_licencia" binding:"omitempty,max=20"`
	LicenseExpiresAt     *string  `json:"vencimiento_licencia" binding:"omitempty,datetime=2006-01-02"`
	DailyAllowanceCOP    *float64 `json:"viatico_diario" binding:"required,gte=0"`
	Status               string   `json:"estado" binding:"omitempty,oneof=disponible descanso inactivo"`
}
type EnterpriseDriverAvailabilityRequest struct {
	Status   string  `json:"estado" binding:"required,oneof=disponible descanso inactivo"`
	Notes    string  `json:"observaciones" binding:"omitempty,max=1000"`
	StartsAt *string `json:"desde"`
	EndsAt   *string `json:"hasta"`
}
type EnterpriseRequestStatusRequest struct {
	Status string `json:"estado" binding:"required,oneof=cancelada finalizada"`
	Reason string `json:"motivo_cancelacion" binding:"omitempty,max=1000"`
}
type EnterpriseAssignmentRequest struct {
	ServiceRequestID string `json:"solicitud_id" binding:"required,uuid"`
	VehicleID        string `json:"vehiculo_id" binding:"required,uuid"`
	DriverID         string `json:"conductor_id" binding:"required,uuid"`
	SelectionReason  string `json:"motivo_seleccion" binding:"omitempty,max=1000"`
}
type EnterpriseTripCloseRequest struct {
	ActualKM       *float64 `json:"km_reales" binding:"required,gte=0"`
	FuelCOP        *float64 `json:"costo_combustible" binding:"required,gte=0"`
	TollsCOP       *float64 `json:"costo_peajes" binding:"required,gte=0"`
	MaintenanceCOP *float64 `json:"costo_mantenimiento" binding:"required,gte=0"`
	DriverCOP      *float64 `json:"costo_conductor" binding:"required,gte=0"`
	OtherCOP       *float64 `json:"otros_gastos" binding:"required,gte=0"`
	Notes          string   `json:"observaciones" binding:"omitempty,max=2000"`
}
