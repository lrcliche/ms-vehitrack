// Package packages orquesta los paquetes de región offline: manifiesto, descarga predictiva
// por ruta, listado de instalados y el tracking de install/touch/remove (doc 03 §5). Todo el
// trabajo real vive en rutinas PG; el servicio solo valida entradas y delega en el store.
package packages

import (
	"context"
	"encoding/json"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

// Service implementa los casos de uso de paquetes offline sobre el store PG.
type Service struct {
	store ports.OfflineStore
}

func NewService(store ports.OfflineStore) *Service {
	return &Service{store: store}
}

// Manifest = offline.fnc_region_manifest (GLOBAL). installedVersion opcional.
func (s *Service) Manifest(
	ctx context.Context, regionID string, installedVersion *int,
) (json.RawMessage, error) {
	if regionID == "" {
		return nil, entities.ErrRegionIDRequired
	}
	return s.store.Manifest(ctx, regionID, installedVersion)
}

// RegionsForRoute = offline.fnc_regions_for_route (GLOBAL).
func (s *Service) RegionsForRoute(
	ctx context.Context, routeGeojson json.RawMessage,
) ([]entities.RegionForRoute, error) {
	if len(routeGeojson) == 0 || string(routeGeojson) == "null" {
		return nil, entities.ErrRouteGeojsonRequired
	}
	return s.store.RegionsForRoute(ctx, routeGeojson)
}

// ListInstalled = device.fnc_list_device_package (TENANT-SCOPED). El tenantID lo resuelve el
// middleware y viaja explícito hasta el store, que abre la transacción con app.tenant_id.
func (s *Service) ListInstalled(
	ctx context.Context, tenantID, deviceID string,
) ([]entities.DevicePackage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	return s.store.ListInstalled(ctx, tenantID, deviceID)
}

// TrackPackage = device.prc_track_device_package (TENANT-SCOPED). operation por defecto
// "install"; la validez real de la operación la fuerza la rutina (VT074).
func (s *Service) TrackPackage(
	ctx context.Context, tenantID, deviceID, regionID, operation string,
	version *int, sizeBytes *int64, isProtected *bool,
) (json.RawMessage, error) {
	if deviceID == "" {
		return nil, entities.ErrDeviceIDRequired
	}
	if regionID == "" {
		return nil, entities.ErrRegionIDRequired
	}
	if operation == "" {
		operation = "install"
	}
	return s.store.TrackPackage(ctx, tenantID, deviceID, regionID, operation, version, sizeBytes, isProtected)
}
