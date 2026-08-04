package osrm

import (
	"context"
	"encoding/json"
	"math"

	"ms-vehitrack/application/routing"
	"ms-vehitrack/domain/entities"
)

// Engine adapta *Client a application/routing.RouteEngine: convierte los waypoints de dominio
// al orden lon/lat de OSRM y mapea la Route cruda al RouteComputation que espera la cascada.
// Vive aqui (no en application) para que la capa de aplicacion no conozca el shape de OSRM.
type Engine struct {
	client *Client
}

func NewEngine(client *Client) *Engine {
	return &Engine{client: client}
}

// altRoute es una ruta alterna serializada para routing.route_cache.alternatives. Mismo shape
// que consume routing.fnc_get_route al mapear cada elemento del array `alternatives`.
type altRoute struct {
	GeoJSON   json.RawMessage `json:"geojson"`
	DistanceM float64         `json:"distance_m"`
	DurationS int             `json:"duration_s"`
	Steps     json.RawMessage `json:"steps"`
}

// Route calcula la ruta y sus alternativas con OSRM y las deja listas para
// routing.prc_store_route. La [0] es la principal (geometry/distance/duration/steps); el resto
// va en Alternatives como jsonb array. Los legs de OSRM (que contienen los steps cuando
// steps=true) se pasan tal cual. La duracion se redondea a segundos enteros (la columna es int).
func (e *Engine) Route(
	ctx context.Context, waypoints []entities.Waypoint, profile string,
) (*routing.RouteComputation, error) {
	wps := make([]Waypoint, len(waypoints))
	for i, w := range waypoints {
		wps[i] = Waypoint{Lat: w.Lat, Lon: w.Lon}
	}

	routes, err := e.client.RouteAll(ctx, wps, profile)
	if err != nil {
		return nil, err
	}

	primary := routes[0]
	comp := &routing.RouteComputation{
		DistanceM: primary.DistanceM,
		DurationS: int(math.Round(primary.DurationS)),
		Geometry:  primary.GeometryJS,
		Steps:     primary.Legs,
	}

	if len(routes) > 1 {
		alts := make([]altRoute, 0, len(routes)-1)
		for _, r := range routes[1:] {
			alts = append(alts, altRoute{
				GeoJSON:   r.GeometryJS,
				DistanceM: r.DistanceM,
				DurationS: int(math.Round(r.DurationS)),
				Steps:     r.Legs,
			})
		}
		if raw, err := json.Marshal(alts); err == nil {
			comp.Alternatives = raw
		}
	}

	return comp, nil
}
