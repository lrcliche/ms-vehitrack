package entities

import (
	"errors"
	"time"
)

// RegionForRoute es una fila de offline.fnc_regions_for_route: una región que la ruta
// atraviesa, con el peso del paquete vigente para que la app decida qué prebajar.
type RegionForRoute struct {
	RegionID       string `json:"regionId"`
	Name           string `json:"name"`
	CurrentVersion int    `json:"currentVersion"`
	SizeBytes      int64  `json:"sizeBytes"`
}

// DevicePackage es una fila de device.fnc_list_device_package: una región instalada en el
// dispositivo con aviso de actualización. Alimenta la pantalla "Offline Maps".
type DevicePackage struct {
	RegionID         string     `json:"regionId"`
	Name             string     `json:"name"`
	InstalledVersion int        `json:"installedVersion"`
	CurrentVersion   int        `json:"currentVersion"`
	UpdateAvailable  bool       `json:"updateAvailable"`
	SizeBytes        int64      `json:"sizeBytes"`
	LastUsedAt       *time.Time `json:"lastUsedAt,omitempty"`
	IsProtected      bool       `json:"isProtected"`
}

var (
	// ErrRegionIDRequired = falta el id de región (manifest / track).
	ErrRegionIDRequired = errors.New("offline: region_id requerida")
	// ErrDeviceIDRequired = falta el device_id en una ruta tenant-scoped.
	ErrDeviceIDRequired = errors.New("offline: device_id requerido")
	// ErrRouteGeojsonRequired = falta el GeoJSON de la ruta.
	ErrRouteGeojsonRequired = errors.New("offline: routeGeojson requerido")
)
