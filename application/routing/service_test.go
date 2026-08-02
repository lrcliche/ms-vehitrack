package routing

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"ms-vehitrack/domain/entities"
)

// --- fakes ---------------------------------------------------------------------------

type fakeStore struct {
	getResult   json.RawMessage
	storeResult json.RawMessage
	hitCalled   int
	storeCalled int
	lastTenant  string
	lastDevice  string
	lastCacheID int64
}

func (f *fakeStore) GetRoute(_ context.Context, _ json.RawMessage, _ string) (json.RawMessage, error) {
	return f.getResult, nil
}
func (f *fakeStore) RecordHit(_ context.Context, tenantID, deviceID string, cacheID int64) error {
	f.hitCalled++
	f.lastTenant = tenantID
	f.lastDevice = deviceID
	f.lastCacheID = cacheID
	return nil
}
func (f *fakeStore) StoreRoute(
	_ context.Context, tenantID, deviceID string,
	_, _ json.RawMessage, _ float64, _ int, _ string, _, _ json.RawMessage,
) (json.RawMessage, error) {
	f.storeCalled++
	f.lastTenant = tenantID
	f.lastDevice = deviceID
	return f.storeResult, nil
}

type fakeEngine struct {
	called int
	result *RouteComputation
	err    error
}

func (e *fakeEngine) Route(_ context.Context, _ []entities.Waypoint, _ string) (*RouteComputation, error) {
	e.called++
	if e.err != nil {
		return nil, e.err
	}
	return e.result, nil
}

func twoWaypoints() []entities.Waypoint {
	return []entities.Waypoint{{Lat: 10.99, Lon: -74.79}, {Lat: 11.00, Lon: -74.80}}
}

// --- tests ---------------------------------------------------------------------------

func TestRoute_CacheHit(t *testing.T) {
	store := &fakeStore{getResult: json.RawMessage(`{"route_cache_id":42,"distance_m":1200}`)}
	engine := &fakeEngine{}
	svc := NewService(store, engine)

	raw, cacheHit, err := svc.Route(context.Background(), "tenant-1", "dev-1", twoWaypoints(), "")
	if err != nil {
		t.Fatal(err)
	}
	if !cacheHit {
		t.Fatalf("esperaba cacheHit=true")
	}
	if engine.called != 0 {
		t.Fatalf("no debe llamar a OSRM en un hit")
	}
	if store.hitCalled != 1 || store.lastCacheID != 42 {
		t.Fatalf("debe registrar el hit con el route_cache_id: %+v", store)
	}
	if string(raw) != `{"route_cache_id":42,"distance_m":1200}` {
		t.Fatalf("passthrough de la ruta de cache: %s", raw)
	}
}

func TestRoute_CacheMiss_CallsOSRMAndStores(t *testing.T) {
	store := &fakeStore{
		getResult:   nil,
		storeResult: json.RawMessage(`{"route_cache_id":7,"expires_at":"2026-08-02T00:00:00Z"}`),
	}
	engine := &fakeEngine{result: &RouteComputation{
		DistanceM: 1500, DurationS: 300,
		Geometry: json.RawMessage(`{"type":"LineString","coordinates":[]}`),
		Steps:    json.RawMessage(`[]`),
	}}
	svc := NewService(store, engine)

	raw, cacheHit, err := svc.Route(context.Background(), "tenant-1", "dev-1", twoWaypoints(), "car")
	if err != nil {
		t.Fatal(err)
	}
	if cacheHit {
		t.Fatalf("esperaba cacheHit=false en un miss")
	}
	if engine.called != 1 {
		t.Fatalf("debe llamar a OSRM en un miss")
	}
	if store.storeCalled != 1 || store.hitCalled != 0 {
		t.Fatalf("debe persistir y NO registrar hit: %+v", store)
	}
	if store.lastTenant != "tenant-1" || store.lastDevice != "dev-1" {
		t.Fatalf("debe propagar tenant y device: %+v", store)
	}
	if string(raw) != string(store.storeResult) {
		t.Fatalf("debe devolver la ruta persistida: %s", raw)
	}
}

func TestRoute_RequiresDevice(t *testing.T) {
	svc := NewService(&fakeStore{}, &fakeEngine{})
	if _, _, err := svc.Route(context.Background(), "t", "", twoWaypoints(), ""); !errors.Is(err, entities.ErrDeviceIDRequired) {
		t.Fatalf("quiero ErrDeviceIDRequired, obtuve %v", err)
	}
}

func TestRoute_RequiresWaypoints(t *testing.T) {
	svc := NewService(&fakeStore{}, &fakeEngine{})
	if _, _, err := svc.Route(context.Background(), "t", "dev-1", nil, ""); !errors.Is(err, entities.ErrWaypointsRequired) {
		t.Fatalf("quiero ErrWaypointsRequired, obtuve %v", err)
	}
}

func TestRoute_RejectsSingleWaypoint(t *testing.T) {
	svc := NewService(&fakeStore{}, &fakeEngine{})
	one := []entities.Waypoint{{Lat: 10.99, Lon: -74.79}}
	if _, _, err := svc.Route(context.Background(), "t", "dev-1", one, ""); !errors.Is(err, entities.ErrTooFewWaypoints) {
		t.Fatalf("quiero ErrTooFewWaypoints, obtuve %v", err)
	}
}

func TestRoute_OSRMError_Propagates(t *testing.T) {
	engine := &fakeEngine{err: errors.New("osrm down")}
	svc := NewService(&fakeStore{getResult: nil}, engine)
	if _, _, err := svc.Route(context.Background(), "t", "dev-1", twoWaypoints(), ""); err == nil {
		t.Fatalf("esperaba propagar el error de OSRM")
	}
}
