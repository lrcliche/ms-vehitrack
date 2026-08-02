package repositories

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
	"ms-vehitrack/infrastructure/database"
)

// PostgresGeocodeStore implementa ports.GeocodeStore contra las rutinas de geo/public.
// geo.* es GLOBAL (sin RLS): no abre transacción con tenant. Solo CALL prc_* / SELECT fnc_*.
type PostgresGeocodeStore struct {
	pool *database.Pool
}

func NewPostgresGeocodeStore(pool *database.Pool) *PostgresGeocodeStore {
	return &PostgresGeocodeStore{pool: pool}
}

func (s *PostgresGeocodeStore) Search(
	ctx context.Context, query, municipalityID string, lat, lon *float64, limit int,
) ([]entities.GeocodeResult, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT result_kind, place_id, street_id, intersection_id, label, context,
		        lat, lon, municipality_id, confidence, geocode_resolver_id, is_verified
		   FROM geo.fnc_search_place($1, $2, $3, $4, $5)`,
		query, nullText(municipalityID), lat, lon, limit)
	if err != nil {
		return nil, fmt.Errorf("geocode search: %w", err)
	}
	defer rows.Close()

	out := make([]entities.GeocodeResult, 0)
	for rows.Next() {
		var r entities.GeocodeResult
		var muni *string
		if err := rows.Scan(
			&r.ResultKind, &r.PlaceID, &r.StreetID, &r.IntersectionID, &r.Label, &r.Context,
			&r.Lat, &r.Lon, &muni, &r.Confidence, &r.Resolver, &r.IsVerified,
		); err != nil {
			return nil, fmt.Errorf("geocode scan: %w", err)
		}
		if muni != nil {
			r.MunicipalityID = *muni
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("geocode rows: %w", err)
	}
	return out, nil
}

func (s *PostgresGeocodeStore) RecordHit(
	ctx context.Context, placeID *int64, query, municipalityID, deviceID, resolver string,
) error {
	_, err := s.pool.Exec(ctx,
		`CALL geo.prc_record_geocode_hit($1, $2, $3, $4, $5)`,
		placeID, query, nullText(municipalityID), nullText(deviceID), resolver)
	if err != nil {
		return fmt.Errorf("geocode record_hit: %w", err)
	}
	return nil
}

func (s *PostgresGeocodeStore) RecordMiss(
	ctx context.Context, deviceID, query, municipalityID string,
) error {
	_, err := s.pool.Exec(ctx,
		`CALL geo.prc_record_geocode_miss($1, $2, $3)`,
		nullText(deviceID), query, nullText(municipalityID))
	if err != nil {
		return fmt.Errorf("geocode record_miss: %w", err)
	}
	return nil
}

func (s *PostgresGeocodeStore) ResolveFromProvider(
	ctx context.Context, deviceID, query, municipalityID string, provider entities.ProviderPlace,
) (json.RawMessage, error) {
	payload, err := json.Marshal(provider)
	if err != nil {
		return nil, fmt.Errorf("%w: marshal provider: %v", ports.ErrGeocodeStoreFailed, err)
	}
	var out []byte
	// p_result es INOUT: se pasa NULL y se lee el jsonb devuelto.
	err = s.pool.QueryRow(ctx,
		`CALL geo.prc_resolve_from_provider($1, $2, $3, $4, $5)`,
		nullText(deviceID), query, nullText(municipalityID), payload, nil,
	).Scan(&out)
	if err != nil {
		return nil, fmt.Errorf("geocode resolve_from_provider: %w", err)
	}
	return out, nil
}

func (s *PostgresGeocodeStore) Reverse(
	ctx context.Context, lat, lon float64, maxDistanceM *float64,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.QueryRow(ctx,
		`SELECT geo.fnc_reverse_lookup($1, $2, $3)`, lat, lon, maxDistanceM).Scan(&out)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("geocode reverse: %w", err)
	}
	return out, nil
}

func (s *PostgresGeocodeStore) Normalize(ctx context.Context, text string) (string, error) {
	var out string
	err := s.pool.QueryRow(ctx,
		`SELECT public.fnc_expand_abbreviation(public.fnc_normalize_text($1))`, text).Scan(&out)
	if err != nil {
		return "", fmt.Errorf("geocode normalize: %w", err)
	}
	return out, nil
}

func (s *PostgresGeocodeStore) DictionaryDelta(
	ctx context.Context, sinceVersion *int,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.QueryRow(ctx,
		`SELECT public.fnc_dictionary_delta($1)`, sinceVersion).Scan(&out)
	if err != nil {
		return nil, fmt.Errorf("geocode dictionary_delta: %w", err)
	}
	return out, nil
}

// nullText convierte "" en NULL para que las rutinas reciban NULL y no cadena vacía (que en
// varios sitios significan cosas distintas: p.ej. municipality_id NULL = sin filtro).
func nullText(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
