package ports

import (
	"context"
	"encoding/json"

	"ms-vehitrack/domain/entities"
)

// UserDataStore es el puerto de los datos del usuario (favoritos, POI propios, geocercas,
// ajustes) + el motor de sync delta + el registro de dispositivo (doc 03 §3). Cada metodo
// envuelve UNA rutina prc_/fnc_ del esquema device: el store NO hace DML crudo.
//
// Casi todo es TENANT-SCOPED: device.* lleva RLS, asi que esos metodos corren dentro de
// pool.WithTenantTx(tenantID) y reciben el tenantID resuelto por el middleware TenantContext.
// Las DOS excepciones son el registro:
//   - RegisterDevice (fleet): CON tenant conocido (viene en el body), corre dentro de
//     WithTenantTx con ese tenant — prc_register_device esta sujeto a RLS.
//   - ProvisionPersonal (personal): SIN tenant, usa el pool directo. Es el UNICO camino de
//     escritura sin contexto de tenant del sistema (prc_provision_personal_tenant es SECURITY
//     DEFINER) — porque es el momento exacto en que el tenant aun no existe.
//
// Los errores VT* que levantan las rutinas se propagan con %w sobre el error crudo, sin
// romper la cadena de errors.As, para que presentationerrors.Map vea el *pgconn.PgError.
type UserDataStore interface {
	// ListFavorites = device.fnc_list_favorite_place. Tenant-scoped.
	ListFavorites(ctx context.Context, tenantID, deviceID string, includeDeleted bool) ([]entities.FavoritePlace, error)
	// UpsertFavorite = device.prc_upsert_favorite_place (INOUT p_result). Tenant-scoped.
	UpsertFavorite(ctx context.Context, tenantID, deviceID, id string, in entities.FavoriteUpsert) (json.RawMessage, error)
	// UpsertPlace = device.prc_upsert_place_user (INOUT p_result). Tenant-scoped.
	UpsertPlace(ctx context.Context, tenantID, deviceID, id string, in entities.PlaceUpsert) (json.RawMessage, error)
	// UpsertGeofence = device.prc_upsert_geofence (INOUT p_result). Tenant-scoped.
	UpsertGeofence(ctx context.Context, tenantID, deviceID, id string, in entities.GeofenceUpsert) (json.RawMessage, error)
	// UpsertSetting = device.prc_upsert_setting (INOUT p_result). Tenant-scoped.
	UpsertSetting(ctx context.Context, tenantID, deviceID, key string, value json.RawMessage) (json.RawMessage, error)
	// SoftDelete = device.prc_soft_delete (INOUT p_result). Tenant-scoped. entity ∈ sync_entity.
	SoftDelete(ctx context.Context, tenantID, deviceID, entity, id string) (json.RawMessage, error)
	// RecordGeofenceEvent = device.prc_record_geofence_event (INOUT p_result). Tenant-scoped.
	RecordGeofenceEvent(ctx context.Context, tenantID, deviceID string, in entities.GeofenceEventInput) (json.RawMessage, error)
	// EvaluateGeofence = device.fnc_evaluate_geofence. Tenant-scoped. points = [{lat,lon,ts}].
	EvaluateGeofence(ctx context.Context, tenantID, deviceID string, points json.RawMessage) ([]entities.GeofenceHit, error)
	// SyncChanges = device.fnc_sync_changes. Tenant-scoped. Devuelve el jsonb tal cual.
	SyncChanges(ctx context.Context, tenantID, deviceID string, entities []string, since *int64, limit *int) (json.RawMessage, error)
	// SyncPush = device.prc_sync_push (INOUT p_result). Tenant-scoped. Devuelve el jsonb tal cual.
	SyncPush(ctx context.Context, tenantID, deviceID string, items json.RawMessage) (json.RawMessage, error)
	// RegisterDevice = device.prc_register_device (fleet, CON tenant). Devuelve el jsonb tal cual.
	RegisterDevice(ctx context.Context, in entities.RegisterInput) (json.RawMessage, error)
	// ProvisionPersonal = device.prc_provision_personal_tenant (personal, SIN tenant, DEFINER).
	ProvisionPersonal(ctx context.Context, in entities.RegisterInput) (json.RawMessage, error)
}
