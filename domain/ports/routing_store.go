package ports

import (
	"context"
	"encoding/json"
)

// RoutingStore es el puerto de ruteo: envuelve las rutinas del esquema routing (doc 03 §3).
// El store NO hace DML crudo; cada metodo llama a un fnc_/prc_.
//
// La cascada de POST /routes vive en application/routing (get -> osrm -> store), no aqui: el
// store solo expone las tres operaciones atomicas.
//
// GetRoute lee routing.route_cache (GLOBAL, sin RLS): corre con el pool directo. RecordHit y
// StoreRoute tocan device.device y routing.route_request (RLS): corren dentro de
// pool.WithTenantTx(tenantID) con el tenant resuelto por el middleware. Los errores VT* se
// propagan con %w sobre el error crudo para que presentationerrors.Map vea el *pgconn.PgError.
type RoutingStore interface {
	// GetRoute = routing.fnc_get_route. Devuelve el jsonb de la ruta en cache o nil (miss).
	GetRoute(ctx context.Context, waypoints json.RawMessage, profile string) (json.RawMessage, error)
	// RecordHit = routing.prc_record_route_hit. Suma el hit de una ruta servida desde cache.
	RecordHit(ctx context.Context, tenantID, deviceID string, routeCacheID int64) error
	// StoreRoute = routing.prc_store_route + re-lectura de fnc_get_route. Persiste la ruta que
	// devolvio OSRM y devuelve el jsonb de la ruta ya normalizada (con expires_at, route_cache_id).
	StoreRoute(
		ctx context.Context, tenantID, deviceID string,
		waypoints, geojson json.RawMessage, distanceM float64, durationS int,
		profile string, steps, alternatives json.RawMessage,
	) (json.RawMessage, error)
}
