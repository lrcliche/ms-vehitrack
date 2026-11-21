package dto

import "time"

type DriverLocationRequest struct {
	Latitude   *float64  `json:"lat" binding:"required"`
	Longitude  *float64  `json:"lon" binding:"required"`
	AccuracyM  *float64  `json:"accuracy_m" binding:"omitempty,gte=0,lte=1000"`
	RecordedAt time.Time `json:"recorded_at" binding:"required"`
}
