package entities

import (
	"encoding/json"
	"errors"
	"time"
)

// FavoritePlace es una fila de device.fnc_list_favorite_place: un favorito vigente (o
// eliminado, si include_deleted) del dispositivo. Alimenta la pantalla de favoritos y el
// estado inicial del sync. El aislamiento por tenant lo pone RLS, no esta struct.
type FavoritePlace struct {
	ID             string     `json:"id"`
	FavoriteKindID string     `json:"favoriteKindId"`
	Label          string     `json:"label"`
	Description    *string    `json:"description,omitempty"`
	Icon           *string    `json:"icon,omitempty"`
	ColorHex       *string    `json:"colorHex,omitempty"`
	Lat            float64    `json:"lat"`
	Lon            float64    `json:"lon"`
	PlaceID        *int64     `json:"placeId,omitempty"`
	VisitCount     int        `json:"visitCount"`
	LastVisitedAt  *time.Time `json:"lastVisitedAt,omitempty"`
	UpdatedAt      time.Time  `json:"updatedAt"`
	DeletedAt      *time.Time `json:"deletedAt,omitempty"`
	SyncVersion    int64      `json:"syncVersion"`
}

// FavoriteUpsert son los datos de entrada de device.prc_upsert_favorite_place. El id llega
// aparte (de la URL): lo genera la app (uuid v7) para poder crear offline.
type FavoriteUpsert struct {
	Label           string
	Lat             float64
	Lon             float64
	Kind            string
	Description     *string
	Icon            *string
	ColorHex        *string
	PlaceID         *int64
	ClientUpdatedAt *time.Time
}

// PlaceUpsert son los datos de device.prc_upsert_place_user (POI propio del usuario).
type PlaceUpsert struct {
	Name            string
	Lat             float64
	Lon             float64
	CategoryID      string
	Description     *string
	ClientUpdatedAt *time.Time
}

// GeofenceUpsert son los datos de device.prc_upsert_geofence. GeomWKT es el punto (circle) o
// el poligono en WKT; la rutina valida que la geometria case con el shape (VT047).
type GeofenceUpsert struct {
	Name            string
	GeomWKT         string
	Shape           string
	RadiusM         *int
	Trigger         string
	CooldownS       *int
	IsActive        bool
	ClientUpdatedAt *time.Time
}

// GeofenceEventInput es un evento que la app evaluo en el dispositivo y reporta al servidor
// (device.prc_record_geofence_event). Idempotente por (geofence_id, occurred_at).
type GeofenceEventInput struct {
	GeofenceID string
	Trigger    string
	Lat        float64
	Lon        float64
	OccurredAt time.Time
	TripID     *string
}

// GeofenceHit es una fila de device.fnc_evaluate_geofence: un cruce (enter/exit) detectado al
// reproducir un lote de puntos contra las geocercas activas. Es auditoria, no tiempo real.
type GeofenceHit struct {
	GeofenceID string    `json:"geofenceId"`
	Name       string    `json:"name"`
	TriggerID  string    `json:"triggerId"`
	OccurredAt time.Time `json:"occurredAt"`
}

// RegisterInput agrupa los campos comunes de registro de dispositivo (fleet y personal).
type RegisterInput struct {
	DeviceID   string
	InstallID  *string
	TenantID   *string
	AccountID  *string
	Platform   *string
	OSVersion  *string
	AppVersion *string
	Model      *string
}

// SyncEntities son las entidades sincronizables validas (espejo de public.sync_entity). El
// servidor las valida tambien (VT048), pero tenerlas aqui permite un 400 temprano y barato.
var SyncEntities = map[string]bool{
	"favorite_place": true,
	"place_user":     true,
	"geofence":       true,
	"device_setting": true,
}

// IsSyncEntity indica si e es una entidad sincronizable conocida.
func IsSyncEntity(e string) bool { return SyncEntities[e] }

var (
	// ErrIDRequired = falta el id (uuid) del recurso en la URL de un upsert/delete.
	ErrIDRequired = errors.New("userdata: id requerido")
	// ErrSettingKeyRequired = falta la clave del ajuste.
	ErrSettingKeyRequired = errors.New("userdata: setting key requerida")
	// ErrSettingValueRequired = falta el valor jsonb del ajuste.
	ErrSettingValueRequired = errors.New("userdata: setting value requerido")
	// ErrEntityRequired = falta o es invalida la entidad en un soft-delete.
	ErrEntityRequired = errors.New("userdata: entity de sync invalida")
	// ErrSyncItemsRequired = el push llego sin items.
	ErrSyncItemsRequired = errors.New("userdata: items requeridos")
	// ErrGeofenceIDRequired = falta el geofence_id en un evento.
	ErrGeofenceIDRequired = errors.New("userdata: geofence_id requerido")
	// ErrGeofenceWKTRequired = falta el WKT de la geometria de la geocerca.
	ErrGeofenceWKTRequired = errors.New("userdata: geom WKT requerido")
	// ErrRegisterAmbiguous = el registro no distingue personal (install_id) de fleet (tenant_id).
	ErrRegisterAmbiguous = errors.New("userdata: registro requiere install_id (personal) o tenant_id (fleet)")
)

// jsonNull es el literal JSON nulo; util para detectar cuerpos vacios en passthrough.
var jsonNull = json.RawMessage("null")

// IsEmptyJSON indica si un jsonb de entrada esta ausente o es null literal.
func IsEmptyJSON(raw json.RawMessage) bool {
	return len(raw) == 0 || string(raw) == string(jsonNull)
}
