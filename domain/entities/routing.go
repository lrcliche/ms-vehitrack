package entities

import "errors"

// Waypoint es un punto {lat,lon} de la ruta pedida. La app manda al menos dos (origen y
// destino) en orden; routing.fnc_waypoints_hash los normaliza para la clave de cache.
type Waypoint struct {
	Lat float64 `json:"lat"`
	Lon float64 `json:"lon"`
}

var (
	// ErrWaypointsRequired = faltan waypoints en POST /routes.
	ErrWaypointsRequired = errors.New("routing: waypoints requeridos")
	// ErrTooFewWaypoints = se necesitan al menos 2 waypoints (origen y destino).
	ErrTooFewWaypoints = errors.New("routing: se requieren al menos 2 waypoints")
)
