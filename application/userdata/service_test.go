package userdata

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"ms-vehitrack/domain/entities"
)

// --- fake store ----------------------------------------------------------------------

type fakeStore struct {
	favorites []entities.FavoritePlace
	hits      []entities.GeofenceHit
	result    json.RawMessage // passthrough que devuelven los prc_

	lastTenantID  string
	lastDeviceID  string
	lastID        string
	lastEntity    string
	lastKey       string
	lastValue     json.RawMessage
	lastItems     json.RawMessage
	lastEnts      []string
	lastSince     *int64
	lastLimit     *int
	lastFavorite  entities.FavoriteUpsert
	lastPlace     entities.PlaceUpsert
	lastGeofence  entities.GeofenceUpsert
	registerCalls int
	provisionCall int
	lastRegister  entities.RegisterInput
}

func (f *fakeStore) ListFavorites(_ context.Context, tenantID, deviceID string, _ bool) ([]entities.FavoritePlace, error) {
	f.lastTenantID, f.lastDeviceID = tenantID, deviceID
	return f.favorites, nil
}
func (f *fakeStore) UpsertFavorite(_ context.Context, tenantID, deviceID, id string, in entities.FavoriteUpsert) (json.RawMessage, error) {
	f.lastTenantID, f.lastDeviceID, f.lastID, f.lastFavorite = tenantID, deviceID, id, in
	return f.result, nil
}
func (f *fakeStore) UpsertPlace(_ context.Context, tenantID, deviceID, id string, in entities.PlaceUpsert) (json.RawMessage, error) {
	f.lastTenantID, f.lastDeviceID, f.lastID, f.lastPlace = tenantID, deviceID, id, in
	return f.result, nil
}
func (f *fakeStore) UpsertGeofence(_ context.Context, tenantID, deviceID, id string, in entities.GeofenceUpsert) (json.RawMessage, error) {
	f.lastTenantID, f.lastDeviceID, f.lastID, f.lastGeofence = tenantID, deviceID, id, in
	return f.result, nil
}
func (f *fakeStore) UpsertSetting(_ context.Context, tenantID, deviceID, key string, value json.RawMessage) (json.RawMessage, error) {
	f.lastTenantID, f.lastDeviceID, f.lastKey, f.lastValue = tenantID, deviceID, key, value
	return f.result, nil
}
func (f *fakeStore) SoftDelete(_ context.Context, tenantID, deviceID, entity, id string) (json.RawMessage, error) {
	f.lastTenantID, f.lastDeviceID, f.lastEntity, f.lastID = tenantID, deviceID, entity, id
	return f.result, nil
}
func (f *fakeStore) RecordGeofenceEvent(_ context.Context, tenantID, deviceID string, _ entities.GeofenceEventInput) (json.RawMessage, error) {
	f.lastTenantID, f.lastDeviceID = tenantID, deviceID
	return f.result, nil
}
func (f *fakeStore) EvaluateGeofence(_ context.Context, tenantID, deviceID string, _ json.RawMessage) ([]entities.GeofenceHit, error) {
	f.lastTenantID, f.lastDeviceID = tenantID, deviceID
	return f.hits, nil
}
func (f *fakeStore) SyncChanges(_ context.Context, tenantID, deviceID string, ents []string, since *int64, limit *int) (json.RawMessage, error) {
	f.lastTenantID, f.lastDeviceID, f.lastEnts, f.lastSince, f.lastLimit = tenantID, deviceID, ents, since, limit
	return f.result, nil
}
func (f *fakeStore) SyncPush(_ context.Context, tenantID, deviceID string, items json.RawMessage) (json.RawMessage, error) {
	f.lastTenantID, f.lastDeviceID, f.lastItems = tenantID, deviceID, items
	return f.result, nil
}
func (f *fakeStore) RegisterDevice(_ context.Context, in entities.RegisterInput) (json.RawMessage, error) {
	f.registerCalls++
	f.lastRegister = in
	return f.result, nil
}
func (f *fakeStore) ProvisionPersonal(_ context.Context, in entities.RegisterInput) (json.RawMessage, error) {
	f.provisionCall++
	f.lastRegister = in
	return f.result, nil
}

func strptr(s string) *string { return &s }

// --- sync passthrough ----------------------------------------------------------------

func TestSyncChanges_Passthrough(t *testing.T) {
	store := &fakeStore{result: json.RawMessage(`{"next_version":42,"has_more":false,"entities":{}}`)}
	svc := NewService(store)

	since := int64(10)
	limit := 100
	raw, err := svc.SyncChanges(context.Background(), "t-1", "dev-1",
		[]string{"favorite_place", "geofence"}, &since, &limit)
	if err != nil {
		t.Fatal(err)
	}
	if string(raw) != string(store.result) {
		t.Fatalf("changes debe ser passthrough del jsonb: %s", raw)
	}
	if store.lastTenantID != "t-1" || store.lastDeviceID != "dev-1" {
		t.Fatalf("debe propagar tenant y device: %+v", store)
	}
	if len(store.lastEnts) != 2 || store.lastSince == nil || *store.lastSince != 10 || store.lastLimit == nil || *store.lastLimit != 100 {
		t.Fatalf("debe propagar entities/since/limit tal cual: %+v", store)
	}
}

func TestSyncChanges_RequiresDevice(t *testing.T) {
	svc := NewService(&fakeStore{})
	if _, err := svc.SyncChanges(context.Background(), "t-1", "", nil, nil, nil); !errors.Is(err, entities.ErrDeviceIDRequired) {
		t.Fatalf("quiero ErrDeviceIDRequired, obtuve %v", err)
	}
}

func TestSyncPush_Passthrough(t *testing.T) {
	store := &fakeStore{result: json.RawMessage(`{"applied":3,"skipped":0,"failed":[],"next_version":99}`)}
	svc := NewService(store)

	items := json.RawMessage(`[{"entity":"favorite_place","op":"upsert","id":"x"}]`)
	raw, err := svc.SyncPush(context.Background(), "t-1", "dev-1", items)
	if err != nil {
		t.Fatal(err)
	}
	if string(raw) != string(store.result) {
		t.Fatalf("push debe ser passthrough del jsonb: %s", raw)
	}
	if string(store.lastItems) != string(items) {
		t.Fatalf("items deben viajar tal cual al store: %s", store.lastItems)
	}
}

func TestSyncPush_RejectsEmptyItems(t *testing.T) {
	svc := NewService(&fakeStore{})
	for _, empty := range []json.RawMessage{nil, json.RawMessage("null")} {
		if _, err := svc.SyncPush(context.Background(), "t-1", "dev-1", empty); !errors.Is(err, entities.ErrSyncItemsRequired) {
			t.Fatalf("items vacios (%q) deben rechazarse, obtuve %v", empty, err)
		}
	}
}

// --- soft-delete routing -------------------------------------------------------------

func TestDeleteFavorite_RoutesEntity(t *testing.T) {
	store := &fakeStore{result: json.RawMessage(`{"deleted":true}`)}
	svc := NewService(store)

	if _, err := svc.SoftDelete(context.Background(), "t-1", "dev-1", "favorite_place", "fav-1"); err != nil {
		t.Fatal(err)
	}
	if store.lastEntity != "favorite_place" || store.lastID != "fav-1" {
		t.Fatalf("debe enrutar entidad e id al store: %+v", store)
	}
}

func TestSoftDelete_RejectsUnknownEntity(t *testing.T) {
	svc := NewService(&fakeStore{})
	if _, err := svc.SoftDelete(context.Background(), "t-1", "dev-1", "not_a_thing", "x"); !errors.Is(err, entities.ErrEntityRequired) {
		t.Fatalf("entidad desconocida debe rechazarse antes de la BD, obtuve %v", err)
	}
}

func TestSoftDelete_RequiresID(t *testing.T) {
	svc := NewService(&fakeStore{})
	if _, err := svc.SoftDelete(context.Background(), "t-1", "dev-1", "geofence", ""); !errors.Is(err, entities.ErrIDRequired) {
		t.Fatalf("quiero ErrIDRequired, obtuve %v", err)
	}
}

// --- upsert defaults + validation ----------------------------------------------------

func TestUpsertFavorite_DefaultsKind(t *testing.T) {
	store := &fakeStore{result: json.RawMessage(`{"applied":true}`)}
	svc := NewService(store)

	if _, err := svc.UpsertFavorite(context.Background(), "t-1", "dev-1", "fav-1",
		entities.FavoriteUpsert{Label: "Casa"}); err != nil {
		t.Fatal(err)
	}
	if store.lastFavorite.Kind != "custom" {
		t.Fatalf("kind vacio debe caer a custom, obtuve %q", store.lastFavorite.Kind)
	}
	if store.lastID != "fav-1" {
		t.Fatalf("id de la URL debe llegar al store: %q", store.lastID)
	}
}

func TestUpsertFavorite_RequiresID(t *testing.T) {
	svc := NewService(&fakeStore{})
	if _, err := svc.UpsertFavorite(context.Background(), "t-1", "dev-1", "",
		entities.FavoriteUpsert{Label: "x"}); !errors.Is(err, entities.ErrIDRequired) {
		t.Fatalf("quiero ErrIDRequired, obtuve %v", err)
	}
}

func TestUpsertGeofence_RequiresWKTAndDefaults(t *testing.T) {
	store := &fakeStore{result: json.RawMessage(`{"applied":true}`)}
	svc := NewService(store)

	if _, err := svc.UpsertGeofence(context.Background(), "t-1", "dev-1", "g-1",
		entities.GeofenceUpsert{Name: "Zona"}); !errors.Is(err, entities.ErrGeofenceWKTRequired) {
		t.Fatalf("sin WKT debe rechazarse, obtuve %v", err)
	}

	if _, err := svc.UpsertGeofence(context.Background(), "t-1", "dev-1", "g-1",
		entities.GeofenceUpsert{Name: "Zona", GeomWKT: "POINT(-74 11)"}); err != nil {
		t.Fatal(err)
	}
	if store.lastGeofence.Shape != "circle" || store.lastGeofence.Trigger != "both" {
		t.Fatalf("shape/trigger vacios deben caer a circle/both: %+v", store.lastGeofence)
	}
}

func TestUpsertSetting_RejectsEmptyValue(t *testing.T) {
	svc := NewService(&fakeStore{})
	if _, err := svc.UpsertSetting(context.Background(), "t-1", "dev-1", "fuel.price", nil); !errors.Is(err, entities.ErrSettingValueRequired) {
		t.Fatalf("value vacio debe rechazarse, obtuve %v", err)
	}
	if _, err := svc.UpsertSetting(context.Background(), "t-1", "dev-1", "", json.RawMessage(`1`)); !errors.Is(err, entities.ErrSettingKeyRequired) {
		t.Fatalf("key vacia debe rechazarse, obtuve %v", err)
	}
}

// --- register routing: personal vs fleet ---------------------------------------------

func TestRegister_FleetWhenTenant(t *testing.T) {
	store := &fakeStore{result: json.RawMessage(`{"device_id":"d","tenant_id":"t","created":true}`)}
	svc := NewService(store)

	_, err := svc.Register(context.Background(), entities.RegisterInput{
		DeviceID: "dev-1", TenantID: strptr("tenant-fleet"), InstallID: strptr("i-1"),
	})
	if err != nil {
		t.Fatal(err)
	}
	if store.registerCalls != 1 || store.provisionCall != 0 {
		t.Fatalf("con tenantId debe ir a RegisterDevice (fleet): reg=%d prov=%d", store.registerCalls, store.provisionCall)
	}
}

func TestRegister_PersonalWhenInstallOnly(t *testing.T) {
	store := &fakeStore{result: json.RawMessage(`{"tenant_id":"t","device_id":"d","created":true}`)}
	svc := NewService(store)

	_, err := svc.Register(context.Background(), entities.RegisterInput{
		DeviceID: "dev-1", InstallID: strptr("install-abc"),
	})
	if err != nil {
		t.Fatal(err)
	}
	if store.provisionCall != 1 || store.registerCalls != 0 {
		t.Fatalf("solo con installId debe ir a ProvisionPersonal: reg=%d prov=%d", store.registerCalls, store.provisionCall)
	}
}

func TestRegister_AmbiguousWithoutEither(t *testing.T) {
	svc := NewService(&fakeStore{})
	if _, err := svc.Register(context.Background(), entities.RegisterInput{DeviceID: "dev-1"}); !errors.Is(err, entities.ErrRegisterAmbiguous) {
		t.Fatalf("sin tenantId ni installId debe ser ambiguo, obtuve %v", err)
	}
}

func TestRegister_RequiresDeviceID(t *testing.T) {
	svc := NewService(&fakeStore{})
	if _, err := svc.Register(context.Background(), entities.RegisterInput{InstallID: strptr("i")}); !errors.Is(err, entities.ErrIDRequired) {
		t.Fatalf("sin deviceId debe rechazarse, obtuve %v", err)
	}
}
