package trafficquery

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"ms-vehitrack/domain/entities"
)

// --- fake store ----------------------------------------------------------------------

type fakeStore struct {
	liveResult    json.RawMessage
	profileResult json.RawMessage
	lastBBox      entities.BBox
	lastMinDev    *int
	lastAt        *time.Time
}

func (f *fakeStore) LiveByBBox(_ context.Context, bbox entities.BBox, minDev *int) (json.RawMessage, error) {
	f.lastBBox = bbox
	f.lastMinDev = minDev
	return f.liveResult, nil
}
func (f *fakeStore) ProfileByBBox(_ context.Context, bbox entities.BBox, at *time.Time, minDev *int) (json.RawMessage, error) {
	f.lastBBox = bbox
	f.lastAt = at
	f.lastMinDev = minDev
	return f.profileResult, nil
}

// --- tests ---------------------------------------------------------------------------

func TestLive_Passthrough(t *testing.T) {
	store := &fakeStore{liveResult: json.RawMessage(`[{"traffic_link_id":1}]`)}
	svc := NewService(store)
	bbox := entities.BBox{MinLon: -74.9, MinLat: 10.9, MaxLon: -74.7, MaxLat: 11.1}

	raw, err := svc.Live(context.Background(), bbox, nil)
	if err != nil {
		t.Fatal(err)
	}
	if string(raw) != `[{"traffic_link_id":1}]` {
		t.Fatalf("passthrough del jsonb: %s", raw)
	}
	if store.lastBBox != bbox {
		t.Fatalf("debe propagar el bbox: %+v", store.lastBBox)
	}
}

func TestProfile_PassesAt(t *testing.T) {
	store := &fakeStore{profileResult: json.RawMessage(`[]`)}
	svc := NewService(store)
	at := time.Date(2026, 8, 2, 8, 30, 0, 0, time.UTC)
	bbox := entities.BBox{MinLon: -74.9, MinLat: 10.9, MaxLon: -74.7, MaxLat: 11.1}

	if _, err := svc.Profile(context.Background(), bbox, &at, nil); err != nil {
		t.Fatal(err)
	}
	if store.lastAt == nil || !store.lastAt.Equal(at) {
		t.Fatalf("debe propagar at: %+v", store.lastAt)
	}
}

func TestParseBBox_Valid(t *testing.T) {
	b, err := entities.ParseBBox("-74.9,10.9,-74.7,11.1")
	if err != nil {
		t.Fatal(err)
	}
	if b.MinLon != -74.9 || b.MaxLat != 11.1 {
		t.Fatalf("parseo incorrecto: %+v", b)
	}
}

func TestParseBBox_Invalid(t *testing.T) {
	cases := []string{"", "1,2,3", "a,b,c,d", "10,10,5,20"}
	for _, raw := range cases {
		if _, err := entities.ParseBBox(raw); err == nil {
			t.Fatalf("esperaba error para %q", raw)
		}
	}
}
