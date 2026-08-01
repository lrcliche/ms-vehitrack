package ports

import (
	"context"
	"encoding/json"
	"errors"

	"ms-vehitrack/domain/entities"
)

// ErrGeocodeStoreFailed = fallo de infraestructura al hablar con PG (distinto de "sin
// resultado", que no es error).
var ErrGeocodeStoreFailed = errors.New("geocode store failed")

// GeocodeStore es el puerto del conocimiento geográfico en PG. Cada método envuelve UNA
// rutina fnc_/prc_ (doc 03): el store no hace DML crudo. geo.* es global (sin tenant), así
// que estos métodos no abren transacción con tenant; el device_id viaja explícito donde la
// rutina lo pide, para auditoría y ranking.
type GeocodeStore interface {
	// Search = geo.fnc_search_place. Cero filas NO es error (devuelve slice vacío).
	Search(ctx context.Context, query, municipalityID string, lat, lon *float64, limit int) ([]entities.GeocodeResult, error)
	// RecordHit = geo.prc_record_geocode_hit. placeID nil en vía/intersección (no cachea).
	RecordHit(ctx context.Context, placeID *int64, query, municipalityID, deviceID, resolver string) error
	// RecordMiss = geo.prc_record_geocode_miss (cachea el fallo con TTL corto).
	RecordMiss(ctx context.Context, deviceID, query, municipalityID string) error
	// ResolveFromProvider = geo.prc_resolve_from_provider (persiste lo que resolvió Nominatim).
	ResolveFromProvider(ctx context.Context, deviceID, query, municipalityID string, provider entities.ProviderPlace) (json.RawMessage, error)
	// Reverse = geo.fnc_reverse_lookup. Devuelve null (json 'null') si no hay lugar cerca.
	Reverse(ctx context.Context, lat, lon float64, maxDistanceM *float64) (json.RawMessage, error)
	// Normalize = public.fnc_expand_abbreviation(public.fnc_normalize_text(...)).
	Normalize(ctx context.Context, text string) (string, error)
	// DictionaryDelta = public.fnc_dictionary_delta. since nil = diccionario completo.
	DictionaryDelta(ctx context.Context, sinceVersion *int) (json.RawMessage, error)
}
