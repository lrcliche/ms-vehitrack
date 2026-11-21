package entities

import "time"

type CreateServiceRequestCommand struct {
	CustomerName         string
	OriginAddress        string
	OriginLatitude       float64
	OriginLongitude      float64
	DestinationAddress   string
	DestinationLatitude  float64
	DestinationLongitude float64
	ScheduledAt          time.Time
	PassengerCount       int
	AgreedFareCOP        float64
	Notes                string
}

type CreatedServiceRequest struct {
	ID                   string    `json:"id"`
	CustomerName         string    `json:"customer_name"`
	OriginAddress        string    `json:"origin_address"`
	OriginLatitude       float64   `json:"origin_latitude"`
	OriginLongitude      float64   `json:"origin_longitude"`
	DestinationAddress   string    `json:"destination_address"`
	DestinationLatitude  float64   `json:"destination_latitude"`
	DestinationLongitude float64   `json:"destination_longitude"`
	ScheduledAt          time.Time `json:"scheduled_at"`
	PassengerCount       int       `json:"passenger_count"`
	AgreedFareCOP        float64   `json:"agreed_fare_cop"`
	Status               string    `json:"status"`
}
