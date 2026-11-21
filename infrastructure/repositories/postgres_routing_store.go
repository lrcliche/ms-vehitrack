package repositories

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"

	"ms-vehitrack/infrastructure/database"
)

// PostgresRoutingStore implementa ports.RoutingStore contra las rutinas del esquema routing.
//
// routing.route_cache es GLOBAL (sin RLS): GetRoute usa el pool directo. RecordHit y StoreRoute
// tocan device.device y routing.route_request (con RLS), asi que corren dentro de
// pool.WithTenantTx(tenantID), que fija app.tenant_id con set_config(...,true) antes de la
// rutina. El tenantID lo resuelve el middleware TenantContext y llega por parametro; el store
// nunca lo inventa.
//
// Los errores se envuelven con %w sobre el error crudo para NO romper la cadena: asi
// presentationerrors.Map (errors.As) sigue viendo el *pgconn.PgError con SQLSTATE VT* (VT041,
// VT060, VT061, VT062) y lo traduce al HTTP correcto.
type PostgresRoutingStore struct {
	pool *database.Pool
}

func NewPostgresRoutingStore(pool *database.Pool) *PostgresRoutingStore {
	return &PostgresRoutingStore{pool: pool}
}

// GetRoute = routing.fnc_get_route (GLOBAL). Devuelve el jsonb de la ruta vigente en cache o
// nil cuando no hay hit (la funcion devuelve NULL). Passthrough del jsonb.
func (s *PostgresRoutingStore) GetRoute(
	ctx context.Context, waypoints json.RawMessage, profile string,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.QueryRow(ctx,
		`SELECT routing.fnc_get_route($1, $2)`, []byte(waypoints), profile).Scan(&out)
	if err != nil {
		return nil, fmt.Errorf("routing get_route: %w", err)
	}
	if out == nil {
		return nil, nil
	}
	return out, nil
}

// RecordHit = routing.prc_record_route_hit (TENANT-SCOPED). Registra el hit de cache.
func (s *PostgresRoutingStore) RecordHit(
	ctx context.Context, tenantID, deviceID string, routeCacheID int64,
) error {
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			`CALL routing.prc_record_route_hit($1, $2)`, deviceID, routeCacheID)
		return err
	})
	if err != nil {
		return fmt.Errorf("routing record_route_hit: %w", err)
	}
	return nil
}

func (s *PostgresRoutingStore) RecordUserHit(
	ctx context.Context, tenantID, userID, tenantUserID string, routeCacheID int64,
) error {
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			`CALL routing.prc_record_business_route_hit($1,$2,$3,$4)`,
			tenantID, userID, tenantUserID, routeCacheID)
		return err
	})
	if err != nil {
		return fmt.Errorf("routing record business route hit: %w", err)
	}
	return nil
}

// StoreRoute = routing.prc_store_route (TENANT-SCOPED, INOUT p_result) + re-lectura de
// routing.fnc_get_route dentro de la MISMA transaccion, para devolver la ruta ya normalizada
// (route_cache_id, geojson, distance_m, duration_s, steps, expires_at). prc_store_route solo
// devuelve {route_cache_id, waypoints_hash}, por eso se relee.
func (s *PostgresRoutingStore) StoreRoute(
	ctx context.Context, tenantID, deviceID string,
	waypoints, geojson json.RawMessage, distanceM float64, durationS int,
	profile string, steps, alternatives json.RawMessage,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx,
			`CALL routing.prc_store_route($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
			deviceID, []byte(waypoints), []byte(geojson), distanceM, durationS, profile,
			nullJSON(steps), nullJSON(alternatives), nil,
		); err != nil {
			return err
		}
		return tx.QueryRow(ctx,
			`SELECT routing.fnc_get_route($1, $2)`, []byte(waypoints), profile).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("routing store_route: %w", err)
	}
	return out, nil
}

func (s *PostgresRoutingStore) StoreUserRoute(
	ctx context.Context, tenantID, userID, tenantUserID string,
	waypoints, geojson json.RawMessage, distanceM float64, durationS int,
	profile string, steps, alternatives json.RawMessage,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx,
			`CALL routing.prc_store_business_route($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
			tenantID, userID, tenantUserID, []byte(waypoints), []byte(geojson), distanceM, durationS, profile,
			nullJSON(steps), nullJSON(alternatives), nil,
		); err != nil {
			return err
		}
		return tx.QueryRow(ctx,
			`SELECT routing.fnc_get_route($1, $2)`, []byte(waypoints), profile).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("routing store business route: %w", err)
	}
	return out, nil
}

// nullJSON pasa nil (=> SQL NULL) cuando el jsonb esta vacio o es "null", para que las rutinas
// reciban NULL y no un jsonb invalido.
func nullJSON(raw json.RawMessage) []byte {
	if len(raw) == 0 || string(raw) == "null" {
		return nil
	}
	return []byte(raw)
}
