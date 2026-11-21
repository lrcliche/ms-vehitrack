package entities

import (
	"errors"
	"time"
)

var (
	ErrEnterpriseForbidden = errors.New("enterprise: permission denied")
	ErrEnterpriseInvalid   = errors.New("enterprise: invalid input")
)

type EnterpriseDashboardKPIs struct {
	VehiclesTotal       int `json:"vehiculos_total"`
	VehiclesAvailable   int `json:"vehiculos_disponibles"`
	VehiclesInService   int `json:"vehiculos_en_servicio"`
	PendingRequests     int `json:"solicitudes_pendientes"`
	CompletedExecutions int `json:"recorridos_finalizados"`
}

type EnterpriseFinancialSummary struct {
	TotalIncomeCOP     float64 `json:"ingreso_total"`
	EstimatedCostCOP   float64 `json:"costo_estimado"`
	ActualCostCOP      float64 `json:"costo_real"`
	EstimatedMarginCOP float64 `json:"margen_estimado"`
	ActualMarginCOP    float64 `json:"margen_real"`
}

type EnterprisePage[T any] struct {
	Items []T `json:"elementos"`
	Total int `json:"total"`
	Page  int `json:"pagina"`
	Limit int `json:"limite"`
}

type EnterpriseVehicle struct {
	ID                     string    `json:"id"`
	Plate                  string    `json:"placa"`
	Type                   string    `json:"tipo"`
	Brand                  *string   `json:"marca,omitempty"`
	Model                  *string   `json:"modelo,omitempty"`
	ModelYear              *int      `json:"anio_modelo,omitempty"`
	PassengerCapacity      int       `json:"capacidad_pasajeros"`
	FuelEfficiencyKMPerGal *float64  `json:"rendimiento_km_gal,omitempty"`
	CostPerKMCOP           float64   `json:"costo_por_km"`
	DispatchCostCOP        float64   `json:"costo_despacho"`
	Status                 string    `json:"estado"`
	CreatedAt              time.Time `json:"fecha_creacion"`
}

type EnterpriseVehicleCommand struct {
	ID                     string
	Plate                  string
	Type                   string
	Brand                  *string
	Model                  *string
	ModelYear              *int
	PassengerCapacity      int
	FuelEfficiencyKMPerGal *float64
	CostPerKMCOP           float64
	DispatchCostCOP        float64
	Status                 string
}

type EnterpriseVehicleFilter struct {
	Status          string
	MinimumCapacity int
	Search          string
	Page            int
	Limit           int
}

type EnterpriseDriver struct {
	ID                   string                              `json:"id"`
	FullName             string                              `json:"nombre_completo"`
	IdentificationNumber *string                             `json:"numero_identificacion,omitempty"`
	Phone                *string                             `json:"telefono,omitempty"`
	LicenseNumber        *string                             `json:"numero_licencia,omitempty"`
	LicenseCategory      *string                             `json:"categoria_licencia,omitempty"`
	LicenseExpiresAt     *string                             `json:"vencimiento_licencia,omitempty"`
	DailyAllowanceCOP    float64                             `json:"viatico_diario"`
	Status               string                              `json:"estado"`
	LicenseCurrent       bool                                `json:"licencia_vigente"`
	CreatedAt            time.Time                           `json:"fecha_creacion"`
	Schedule             *EnterpriseDriverAvailabilityWindow `json:"turno,omitempty"`
}

type EnterpriseDriverCommand struct {
	ID                   string
	FullName             string
	IdentificationNumber *string
	Phone                *string
	LicenseNumber        *string
	LicenseCategory      *string
	LicenseExpiresAt     *time.Time
	DailyAllowanceCOP    float64
	Status               string
}

type EnterpriseDriverFilter struct {
	Status string
	Search string
	Page   int
	Limit  int
}

type EnterpriseDriverAvailabilityCommand struct {
	DriverID string
	Status   string
	Notes    string
	StartsAt *time.Time
	EndsAt   *time.Time
}

type EnterpriseDriverAvailabilityWindow struct {
	StartsAt time.Time `json:"desde"`
	EndsAt   time.Time `json:"hasta"`
	Status   string    `json:"estado"`
}

type EnterpriseServiceRequestFilter struct {
	Status   string
	Date     *time.Time
	Customer string
	Page     int
	Limit    int
}

type EnterpriseServiceRequest struct {
	ID                   string    `json:"id"`
	CustomerName         string    `json:"nombre_cliente"`
	OriginAddress        string    `json:"origen_direccion"`
	OriginLatitude       *float64  `json:"origen_lat"`
	OriginLongitude      *float64  `json:"origen_lng"`
	DestinationAddress   string    `json:"destino_direccion"`
	DestinationLatitude  *float64  `json:"destino_lat"`
	DestinationLongitude *float64  `json:"destino_lng"`
	ScheduledAt          time.Time `json:"fecha_servicio"`
	Passengers           int       `json:"pasajeros"`
	AgreedFareCOP        float64   `json:"tarifa_pactada"`
	Status               string    `json:"estado"`
}

type EnterpriseRequestStatusCommand struct {
	RequestID string
	Status    string
	Reason    string
}

type EnterpriseAssignmentCommand struct {
	RequestID          string
	VehicleID          string
	DriverID           string
	Reason             string
	EmptyKM            float64
	ServiceKM          float64
	EstimatedDurationS float64
}

type EnterpriseAssignmentResult struct {
	AssignmentID     string  `json:"asignacion_id"`
	Status           string  `json:"estado"`
	EstimatedCostCOP float64 `json:"costo_estimado"`
	VehicleStatus    string  `json:"estado_vehiculo"`
	DriverStatus     string  `json:"estado_conductor"`
}

type EnterpriseTripCloseCommand struct {
	AssignmentID   string
	ActualKM       float64
	FuelCOP        float64
	TollsCOP       float64
	MaintenanceCOP float64
	DriverCOP      float64
	OtherCOP       float64
	Notes          string
}

type EnterpriseTripCloseResult struct {
	ExecutionID            string  `json:"recorrido_id"`
	AgreedFareCOP          float64 `json:"tarifa_pactada"`
	EstimatedCostCOP       float64 `json:"costo_estimado"`
	ActualCostCOP          float64 `json:"costo_real"`
	CostDeviationCOP       float64 `json:"desviacion_costos"`
	ActualMarginCOP        float64 `json:"margen_real"`
	ActualMarginPercentage float64 `json:"porcentaje_margen_real"`
}

type EnterpriseProfitabilityFilter struct {
	From      time.Time
	To        time.Time
	VehicleID string
	DriverID  string
	Page      int
	Limit     int
}

type EnterpriseProfitabilitySummary struct {
	TotalFareCOP       float64 `json:"tarifa_total"`
	EstimatedCostCOP   float64 `json:"costo_estimado_total"`
	ActualCostCOP      float64 `json:"costo_real_total"`
	CostDeviationCOP   float64 `json:"desviacion"`
	EstimatedMarginCOP float64 `json:"margen_estimado_total"`
	ActualMarginCOP    float64 `json:"margen_real_total"`
}

type EnterpriseProfitabilityItem struct {
	RequestID          string    `json:"solicitud_id"`
	VehicleID          string    `json:"vehiculo_id"`
	Plate              string    `json:"placa"`
	DriverID           string    `json:"conductor_id"`
	DriverName         string    `json:"conductor"`
	AgreedFareCOP      float64   `json:"tarifa_pactada"`
	EstimatedCostCOP   float64   `json:"costo_estimado"`
	ActualCostCOP      float64   `json:"costo_real"`
	CostDeviationCOP   float64   `json:"desviacion_costos"`
	EstimatedMarginCOP float64   `json:"margen_estimado"`
	ActualMarginCOP    float64   `json:"margen_real"`
	ClosedAt           time.Time `json:"fecha_cierre"`
}

type EnterpriseProfitabilityReport struct {
	Summary EnterpriseProfitabilitySummary `json:"resumen"`
	Trips   []EnterpriseProfitabilityItem  `json:"recorridos"`
	Total   int                            `json:"total"`
	Page    int                            `json:"pagina"`
	Limit   int                            `json:"limite"`
}
