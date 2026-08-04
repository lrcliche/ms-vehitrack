package dto

import "encoding/json"

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

// storedRouteItem es UNA ruta dentro del array `routes` de routing.fnc_get_route (claves del
// modelo PG). Se deserializa para re-mapearla al contrato que consume la app.
type storedRouteItem struct {
	GeoJSON            json.RawMessage `json:"geojson"`
	DistanceM          float64         `json:"distance_m"`
	DurationS          float64         `json:"duration_s"`
	DurationInTrafficS *float64        `json:"duration_in_traffic_s"`
	Steps              json.RawMessage `json:"steps"`
}

// storedRoutes es el shape que devuelve routing.fnc_get_route: la principal y sus alternativas
// bajo `routes`, con el id de cache y la vigencia en la raiz.
type storedRoutes struct {
	RouteCacheID int64             `json:"route_cache_id"`
	ExpiresAt    *string           `json:"expires_at"`
	Routes       []storedRouteItem `json:"routes"`
}

// RouteView es UNA ruta en el contrato de la app: geometry (GeoJSON LineString), distance (m),
// duration (s, flujo libre), duration_in_traffic (s, con trafico vivo) y steps. La app rankea
// "mas rapida" y muestra el ETA por duration_in_traffic cuando viene; cae a duration si es 0.
type RouteView struct {
	Geometry          json.RawMessage `json:"geometry"`
	Distance          float64         `json:"distance"`
	Duration          float64         `json:"duration"`
	DurationInTraffic *float64        `json:"duration_in_traffic,omitempty"`
	// El jsonb `steps` del modelo guarda los LEGS de OSRM ([{steps:[...]}]); se emite bajo
	// `legs` porque la app extrae las maniobras de leg['steps'] (VehitrackRoutingEngine).
	Legs      json.RawMessage `json:"legs,omitempty"`
	ExpiresAt *string         `json:"expires_at,omitempty"`
}

// RouteViewsFromStored re-mapea el jsonb de fnc_get_route (routes[]) al contrato de la app:
// una lista de RouteView (principal + alternativas). ok=false si no hay ninguna ruta con
// geometria (no deberia pasar en un hit valido).
func RouteViewsFromStored(raw json.RawMessage) ([]RouteView, bool) {
	var s storedRoutes
	if err := json.Unmarshal(raw, &s); err != nil || len(s.Routes) == 0 {
		return nil, false
	}
	out := make([]RouteView, 0, len(s.Routes))
	for _, r := range s.Routes {
		if len(r.GeoJSON) == 0 {
			continue
		}
		out = append(out, RouteView{
			Geometry:          r.GeoJSON,
			Distance:          r.DistanceM,
			Duration:          r.DurationS,
			DurationInTraffic: r.DurationInTrafficS,
			Legs:              r.Steps,
			ExpiresAt:         s.ExpiresAt,
		})
	}
	if len(out) == 0 {
		return nil, false
	}
	return out, true
}
