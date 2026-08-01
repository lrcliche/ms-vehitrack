package dto

import "encoding/json"

// RegionsForRouteRequest = POST /v1/regions/for-route. El GeoJSON de la ruta (LineString) se
// pasa tal cual a offline.fnc_regions_for_route.
type RegionsForRouteRequest struct {
	RouteGeojson json.RawMessage `json:"routeGeojson" binding:"required"`
}

// TrackPackageRequest = POST /v1/regions/:id/installed. operation ∈ {install, touch, remove}.
type TrackPackageRequest struct {
	Operation   string `json:"operation"`
	Version     *int   `json:"version"`
	SizeBytes   *int64 `json:"sizeBytes"`
	IsProtected *bool  `json:"isProtected"`
}
