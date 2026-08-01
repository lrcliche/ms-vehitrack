package ports

import (
	"context"
	"encoding/json"

	"ms-vehitrack/domain/entities"
)

// OfflineStore es el puerto de los paquetes offline en PG. Cada método envuelve UNA rutina
// fnc_/prc_ del esquema offline/device (doc 03): el store no hace DML crudo.
//
// Los métodos GLOBALES (Manifest, RegionsForRoute) viven en offline.* (sin RLS) y usan el
// pool directo. Los TENANT-SCOPED (ListInstalled, TrackPackage) tocan device.device_package
// (con RLS) y DEBEN correr dentro de una transacción con app.tenant_id fijado; por eso
// reciben el tenantID resuelto por el middleware TenantContext.
//
// Los errores VT* (VT070/VT041/VT074) que levantan las rutinas se propagan tal cual para que
// presentationerrors.Map los traduzca al HTTP correcto; el store no los envuelve de forma que
// rompa la cadena de errores.As.
type OfflineStore interface {
	// Manifest = offline.fnc_region_manifest. installedVersion nil = sin versión instalada.
	// Levanta VT070 si la región no tiene paquete publicado.
	Manifest(ctx context.Context, regionID string, installedVersion *int) (json.RawMessage, error)
	// RegionsForRoute = offline.fnc_regions_for_route. Cero filas NO es error.
	RegionsForRoute(ctx context.Context, routeGeojson json.RawMessage) ([]entities.RegionForRoute, error)
	// ListInstalled = device.fnc_list_device_package. Tenant-scoped.
	ListInstalled(ctx context.Context, tenantID, deviceID string) ([]entities.DevicePackage, error)
	// TrackPackage = device.prc_track_device_package (INOUT p_result). Tenant-scoped.
	// operation ∈ {install, touch, remove}. Levanta VT041/VT074.
	TrackPackage(ctx context.Context, tenantID, deviceID, regionID, operation string, version *int, sizeBytes *int64, isProtected *bool) (json.RawMessage, error)
}
