package tracking

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"ms-vehitrack/domain/entities"
)

// --- fake store ----------------------------------------------------------------------

type fakeStore struct {
	ingestResult json.RawMessage
	tripResult   json.RawMessage
	closeResult  json.RawMessage
	obdResult    json.RawMessage
	lastTenant   string
	lastDevice   string
	lastStatus   string
	lastProtocol string
	ingestCalled int
	tripCalled   int
	closeCalled  int
	obdCalled    int
}

func (f *fakeStore) IngestTelemetry(_ context.Context, tenantID, deviceID, _ string, _ json.RawMessage, _ *time.Time) (json.RawMessage, error) {
	f.ingestCalled++
	f.lastTenant = tenantID
	f.lastDevice = deviceID
	return f.ingestResult, nil
}
func (f *fakeStore) UpsertTrip(_ context.Context, tenantID, deviceID, _ string, in entities.TripUpsert) (json.RawMessage, error) {
	f.tripCalled++
	f.lastTenant = tenantID
	f.lastDevice = deviceID
	f.lastStatus = in.Status
	return f.tripResult, nil
}
func (f *fakeStore) CloseTrip(_ context.Context, tenantID, _ string) (json.RawMessage, error) {
	f.closeCalled++
	f.lastTenant = tenantID
	return f.closeResult, nil
}
func (f *fakeStore) UpsertObdSession(_ context.Context, tenantID, deviceID, _ string, in entities.ObdSessionUpsert) (json.RawMessage, error) {
	f.obdCalled++
	f.lastTenant = tenantID
	f.lastDevice = deviceID
	f.lastProtocol = in.Protocol
	return f.obdResult, nil
}

// --- tests ---------------------------------------------------------------------------

func TestIngestTelemetry_Passthrough(t *testing.T) {
	store := &fakeStore{ingestResult: json.RawMessage(`{"batch_id":"b1","duplicate":false}`)}
	svc := NewService(store)

	raw, err := svc.IngestTelemetry(context.Background(), "tenant-1", "dev-1", "b1",
		json.RawMessage(`[{"lat":10.9,"lon":-74.8}]`), nil)
	if err != nil {
		t.Fatal(err)
	}
	if store.ingestCalled != 1 || store.lastTenant != "tenant-1" || store.lastDevice != "dev-1" {
		t.Fatalf("debe propagar tenant y device: %+v", store)
	}
	if string(raw) != `{"batch_id":"b1","duplicate":false}` {
		t.Fatalf("passthrough del resultado: %s", raw)
	}
}

func TestIngestTelemetry_RequiresBatchID(t *testing.T) {
	svc := NewService(&fakeStore{})
	_, err := svc.IngestTelemetry(context.Background(), "t", "dev-1", "", json.RawMessage(`[]`), nil)
	if !errors.Is(err, entities.ErrBatchIDRequired) {
		t.Fatalf("quiero ErrBatchIDRequired, obtuve %v", err)
	}
}

func TestIngestTelemetry_RequiresSamples(t *testing.T) {
	svc := NewService(&fakeStore{})
	_, err := svc.IngestTelemetry(context.Background(), "t", "dev-1", "b1", nil, nil)
	if !errors.Is(err, entities.ErrSamplesRequired) {
		t.Fatalf("quiero ErrSamplesRequired, obtuve %v", err)
	}
}

func TestUpsertTrip_DefaultsStatusActive(t *testing.T) {
	store := &fakeStore{tripResult: json.RawMessage(`{"trip_id":"t1"}`)}
	svc := NewService(store)

	_, err := svc.UpsertTrip(context.Background(), "tenant-1", "dev-1", "t1", entities.TripUpsert{})
	if err != nil {
		t.Fatal(err)
	}
	if store.lastStatus != "active" {
		t.Fatalf("status vacio debe ser active, obtuve %q", store.lastStatus)
	}
}

func TestUpsertTrip_RequiresTripID(t *testing.T) {
	svc := NewService(&fakeStore{})
	_, err := svc.UpsertTrip(context.Background(), "t", "dev-1", "", entities.TripUpsert{})
	if !errors.Is(err, entities.ErrTripIDRequired) {
		t.Fatalf("quiero ErrTripIDRequired, obtuve %v", err)
	}
}

func TestCloseTrip_RequiresTripID(t *testing.T) {
	svc := NewService(&fakeStore{})
	_, err := svc.CloseTrip(context.Background(), "t", "")
	if !errors.Is(err, entities.ErrTripIDRequired) {
		t.Fatalf("quiero ErrTripIDRequired, obtuve %v", err)
	}
}

func TestCloseTrip_Passthrough(t *testing.T) {
	store := &fakeStore{closeResult: json.RawMessage(`{"trip_id":"t1","point_count":42}`)}
	svc := NewService(store)
	raw, err := svc.CloseTrip(context.Background(), "tenant-1", "t1")
	if err != nil {
		t.Fatal(err)
	}
	if store.closeCalled != 1 || store.lastTenant != "tenant-1" {
		t.Fatalf("debe propagar tenant: %+v", store)
	}
	if string(raw) != `{"trip_id":"t1","point_count":42}` {
		t.Fatalf("passthrough: %s", raw)
	}
}

func TestUpsertObdSession_RequiresProtocol(t *testing.T) {
	svc := NewService(&fakeStore{})
	_, err := svc.UpsertObdSession(context.Background(), "t", "dev-1", "s1", entities.ObdSessionUpsert{})
	if !errors.Is(err, entities.ErrProtocolRequired) {
		t.Fatalf("quiero ErrProtocolRequired, obtuve %v", err)
	}
}

func TestUpsertObdSession_RequiresSessionID(t *testing.T) {
	svc := NewService(&fakeStore{})
	_, err := svc.UpsertObdSession(context.Background(), "t", "dev-1", "", entities.ObdSessionUpsert{Protocol: "can"})
	if !errors.Is(err, entities.ErrSessionIDRequired) {
		t.Fatalf("quiero ErrSessionIDRequired, obtuve %v", err)
	}
}

func TestUpsertObdSession_Passthrough(t *testing.T) {
	store := &fakeStore{obdResult: json.RawMessage(`{"session_id":"s1","created":true}`)}
	svc := NewService(store)
	_, err := svc.UpsertObdSession(context.Background(), "tenant-1", "dev-1", "s1",
		entities.ObdSessionUpsert{Protocol: "can"})
	if err != nil {
		t.Fatal(err)
	}
	if store.obdCalled != 1 || store.lastProtocol != "can" || store.lastDevice != "dev-1" {
		t.Fatalf("debe propagar device y protocolo: %+v", store)
	}
}
