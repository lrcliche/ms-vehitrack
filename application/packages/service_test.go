package packages

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"ms-vehitrack/domain/entities"
)

// --- fake store ----------------------------------------------------------------------

type fakeStore struct {
	manifest       json.RawMessage
	regions        []entities.RegionForRoute
	installed      []entities.DevicePackage
	trackResult    json.RawMessage
	lastTenantID   string
	lastDeviceID   string
	lastOperation  string
	lastRegionID   string
	manifestCalled int
	trackCalled    int
}

func (f *fakeStore) Manifest(_ context.Context, regionID string, _ *int) (json.RawMessage, error) {
	f.manifestCalled++
	f.lastRegionID = regionID
	return f.manifest, nil
}
func (f *fakeStore) RegionsForRoute(context.Context, json.RawMessage) ([]entities.RegionForRoute, error) {
	return f.regions, nil
}
func (f *fakeStore) ListInstalled(_ context.Context, tenantID, deviceID string) ([]entities.DevicePackage, error) {
	f.lastTenantID = tenantID
	f.lastDeviceID = deviceID
	return f.installed, nil
}
func (f *fakeStore) TrackPackage(_ context.Context, tenantID, deviceID, regionID, operation string, _ *int, _ *int64, _ *bool) (json.RawMessage, error) {
	f.trackCalled++
	f.lastTenantID = tenantID
	f.lastDeviceID = deviceID
	f.lastRegionID = regionID
	f.lastOperation = operation
	return f.trackResult, nil
}

// --- tests ---------------------------------------------------------------------------

func TestManifest_Passthrough(t *testing.T) {
	store := &fakeStore{manifest: json.RawMessage(`{"region_id":"co-atl","version":7}`)}
	svc := NewService(store)

	raw, err := svc.Manifest(context.Background(), "co-atl", nil)
	if err != nil {
		t.Fatal(err)
	}
	if string(raw) != `{"region_id":"co-atl","version":7}` {
		t.Fatalf("manifest no es passthrough: %s", raw)
	}
	if store.manifestCalled != 1 || store.lastRegionID != "co-atl" {
		t.Fatalf("debe llamar al store con la región: %+v", store)
	}
}

func TestManifest_EmptyRegion(t *testing.T) {
	svc := NewService(&fakeStore{})
	if _, err := svc.Manifest(context.Background(), "", nil); !errors.Is(err, entities.ErrRegionIDRequired) {
		t.Fatalf("quiero ErrRegionIDRequired, obtuve %v", err)
	}
}

func TestRegionsForRoute_EmptyGeojson(t *testing.T) {
	svc := NewService(&fakeStore{})
	if _, err := svc.RegionsForRoute(context.Background(), nil); !errors.Is(err, entities.ErrRouteGeojsonRequired) {
		t.Fatalf("quiero ErrRouteGeojsonRequired, obtuve %v", err)
	}
	if _, err := svc.RegionsForRoute(context.Background(), json.RawMessage("null")); !errors.Is(err, entities.ErrRouteGeojsonRequired) {
		t.Fatalf("null debe rechazarse, obtuve %v", err)
	}
}

func TestListInstalled_PassesTenant(t *testing.T) {
	store := &fakeStore{installed: []entities.DevicePackage{{RegionID: "co-atl", Name: "Barranquilla"}}}
	svc := NewService(store)

	res, err := svc.ListInstalled(context.Background(), "tenant-1", "dev-1")
	if err != nil {
		t.Fatal(err)
	}
	if len(res) != 1 {
		t.Fatalf("resultado inesperado: %+v", res)
	}
	if store.lastTenantID != "tenant-1" || store.lastDeviceID != "dev-1" {
		t.Fatalf("debe propagar tenant y device: %+v", store)
	}
}

func TestListInstalled_EmptyDevice(t *testing.T) {
	svc := NewService(&fakeStore{})
	if _, err := svc.ListInstalled(context.Background(), "tenant-1", ""); !errors.Is(err, entities.ErrDeviceIDRequired) {
		t.Fatalf("quiero ErrDeviceIDRequired, obtuve %v", err)
	}
}

func TestTrackPackage_DefaultsOperation(t *testing.T) {
	store := &fakeStore{trackResult: json.RawMessage(`{"operation":"install"}`)}
	svc := NewService(store)

	_, err := svc.TrackPackage(context.Background(), "tenant-1", "dev-1", "co-atl", "", nil, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if store.lastOperation != "install" {
		t.Fatalf("operation vacía debe ser install, obtuve %q", store.lastOperation)
	}
	if store.lastTenantID != "tenant-1" || store.lastRegionID != "co-atl" {
		t.Fatalf("debe propagar tenant y región: %+v", store)
	}
}

func TestTrackPackage_RequiresRegion(t *testing.T) {
	svc := NewService(&fakeStore{})
	if _, err := svc.TrackPackage(context.Background(), "t", "dev-1", "", "install", nil, nil, nil); !errors.Is(err, entities.ErrRegionIDRequired) {
		t.Fatalf("quiero ErrRegionIDRequired, obtuve %v", err)
	}
}
