package entities

import "errors"

// GeocodeResult es una fila de geo.fnc_search_place. result_kind ∈ {place, street,
// intersection}. Solo 'place' trae place_id; vías e intersecciones no (no se inventan
// lugares falsos para cachearlos).
type GeocodeResult struct {
	ResultKind     string   `json:"resultKind"`
	PlaceID        *int64   `json:"placeId,omitempty"`
	StreetID       *int64   `json:"streetId,omitempty"`
	IntersectionID *int64   `json:"intersectionId,omitempty"`
	Label          string   `json:"label"`
	Context        string   `json:"context"`
	Lat            float64  `json:"lat"`
	Lon            float64  `json:"lon"`
	MunicipalityID string   `json:"municipalityId"`
	Confidence     float64  `json:"confidence"`
	Resolver       string   `json:"resolver"`
	IsVerified     bool     `json:"isVerified"`
}

// ProviderPlace es el payload que se le pasa a geo.prc_resolve_from_provider tras resolver
// con Nominatim: el lugar se persiste y las siguientes búsquedas salen de PG.
type ProviderPlace struct {
	Label       string   `json:"label"`
	Lat         float64  `json:"lat"`
	Lon         float64  `json:"lon"`
	Kind        string   `json:"kind,omitempty"`
	ExternalRef string   `json:"external_ref,omitempty"`
	Confidence  *float64 `json:"confidence,omitempty"`
}

var (
	// ErrGeocodeQueryRequired = falta el texto de búsqueda.
	ErrGeocodeQueryRequired = errors.New("geocode: query requerida")
	// ErrGeocodeNoResult = ni PG ni Nominatim resolvieron (404).
	ErrGeocodeNoResult = errors.New("geocode: sin resultado")
)
