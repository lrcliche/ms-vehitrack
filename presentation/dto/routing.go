package dto

// RouteWaypoint es un punto {lat,lon} del cuerpo de POST /routes.
type RouteWaypoint struct {
	Lat float64 `json:"lat"`
	Lon float64 `json:"lon"`
}

// RouteRequest = POST /api/v1/routes. profile vacio -> 'car' lo pone el servicio.
type RouteRequest struct {
	Waypoints []RouteWaypoint `json:"waypoints"`
	Profile   string          `json:"profile"`
}
