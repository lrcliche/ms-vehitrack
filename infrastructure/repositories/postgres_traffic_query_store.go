package repositories

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/infrastructure/database"
)

// PostgresTrafficQueryStore implementa ports.TrafficQueryStore contra las funciones de lectura
// de trafico por bbox. Estas tablas son GLOBALES (sin RLS): usan el pool directo, sin tenant.
//
// La geometria se devuelve como GeoJSON: se reemplaza la columna geom (PostGIS) por
// ST_AsGeoJSON(geom) y se agrega todo a un unico jsonb array, para que el ms haga passthrough
// sin escanear geometrias columna a columna.
type PostgresTrafficQueryStore struct {
	pool *database.Pool
}

func NewPostgresTrafficQueryStore(pool *database.Pool) *PostgresTrafficQueryStore {
	return &PostgresTrafficQueryStore{pool: pool}
}

// LiveByBBox = traffic.fnc_live_by_bbox (GLOBAL). Devuelve un jsonb array (o [] si no hay filas).
func (s *PostgresTrafficQueryStore) LiveByBBox(
	ctx context.Context, bbox entities.BBox, minDeviceCount *int,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.QueryRow(ctx,
		`SELECT COALESCE(jsonb_agg(
		          to_jsonb(t) - 'geom'
		          || jsonb_build_object('geom', ST_AsGeoJSON(t.geom)::jsonb)
		        ), '[]'::jsonb)
		   FROM traffic.fnc_live_by_bbox($1, $2, $3, $4, $5) t`,
		bbox.MinLon, bbox.MinLat, bbox.MaxLon, bbox.MaxLat, minDeviceCount).Scan(&out)
	if err != nil {
		return nil, fmt.Errorf("traffic live_by_bbox: %w", err)
	}
	return out, nil
}

// ProfileByBBox = traffic.fnc_profile_by_bbox (GLOBAL). at nil -> now() vía COALESCE (la funcion
// deriva day_kind y time_slot del instante). Devuelve un jsonb array (o []).
func (s *PostgresTrafficQueryStore) ProfileByBBox(
	ctx context.Context, bbox entities.BBox, at *time.Time, minDeviceCount *int,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.QueryRow(ctx,
		`SELECT COALESCE(jsonb_agg(
		          to_jsonb(t) - 'geom'
		          || jsonb_build_object('geom', ST_AsGeoJSON(t.geom)::jsonb)
		        ), '[]'::jsonb)
		   FROM traffic.fnc_profile_by_bbox($1, $2, $3, $4, COALESCE($5::timestamptz, now()), $6) t`,
		bbox.MinLon, bbox.MinLat, bbox.MaxLon, bbox.MaxLat, at, minDeviceCount).Scan(&out)
	if err != nil {
		return nil, fmt.Errorf("traffic profile_by_bbox: %w", err)
	}
	return out, nil
}
