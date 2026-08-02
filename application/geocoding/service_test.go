package geocoding

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"ms-vehitrack/domain/entities"
)

// --- fakes ---------------------------------------------------------------------------

type fakeStore struct {
	searchResults []entities.GeocodeResult
	recordHit     int
	recordMiss    int
	resolved      int
	lastResolver  string
}

func (f *fakeStore) Search(context.Context, string, string, *float64, *float64, int) ([]entities.GeocodeResult, error) {
	return f.searchResults, nil
}
func (f *fakeStore) RecordHit(_ context.Context, _ *int64, _, _, _, resolver string) error {
	f.recordHit++
	f.lastResolver = resolver
	return nil
}
func (f *fakeStore) RecordMiss(context.Context, string, string, string) error {
	f.recordMiss++
	return nil
}
func (f *fakeStore) ResolveFromProvider(context.Context, string, string, string, entities.ProviderPlace) (json.RawMessage, error) {
	f.resolved++
	return json.RawMessage(`{"place_id": 42, "created": true}`), nil
}
func (f *fakeStore) Reverse(context.Context, float64, float64, *float64) (json.RawMessage, error) {
	return json.RawMessage("null"), nil
}
func (f *fakeStore) Normalize(context.Context, string) (string, error) { return "carrera 15", nil }
func (f *fakeStore) DictionaryDelta(context.Context, *int) (json.RawMessage, error) {
	return json.RawMessage(`{"version":1}`), nil
}

type fakeProvider struct {
	results []entities.ProviderPlace
	called  int
}

func (p *fakeProvider) Search(context.Context, string, string, int) ([]entities.ProviderPlace, error) {
	p.called++
	return p.results, nil
}
func (p *fakeProvider) Reverse(context.Context, float64, float64) (*entities.ProviderPlace, error) {
	return nil, nil
}

// --- tests ---------------------------------------------------------------------------

func TestSearch_LocalHit_NoProvider(t *testing.T) {
	pid := int64(7)
	store := &fakeStore{searchResults: []entities.GeocodeResult{
		{ResultKind: "place", PlaceID: &pid, Label: "Carrera 15", Resolver: "cache"},
	}}
	prov := &fakeProvider{}
	svc := NewService(store, prov)

	res, err := svc.Search(context.Background(), "dev-1", "cra 15", "co-atl-barranquilla", nil, nil, 8)
	if err != nil {
		t.Fatal(err)
	}
	if len(res) != 1 || res[0].Resolver != "cache" {
		t.Fatalf("resultado inesperado: %+v", res)
	}
	if prov.called != 0 {
		t.Fatal("no debe llamar a Nominatim si PG resolvió")
	}
	if store.recordHit != 1 || store.lastResolver != "cache" {
		t.Fatalf("debe registrar el hit local: hit=%d resolver=%s", store.recordHit, store.lastResolver)
	}
}

func TestSearch_FallbackToProvider_Persists(t *testing.T) {
	store := &fakeStore{searchResults: nil}
	prov := &fakeProvider{results: []entities.ProviderPlace{
		{Label: "Carrera 43 # 76", Lat: 10.99, Lon: -74.8, ExternalRef: "W1"},
	}}
	svc := NewService(store, prov)

	res, err := svc.Search(context.Background(), "dev-1", "cra 43 76", "co-atl-barranquilla", nil, nil, 8)
	if err != nil {
		t.Fatal(err)
	}
	if prov.called != 1 || store.resolved != 1 {
		t.Fatalf("debe llamar y persistir: called=%d resolved=%d", prov.called, store.resolved)
	}
	if len(res) != 1 || res[0].PlaceID == nil || *res[0].PlaceID != 42 {
		t.Fatalf("debe devolver el place persistido (id 42): %+v", res)
	}
	if res[0].Resolver != "nominatim" {
		t.Fatalf("resolver = %s, quiero nominatim", res[0].Resolver)
	}
}

func TestSearch_NoResultAnywhere_RecordsMiss(t *testing.T) {
	store := &fakeStore{searchResults: nil}
	prov := &fakeProvider{results: nil}
	svc := NewService(store, prov)

	_, err := svc.Search(context.Background(), "dev-1", "xyz", "", nil, nil, 8)
	if !errors.Is(err, entities.ErrGeocodeNoResult) {
		t.Fatalf("quiero ErrGeocodeNoResult, obtuve %v", err)
	}
	if store.recordMiss != 1 {
		t.Fatalf("debe cachear el miss: %d", store.recordMiss)
	}
}

func TestAutocomplete_NeverHitsProvider(t *testing.T) {
	store := &fakeStore{searchResults: nil}
	prov := &fakeProvider{results: []entities.ProviderPlace{{Label: "x"}}}
	svc := NewService(store, prov)

	_, err := svc.Autocomplete(context.Background(), "cra", "", nil, nil, 8)
	if err != nil {
		t.Fatal(err)
	}
	if prov.called != 0 || store.recordMiss != 0 || store.recordHit != 0 {
		t.Fatal("autocomplete solo consulta local: ni provider, ni record")
	}
}

func TestSearch_EmptyQuery(t *testing.T) {
	svc := NewService(&fakeStore{}, &fakeProvider{})
	if _, err := svc.Search(context.Background(), "d", "", "", nil, nil, 8); !errors.Is(err, entities.ErrGeocodeQueryRequired) {
		t.Fatalf("quiero ErrGeocodeQueryRequired, obtuve %v", err)
	}
}
