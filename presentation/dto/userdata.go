package dto

import (
	"encoding/json"
	"time"
)

// UpsertFavoriteRequest = PUT /v1/favorites/:id. El id va en la URL (uuid v7 de la app), no
// en el body. kind vacio -> 'custom' lo pone el servicio.
type UpsertFavoriteRequest struct {
	Label           string     `json:"label" binding:"required"`
	Lat             float64    `json:"lat"`
	Lon             float64    `json:"lon"`
	Kind            string     `json:"kind"`
	Description     *string    `json:"description"`
	Icon            *string    `json:"icon"`
	ColorHex        *string    `json:"colorHex"`
	PlaceID         *int64     `json:"placeId"`
	ClientUpdatedAt *time.Time `json:"clientUpdatedAt"`
}

// UpsertPlaceRequest = PUT /v1/places/:id. POI propio del usuario.
type UpsertPlaceRequest struct {
	Name            string     `json:"name" binding:"required"`
	Lat             float64    `json:"lat"`
	Lon             float64    `json:"lon"`
	CategoryID      string     `json:"categoryId"`
	Description     *string    `json:"description"`
	ClientUpdatedAt *time.Time `json:"clientUpdatedAt"`
}

// UpsertGeofenceRequest = PUT /v1/geofences/:id. geomWkt = punto (circle) o poligono (WKT).
type UpsertGeofenceRequest struct {
	Name            string     `json:"name" binding:"required"`
	GeomWKT         string     `json:"geomWkt" binding:"required"`
	Shape           string     `json:"shape"`
	RadiusM         *int       `json:"radiusM"`
	Trigger         string     `json:"trigger"`
	CooldownS       *int       `json:"cooldownS"`
	IsActive        *bool      `json:"isActive"`
	ClientUpdatedAt *time.Time `json:"clientUpdatedAt"`
}

// GeofenceEventRequest = POST /v1/geofences/events. Evento evaluado por la app.
type GeofenceEventRequest struct {
	GeofenceID string    `json:"geofenceId" binding:"required"`
	Trigger    string    `json:"trigger" binding:"required"`
	Lat        float64   `json:"lat"`
	Lon        float64   `json:"lon"`
	OccurredAt time.Time `json:"occurredAt" binding:"required"`
	TripID     *string   `json:"tripId"`
}

// EvaluateGeofenceRequest = POST /v1/geofences/evaluate. points = [{lat,lon,ts}] tal cual se
// pasa a device.fnc_evaluate_geofence.
type EvaluateGeofenceRequest struct {
	Points json.RawMessage `json:"points"`
}

// UpsertSettingRequest = PUT /v1/settings/:key. value es jsonb libre (numero, string, objeto).
type UpsertSettingRequest struct {
	Value json.RawMessage `json:"value" binding:"required"`
}

// SyncPushRequest = POST /v1/sync/push. items = [{entity, op, id, data{}, updated_at}] tal
// cual se pasa a device.prc_sync_push (passthrough del resultado).
type SyncPushRequest struct {
	Items json.RawMessage `json:"items" binding:"required"`
}

// RegisterDeviceRequest = POST /v1/devices/register. La presencia de tenantId decide el
// camino: tenantId -> fleet (prc_register_device); sin el pero con installId -> personal
// (prc_provision_personal_tenant). deviceId (uuid) lo genera la app y es obligatorio.
type RegisterDeviceRequest struct {
	DeviceID   string  `json:"deviceId" binding:"required"`
	InstallID  *string `json:"installId"`
	TenantID   *string `json:"tenantId"`
	AccountID  *string `json:"accountId"`
	Platform   *string `json:"platform"`
	OSVersion  *string `json:"osVersion"`
	AppVersion *string `json:"appVersion"`
	Model      *string `json:"model"`
}
