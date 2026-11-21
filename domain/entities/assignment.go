package entities

import "time"

type AssignmentServiceRequest struct {
	ID                   string    `json:"id"`
	Status               string    `json:"status"`
	OriginAddress        string    `json:"origin_address"`
	OriginLatitude       *float64  `json:"origin_latitude"`
	OriginLongitude      *float64  `json:"origin_longitude"`
	DestinationAddress   string    `json:"destination_address"`
	DestinationLatitude  *float64  `json:"destination_latitude"`
	DestinationLongitude *float64  `json:"destination_longitude"`
	ScheduledAt          time.Time `json:"scheduled_at"`
	PassengerCount       int       `json:"passenger_count"`
	AgreedFareCOP        float64   `json:"agreed_fare_cop"`
}

type AssignmentVehicle struct {
	ID                     string           `json:"id"`
	Plate                  string           `json:"plate"`
	VehicleTypeID          *string          `json:"vehicle_type_id"`
	Brand                  *string          `json:"brand"`
	Model                  *string          `json:"model"`
	ModelYear              *int             `json:"model_year"`
	PassengerCapacity      int              `json:"passenger_capacity"`
	OperationalStatus      string           `json:"operational_status"`
	CostPerKMCOP           float64          `json:"cost_per_km_cop"`
	DispatchCostCOP        float64          `json:"dispatch_cost_cop"`
	FuelEfficiencyKMGallon *float64         `json:"fuel_efficiency_km_per_gallon"`
	Driver                 AssignmentDriver `json:"driver"`
	CurrentLocation        *VehicleLocation `json:"current_location"`
}

type AssignmentDriver struct {
	ID                string  `json:"id"`
	FullName          string  `json:"full_name"`
	Phone             *string `json:"phone"`
	LicenseNumber     *string `json:"license_number"`
	LicenseCategory   *string `json:"license_category"`
	LicenseExpiresAt  *string `json:"license_expires_at"`
	DailyAllowanceCOP float64 `json:"daily_allowance_cop"`
	OperationalStatus string  `json:"operational_status"`
}

type VehicleLocation struct {
	Latitude   float64   `json:"latitude"`
	Longitude  float64   `json:"longitude"`
	RecordedAt time.Time `json:"recorded_at"`
}
