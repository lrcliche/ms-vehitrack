// Package geocoding orquesta el geocoder: cascada local (PG) y solo entonces Nominatim,
// persistiendo lo que el proveedor resuelve para que la siguiente búsqueda salga de PG
// (ADR-001, doc 03 §3).
package geocoding

import (
	"context"
	"encoding/json"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

// Provider es el geocoder externo (Nominatim), detrás de una interfaz para no acoplar la
// aplicación al cliente HTTP y poder falsearlo en tests.
type Provider interface {
	Search(ctx context.Context, query, city string, limit int) ([]entities.ProviderPlace, error)
	Reverse(ctx context.Context, lat, lon float64) (*entities.ProviderPlace, error)
}

// Service implementa los casos de uso de geocoding sobre el store PG y el proveedor.
type Service struct {
	store    ports.GeocodeStore
	provider Provider
}

func NewService(store ports.GeocodeStore, provider Provider) *Service {
	return &Service{store: store, provider: provider}
}

// Autocomplete = geo.fnc_search_place y NADA MÁS. El usuario está tecleando: no se gasta un
// round-trip a Nominatim por letra (doc 03).
func (s *Service) Autocomplete(
	ctx context.Context, query, municipalityID string, lat, lon *float64, limit int,
) ([]entities.GeocodeResult, error) {
	if query == "" {
		return nil, entities.ErrGeocodeQueryRequired
	}
	return s.store.Search(ctx, query, municipalityID, lat, lon, limit)
}

// Search = la cascada completa: PG local; si 0 filas, Nominatim; y persistir el resultado.
func (s *Service) Search(
	ctx context.Context, deviceID, query, municipalityID string, lat, lon *float64, limit int,
) ([]entities.GeocodeResult, error) {
	if query == "" {
		return nil, entities.ErrGeocodeQueryRequired
	}

	results, err := s.store.Search(ctx, query, municipalityID, lat, lon, limit)
	if err != nil {
		return nil, err
	}
	if len(results) > 0 {
		// Contabiliza el acierto local del mejor resultado (placeID nil en vía/intersección
		// es no-op dentro de la rutina). Es best-effort: no tumba la respuesta.
		top := results[0]
		_ = s.store.RecordHit(ctx, top.PlaceID, query, municipalityID, deviceID, top.Resolver)
		return results, nil
	}

	// 0 filas locales -> Nominatim.
	if s.provider != nil {
		providerResults, perr := s.provider.Search(ctx, query, "", limit)
		if perr == nil && len(providerResults) > 0 {
			p := providerResults[0]
			raw, rerr := s.store.ResolveFromProvider(ctx, deviceID, query, municipalityID, p)
			if rerr != nil {
				return nil, rerr
			}
			return []entities.GeocodeResult{providerToResult(p, municipalityID, raw)}, nil
		}
	}

	// Ni PG ni Nominatim: cachear el fallo y devolver "sin resultado" (404).
	_ = s.store.RecordMiss(ctx, deviceID, query, municipalityID)
	return nil, entities.ErrGeocodeNoResult
}

// Reverse: cache/PG local y, si no hay lugar cerca, Nominatim (persistiendo).
func (s *Service) Reverse(
	ctx context.Context, deviceID string, lat, lon float64, maxDistanceM *float64,
) (json.RawMessage, error) {
	local, err := s.store.Reverse(ctx, lat, lon, maxDistanceM)
	if err != nil {
		return nil, err
	}
	if !isJSONNull(local) {
		return local, nil
	}

	if s.provider != nil {
		p, perr := s.provider.Reverse(ctx, lat, lon)
		if perr == nil && p != nil {
			if _, rerr := s.store.ResolveFromProvider(ctx, deviceID, p.Label, "", *p); rerr != nil {
				return nil, rerr
			}
			out, _ := json.Marshal(map[string]any{
				"label": p.Label, "lat": p.Lat, "lon": p.Lon, "geocode_resolver_id": "nominatim",
			})
			return out, nil
		}
	}
	return nil, entities.ErrGeocodeNoResult
}

func (s *Service) Normalize(ctx context.Context, text string) (string, error) {
	return s.store.Normalize(ctx, text)
}

func (s *Service) Dictionary(ctx context.Context, sinceVersion *int) (json.RawMessage, error) {
	return s.store.DictionaryDelta(ctx, sinceVersion)
}

func providerToResult(p entities.ProviderPlace, municipalityID string, resolveResult json.RawMessage) entities.GeocodeResult {
	conf := 0.7
	if p.Confidence != nil {
		conf = *p.Confidence
	}
	var pid *int64
	var parsed struct {
		PlaceID *int64 `json:"place_id"`
	}
	if json.Unmarshal(resolveResult, &parsed) == nil {
		pid = parsed.PlaceID
	}
	return entities.GeocodeResult{
		ResultKind:     "place",
		PlaceID:        pid,
		Label:          p.Label,
		Lat:            p.Lat,
		Lon:            p.Lon,
		MunicipalityID: municipalityID,
		Confidence:     conf,
		Resolver:       "nominatim",
	}
}

func isJSONNull(raw json.RawMessage) bool {
	if len(raw) == 0 {
		return true
	}
	for _, b := range raw {
		if b != ' ' && b != '\t' && b != '\n' && b != '\r' {
			return string(raw) == "null"
		}
	}
	return true
}
