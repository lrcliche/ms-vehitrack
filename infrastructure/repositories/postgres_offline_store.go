package repositories

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/infrastructure/database"
)

// PostgresOfflineStore implementa ports.OfflineStore contra las rutinas de offline/device.
//
// offline.* es GLOBAL (sin RLS): Manifest y RegionsForRoute usan el pool directo. device.* es
// TENANT-SCOPED (device.device_package tiene RLS): ListInstalled y TrackPackage corren dentro
// de pool.WithTenantTx, que abre una transacción y fija app.tenant_id con set_config(...,true)
// antes de llamar a la rutina. El tenantID lo resuelve el middleware TenantContext y llega por
// parámetro; el store nunca lo inventa.
//
// Los errores se envuelven con %w sobre el error crudo para NO romper la cadena: así
// presentationerrors.Map (errors.As) sigue viendo el *pgconn.PgError con SQLSTATE VT* y lo
// traduce al HTTP correcto (VT070→503, VT041→404, VT074→400).
type PostgresOfflineStore struct {
	pool *database.Pool
}

func NewPostgresOfflineStore(pool *database.Pool) *PostgresOfflineStore {
	return &PostgresOfflineStore{pool: pool}
}

// Manifest = offline.fnc_region_manifest (GLOBAL). Devuelve el jsonb tal cual (passthrough).
func (s *PostgresOfflineStore) Manifest(
	ctx context.Context, regionID string, installedVersion *int,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.QueryRow(ctx,
		`SELECT offline.fnc_region_manifest($1, $2)`, regionID, installedVersion).Scan(&out)
	if err != nil {
		return nil, fmt.Errorf("offline manifest: %w", err)
	}
	return out, nil
}

// RegionsForRoute = offline.fnc_regions_for_route (GLOBAL). SETOF filas.
func (s *PostgresOfflineStore) RegionsForRoute(
	ctx context.Context, routeGeojson json.RawMessage,
) ([]entities.RegionForRoute, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT region_id, name, current_version, size_bytes
		   FROM offline.fnc_regions_for_route($1)`, routeGeojson)
	if err != nil {
		return nil, fmt.Errorf("offline regions_for_route: %w", err)
	}
	defer rows.Close()

	out := make([]entities.RegionForRoute, 0)
	for rows.Next() {
		var r entities.RegionForRoute
		if err := rows.Scan(&r.RegionID, &r.Name, &r.CurrentVersion, &r.SizeBytes); err != nil {
			return nil, fmt.Errorf("offline regions_for_route scan: %w", err)
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("offline regions_for_route rows: %w", err)
	}
	return out, nil
}

// ListInstalled = device.fnc_list_device_package (TENANT-SCOPED): corre dentro de la
// transacción con app.tenant_id fijado.
func (s *PostgresOfflineStore) ListInstalled(
	ctx context.Context, tenantID, deviceID string,
) ([]entities.DevicePackage, error) {
	var out []entities.DevicePackage
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			`SELECT region_id, name, installed_version, current_version,
			        update_available, size_bytes, last_used_at, is_protected
			   FROM device.fnc_list_device_package($1)`, deviceID)
		if err != nil {
			return err
		}
		defer rows.Close()

		list := make([]entities.DevicePackage, 0)
		for rows.Next() {
			var d entities.DevicePackage
			if err := rows.Scan(
				&d.RegionID, &d.Name, &d.InstalledVersion, &d.CurrentVersion,
				&d.UpdateAvailable, &d.SizeBytes, &d.LastUsedAt, &d.IsProtected,
			); err != nil {
				return err
			}
			list = append(list, d)
		}
		if err := rows.Err(); err != nil {
			return err
		}
		out = list
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("offline list_device_package: %w", err)
	}
	return out, nil
}

// TrackPackage = device.prc_track_device_package (TENANT-SCOPED, INOUT p_result). Se pasa NULL
// en p_result y se lee el jsonb devuelto, dentro de la transacción con tenant.
func (s *PostgresOfflineStore) TrackPackage(
	ctx context.Context, tenantID, deviceID, regionID, operation string,
	version *int, sizeBytes *int64, isProtected *bool,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL device.prc_track_device_package($1, $2, $3, $4, $5, $6, $7)`,
			deviceID, regionID, operation, version, sizeBytes, isProtected, nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("offline track_device_package: %w", err)
	}
	return out, nil
}
