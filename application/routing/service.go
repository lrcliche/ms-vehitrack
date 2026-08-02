// Package routing orquesta el ruteo con cascada de cache (doc 03 §3): primero
// routing.fnc_get_route; si hay hit registra el hit y devuelve la ruta de cache; si no,
// consulta al motor OSRM y persiste el resultado con routing.prc_store_route. El ms no calcula
// geometria: solo cachea lo que devuelve OSRM y deja que la BD valide (VT060/061/062).
package routing

import (
	"context"
	"encoding/json"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

// RouteComputation es lo que devuelve el motor de ruteo (OSRM), ya en la forma que espera
// routing.prc_store_route: geometria GeoJSON (LineString), distancia, duracion y maniobras.
type RouteComputation struct {
	DistanceM float64
	DurationS int
	Geometry  json.RawMessage // GeoJSON LineString
	Steps     json.RawMessage // maniobras crudas (legs/steps de OSRM)
}

// RouteEngine es el motor de ruteo externo (OSRM), detras de una interfaz para no acoplar la
// aplicacion al cliente HTTP y poder falsearlo en tests.
type RouteEngine interface {
	Route(ctx context.Context, waypoints []entities.Waypoint, profile string) (*RouteComputation, error)
}

// Service implementa la cascada de ruteo sobre el store PG y el motor OSRM.
type Service struct {
	store  ports.RoutingStore
	engine RouteEngine
}

func NewService(store ports.RoutingStore, engine RouteEngine) *Service {
	return &Service{store: store, engine: engine}
}

// Route resuelve POST /routes. Devuelve (ruta jsonb, cacheHit, error). profile vacio -> 'car'.
// La cascada:
//  1. routing.fnc_get_route: si hay hit -> prc_record_route_hit y devuelve la ruta (cacheHit=true).
//  2. miss -> OSRM -> routing.prc_store_route -> devuelve la ruta persistida (cacheHit=false).
func (s *Service) Route(
	ctx context.Context, tenantID, deviceID string, waypoints []entities.Waypoint, profile string,
) (json.RawMessage, bool, error) {
	if deviceID == "" {
		return nil, false, entities.ErrDeviceIDRequired
	}
	if len(waypoints) == 0 {
		return nil, false, entities.ErrWaypointsRequired
	}
	if len(waypoints) < 2 {
		return nil, false, entities.ErrTooFewWaypoints
	}
	if profile == "" {
		profile = "car"
	}

	wpJSON, err := json.Marshal(waypoints)
	if err != nil {
		return nil, false, err
	}

	cached, err := s.store.GetRoute(ctx, wpJSON, profile)
	if err != nil {
		return nil, false, err
	}
	if cached != nil {
		var meta struct {
			RouteCacheID int64 `json:"route_cache_id"`
		}
		if err := json.Unmarshal(cached, &meta); err != nil {
			return nil, false, err
		}
		if err := s.store.RecordHit(ctx, tenantID, deviceID, meta.RouteCacheID); err != nil {
			return nil, false, err
		}
		return cached, true, nil
	}

	comp, err := s.engine.Route(ctx, waypoints, profile)
	if err != nil {
		return nil, false, err
	}
	stored, err := s.store.StoreRoute(ctx, tenantID, deviceID, wpJSON,
		comp.Geometry, comp.DistanceM, comp.DurationS, profile, comp.Steps, nil)
	if err != nil {
		return nil, false, err
	}
	return stored, false, nil
}
