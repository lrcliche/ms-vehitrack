package osrm

import (
	"context"
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

// Route calcula la ruta con OSRM y la deja lista para routing.prc_store_route. Los legs de OSRM
// (que contienen los steps cuando steps=true) se pasan tal cual como maniobras. La duracion se
// redondea a segundos enteros (la columna es int).
func (e *Engine) Route(
	ctx context.Context, waypoints []entities.Waypoint, profile string,
) (*routing.RouteComputation, error) {
	wps := make([]Waypoint, len(waypoints))
	for i, w := range waypoints {
		wps[i] = Waypoint{Lat: w.Lat, Lon: w.Lon}
	}

	r, err := e.client.Route(ctx, wps, profile)
	if err != nil {
		return nil, err
	}

	return &routing.RouteComputation{
		DistanceM: r.DistanceM,
		DurationS: int(math.Round(r.DurationS)),
		Geometry:  r.GeometryJS,
		Steps:     r.Legs,
	}, nil
}
