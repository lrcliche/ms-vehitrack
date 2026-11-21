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
	// Alternatives = rutas alternas (jsonb array de {geojson,distance_m,duration_s,steps}),
	// o nil si no hubo. Se persiste tal cual en routing.route_cache.alternatives; fnc_get_route
	// las devuelve junto a la principal en el array `routes`.
	Alternatives json.RawMessage
}

// RouteEngine es el motor de ruteo externo (OSRM), detras de una interfaz para no acoplar la
// aplicacion al cliente HTTP y poder falsearlo en tests.
type RouteEngine interface {
	Route(ctx context.Context, waypoints []entities.Waypoint, profile string) (*RouteComputation, error)
}

// TrafficETA ajusta la duracion de una ruta al trafico en vivo de una fuente EXTERNA (TomTom
// Flow), como ARRANQUE mientras el trafico colaborativo (traffic.live_state) aun no cubre. Se
// aplica solo a rutas SIN señal crowd. geometryGeoJSON = LineString GeoJSON de la ruta;
// devuelve (segundos ajustados, true) o (_, false) si no hay dato / no esta configurado.
type TrafficETA interface {
	AdjustedDuration(ctx context.Context, geometryGeoJSON json.RawMessage, freeFlowS float64) (float64, bool)
}

// Service implementa la cascada de ruteo sobre el store PG y el motor OSRM.
type Service struct {
	store  ports.RoutingStore
	engine RouteEngine
	eta    TrafficETA // opcional (arranque TomTom); nil = solo crowd/flujo libre.
}

func NewService(store ports.RoutingStore, engine RouteEngine) *Service {
	return &Service{store: store, engine: engine}
}

// WithTrafficETA enchufa una fuente externa de ETA (TomTom) como arranque. Devuelve el mismo
// Service para encadenar en el arranque. Sin llamarlo, el ETA se queda en crowd/flujo libre.
func (s *Service) WithTrafficETA(eta TrafficETA) *Service {
	s.eta = eta
	return s
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
	return s.route(ctx, tenantID, deviceID, waypoints, profile, nil, "")
}

// RouteForUser is the token-authenticated enterprise route flow. It uses the same cache and
// OSRM engine as Route while attributing route_request to the business user, not a device.
func (s *Service) RouteForUser(
	ctx context.Context, tenantID, userID, tenantUserID string,
	waypoints []entities.Waypoint, profile string,
) (json.RawMessage, bool, error) {
	if userID == "" || tenantUserID == "" {
		return nil, false, entities.ErrDeviceIDRequired
	}
	store, ok := s.store.(ports.BusinessRoutingStore)
	if !ok {
		return nil, false, entities.ErrBusinessRoutingUnavailable
	}
	return s.route(ctx, tenantID, userID, waypoints, profile, store, tenantUserID)
}

func (s *Service) route(
	ctx context.Context, tenantID, actorID string,
	waypoints []entities.Waypoint, profile string,
	businessStore ports.BusinessRoutingStore, tenantUserID string,
) (json.RawMessage, bool, error) {
	if len(waypoints) == 0 {
		return nil, false, entities.ErrWaypointsRequired
	}
	if len(waypoints) < 2 {
		return nil, false, entities.ErrTooFewWaypoints
	}
	// La app manda profile 'driving' (nombre OSRM); el unico route_profile del modelo es
	// 'car'. Se normaliza aqui para no chocar con VT061 (perfil invalido) en prc_store_route.
	if profile == "" || profile == "driving" {
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
		var recordErr error
		if businessStore != nil {
			recordErr = businessStore.RecordUserHit(ctx, tenantID, actorID, tenantUserID, meta.RouteCacheID)
		} else {
			recordErr = s.store.RecordHit(ctx, tenantID, actorID, meta.RouteCacheID)
		}
		if recordErr != nil {
			return nil, false, recordErr
		}
		return s.enrich(ctx, cached), true, nil
	}

	comp, err := s.engine.Route(ctx, waypoints, profile)
	if err != nil {
		return nil, false, err
	}
	var stored json.RawMessage
	if businessStore != nil {
		stored, err = businessStore.StoreUserRoute(ctx, tenantID, actorID, tenantUserID, wpJSON,
			comp.Geometry, comp.DistanceM, comp.DurationS, profile, comp.Steps, comp.Alternatives)
	} else {
		stored, err = s.store.StoreRoute(ctx, tenantID, actorID, wpJSON,
			comp.Geometry, comp.DistanceM, comp.DurationS, profile, comp.Steps, comp.Alternatives)
	}
	if err != nil {
		return nil, false, err
	}
	return s.enrich(ctx, stored), false, nil
}

// enrich rellena duration_in_traffic_s con la fuente externa (TomTom) en las rutas que NO
// tienen señal colaborativa (ETA == flujo libre). Respeta el dato crowd cuando existe (ETA >
// flujo libre): el trafico propio manda sobre el de arranque. Sin `eta` configurada, o ante
// cualquier fallo de parseo, devuelve el jsonb intacto — nunca degrada la respuesta.
func (s *Service) enrich(ctx context.Context, raw json.RawMessage) json.RawMessage {
	if s.eta == nil || len(raw) == 0 {
		return raw
	}
	var doc map[string]json.RawMessage
	if err := json.Unmarshal(raw, &doc); err != nil {
		return raw
	}
	routesRaw, ok := doc["routes"]
	if !ok {
		return raw
	}
	var routes []map[string]json.RawMessage
	if err := json.Unmarshal(routesRaw, &routes); err != nil || len(routes) == 0 {
		return raw
	}

	changed := false
	for _, r := range routes {
		var freeFlow float64
		if err := json.Unmarshal(r["duration_s"], &freeFlow); err != nil || freeFlow <= 0 {
			continue
		}
		// ¿ya hay señal crowd? (ETA > flujo libre). Si la hay, no se pisa con TomTom.
		if v, present := r["duration_in_traffic_s"]; present {
			var dit float64
			if json.Unmarshal(v, &dit) == nil && dit > freeFlow+1 {
				continue
			}
		}
		geo := r["geojson"]
		if len(geo) == 0 {
			continue
		}
		adj, applied := s.eta.AdjustedDuration(ctx, geo, freeFlow)
		if !applied {
			continue
		}
		b, err := json.Marshal(int(adj + 0.5))
		if err != nil {
			continue
		}
		r["duration_in_traffic_s"] = b
		changed = true
	}
	if !changed {
		return raw
	}

	nr, err := json.Marshal(routes)
	if err != nil {
		return raw
	}
	doc["routes"] = nr
	out, err := json.Marshal(doc)
	if err != nil {
		return raw
	}
	return out
}
