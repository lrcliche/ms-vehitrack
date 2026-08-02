// Package userdata orquesta los datos del usuario (favoritos, POI propios, geocercas,
// ajustes), el motor de sync bidireccional (changes/push) y el registro de dispositivo
// (doc 03 §3). Todo el trabajo real vive en rutinas PG del esquema device; el servicio solo
// valida entradas baratas y delega en el store. Las reglas de negocio (last-write-wins,
// unicidad casa/trabajo, cupos, geometria) las fuerza la BD con SQLSTATE VT*.
package userdata

import (
	"context"
	"encoding/json"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

// Service implementa los casos de uso de datos del usuario + sync + registro sobre el store PG.
type Service struct {
	store ports.UserDataStore
}

func NewService(store ports.UserDataStore) *Service {
	return &Service{store: store}
}

// ListFavorites = device.fnc_list_favorite_place (TENANT-SCOPED).
func (s *Service) ListFavorites(
	ctx context.Context, tenantID, deviceID string, includeDeleted bool,
) ([]entities.FavoritePlace, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	return s.store.ListFavorites(ctx, tenantID, deviceID, includeDeleted)
}

// UpsertFavorite = device.prc_upsert_favorite_place. El id (uuid v7) lo trae la app en la URL.
// kind vacio -> 'custom' (la BD valida el resto: VT042 coords, VT043 kind, VT044 unicidad).
func (s *Service) UpsertFavorite(
	ctx context.Context, tenantID, deviceID, id string, in entities.FavoriteUpsert,
) (json.RawMessage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	if id == "" {
		return nil, entities.ErrIDRequired
	}
	if in.Kind == "" {
		in.Kind = "custom"
	}
	return s.store.UpsertFavorite(ctx, tenantID, deviceID, id, in)
}

// UpsertPlace = device.prc_upsert_place_user. category vacia -> 'other'.
func (s *Service) UpsertPlace(
	ctx context.Context, tenantID, deviceID, id string, in entities.PlaceUpsert,
) (json.RawMessage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	if id == "" {
		return nil, entities.ErrIDRequired
	}
	if in.CategoryID == "" {
		in.CategoryID = "other"
	}
	return s.store.UpsertPlace(ctx, tenantID, deviceID, id, in)
}

// UpsertGeofence = device.prc_upsert_geofence. shape vacio -> 'circle', trigger vacio ->
// 'both'. El WKT es obligatorio; la BD valida que la geometria case con el shape (VT047).
func (s *Service) UpsertGeofence(
	ctx context.Context, tenantID, deviceID, id string, in entities.GeofenceUpsert,
) (json.RawMessage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	if id == "" {
		return nil, entities.ErrIDRequired
	}
	if in.GeomWKT == "" {
		return nil, entities.ErrGeofenceWKTRequired
	}
	if in.Shape == "" {
		in.Shape = "circle"
	}
	if in.Trigger == "" {
		in.Trigger = "both"
	}
	return s.store.UpsertGeofence(ctx, tenantID, deviceID, id, in)
}

// UpsertSetting = device.prc_upsert_setting. key y value (jsonb) obligatorios.
func (s *Service) UpsertSetting(
	ctx context.Context, tenantID, deviceID, key string, value json.RawMessage,
) (json.RawMessage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	if key == "" {
		return nil, entities.ErrSettingKeyRequired
	}
	if entities.IsEmptyJSON(value) {
		return nil, entities.ErrSettingValueRequired
	}
	return s.store.UpsertSetting(ctx, tenantID, deviceID, key, value)
}

// SoftDelete = device.prc_soft_delete. entity debe ser una sync_entity conocida (400 barato
// antes de tocar la BD; la BD igual valida con VT048).
func (s *Service) SoftDelete(
	ctx context.Context, tenantID, deviceID, entity, id string,
) (json.RawMessage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	if id == "" {
		return nil, entities.ErrIDRequired
	}
	if !entities.IsSyncEntity(entity) {
		return nil, entities.ErrEntityRequired
	}
	return s.store.SoftDelete(ctx, tenantID, deviceID, entity, id)
}

// RecordGeofenceEvent = device.prc_record_geofence_event. Idempotente por (geofence, ts).
func (s *Service) RecordGeofenceEvent(
	ctx context.Context, tenantID, deviceID string, in entities.GeofenceEventInput,
) (json.RawMessage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	if in.GeofenceID == "" {
		return nil, entities.ErrGeofenceIDRequired
	}
	return s.store.RecordGeofenceEvent(ctx, tenantID, deviceID, in)
}

// EvaluateGeofence = device.fnc_evaluate_geofence. points = [{lat,lon,ts}]. Cero puntos no es
// error (devuelve lista vacia): la rutina hace COALESCE a '[]'.
func (s *Service) EvaluateGeofence(
	ctx context.Context, tenantID, deviceID string, points json.RawMessage,
) ([]entities.GeofenceHit, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	if entities.IsEmptyJSON(points) {
		points = json.RawMessage("[]")
	}
	return s.store.EvaluateGeofence(ctx, tenantID, deviceID, points)
}

// SyncChanges = device.fnc_sync_changes. Passthrough del jsonb {next_version, has_more,
// entities}. entities nil = todas.
func (s *Service) SyncChanges(
	ctx context.Context, tenantID, deviceID string, ents []string, since *int64, limit *int,
) (json.RawMessage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	return s.store.SyncChanges(ctx, tenantID, deviceID, ents, since, limit)
}

// SyncPush = device.prc_sync_push. Passthrough del jsonb {applied, skipped, failed[],
// next_version}. items debe ser un array no vacio (la BD valida el tope con VT051). Reenviar
// el mismo lote es esperado (idempotente): no es un error que se castigue aqui.
func (s *Service) SyncPush(
	ctx context.Context, tenantID, deviceID string, items json.RawMessage,
) (json.RawMessage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	if entities.IsEmptyJSON(items) {
		return nil, entities.ErrSyncItemsRequired
	}
	return s.store.SyncPush(ctx, tenantID, deviceID, items)
}

// Register enruta el registro segun el body: si trae tenant_id -> fleet (prc_register_device,
// CON tenant); si no y trae install_id -> personal (prc_provision_personal_tenant, SIN tenant,
// DEFINER). Sin ninguno de los dos es ambiguo (400). El device_id (uuid) lo genera la app y es
// obligatorio en ambos caminos. Devuelve el jsonb de la rutina tal cual.
func (s *Service) Register(
	ctx context.Context, in entities.RegisterInput,
) (json.RawMessage, error) {
	if in.DeviceID == "" {
		return nil, entities.ErrIDRequired
	}
	switch {
	case in.TenantID != nil && *in.TenantID != "":
		return s.store.RegisterDevice(ctx, in)
	case in.InstallID != nil && *in.InstallID != "":
		return s.store.ProvisionPersonal(ctx, in)
	default:
		return nil, entities.ErrRegisterAmbiguous
	}
}
