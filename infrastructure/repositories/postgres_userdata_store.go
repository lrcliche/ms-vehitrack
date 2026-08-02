package repositories

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/infrastructure/database"
)

// PostgresUserDataStore implementa ports.UserDataStore contra las rutinas del esquema device.
//
// La regla de aislamiento es la misma del resto del modelo PG: device.* lleva RLS, asi que
// cada escritura/lectura corre dentro de pool.WithTenantTx(tenantID) — el store nunca inventa
// el tenant, lo recibe del middleware. La UNICA excepcion es ProvisionPersonal: el tenant aun
// no existe, asi que corre con el pool directo contra prc_provision_personal_tenant (SECURITY
// DEFINER). RegisterDevice (fleet) SI lleva tenant: el body trae el tenant destino.
//
// Los errores se envuelven con %w sobre el error crudo para NO romper la cadena: asi
// presentationerrors.Map (errors.As) sigue viendo el *pgconn.PgError con SQLSTATE VT* (VT041,
// VT042, VT044, VT048, VT049, VT050, VT051...) y lo traduce al HTTP correcto.
type PostgresUserDataStore struct {
	pool *database.Pool
}

func NewPostgresUserDataStore(pool *database.Pool) *PostgresUserDataStore {
	return &PostgresUserDataStore{pool: pool}
}

// ListFavorites = device.fnc_list_favorite_place (TENANT-SCOPED).
func (s *PostgresUserDataStore) ListFavorites(
	ctx context.Context, tenantID, deviceID string, includeDeleted bool,
) ([]entities.FavoritePlace, error) {
	var out []entities.FavoritePlace
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			`SELECT id, favorite_kind_id, label, description, icon, color_hex,
			        lat, lon, place_id, visit_count, last_visited_at,
			        updated_at, deleted_at, sync_version
			   FROM device.fnc_list_favorite_place($1, $2)`, deviceID, includeDeleted)
		if err != nil {
			return err
		}
		defer rows.Close()

		list := make([]entities.FavoritePlace, 0)
		for rows.Next() {
			var f entities.FavoritePlace
			if err := rows.Scan(
				&f.ID, &f.FavoriteKindID, &f.Label, &f.Description, &f.Icon, &f.ColorHex,
				&f.Lat, &f.Lon, &f.PlaceID, &f.VisitCount, &f.LastVisitedAt,
				&f.UpdatedAt, &f.DeletedAt, &f.SyncVersion,
			); err != nil {
				return err
			}
			list = append(list, f)
		}
		if err := rows.Err(); err != nil {
			return err
		}
		out = list
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("userdata list_favorite_place: %w", err)
	}
	return out, nil
}

// UpsertFavorite = device.prc_upsert_favorite_place (TENANT-SCOPED, INOUT p_result).
func (s *PostgresUserDataStore) UpsertFavorite(
	ctx context.Context, tenantID, deviceID, id string, in entities.FavoriteUpsert,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL device.prc_upsert_favorite_place($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
			id, deviceID, in.Label, in.Lat, in.Lon, in.Kind, in.Description, in.Icon,
			in.ColorHex, in.PlaceID, in.ClientUpdatedAt, nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("userdata upsert_favorite_place: %w", err)
	}
	return out, nil
}

// UpsertPlace = device.prc_upsert_place_user (TENANT-SCOPED, INOUT p_result).
func (s *PostgresUserDataStore) UpsertPlace(
	ctx context.Context, tenantID, deviceID, id string, in entities.PlaceUpsert,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL device.prc_upsert_place_user($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
			id, deviceID, in.Name, in.Lat, in.Lon, in.CategoryID, in.Description,
			in.ClientUpdatedAt, nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("userdata upsert_place_user: %w", err)
	}
	return out, nil
}

// UpsertGeofence = device.prc_upsert_geofence (TENANT-SCOPED, INOUT p_result).
func (s *PostgresUserDataStore) UpsertGeofence(
	ctx context.Context, tenantID, deviceID, id string, in entities.GeofenceUpsert,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL device.prc_upsert_geofence($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
			id, deviceID, in.Name, in.GeomWKT, in.Shape, in.RadiusM, in.Trigger,
			in.CooldownS, in.IsActive, in.ClientUpdatedAt, nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("userdata upsert_geofence: %w", err)
	}
	return out, nil
}

// UpsertSetting = device.prc_upsert_setting (TENANT-SCOPED, INOUT p_result).
func (s *PostgresUserDataStore) UpsertSetting(
	ctx context.Context, tenantID, deviceID, key string, value json.RawMessage,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL device.prc_upsert_setting($1,$2,$3,$4)`,
			deviceID, key, []byte(value), nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("userdata upsert_setting: %w", err)
	}
	return out, nil
}

// SoftDelete = device.prc_soft_delete (TENANT-SCOPED, INOUT p_result).
func (s *PostgresUserDataStore) SoftDelete(
	ctx context.Context, tenantID, deviceID, entity, id string,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL device.prc_soft_delete($1,$2,$3,$4)`,
			entity, id, deviceID, nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("userdata soft_delete: %w", err)
	}
	return out, nil
}

// RecordGeofenceEvent = device.prc_record_geofence_event (TENANT-SCOPED, INOUT p_result).
func (s *PostgresUserDataStore) RecordGeofenceEvent(
	ctx context.Context, tenantID, deviceID string, in entities.GeofenceEventInput,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL device.prc_record_geofence_event($1,$2,$3,$4,$5,$6,$7,$8)`,
			deviceID, in.GeofenceID, in.Trigger, in.Lat, in.Lon, in.OccurredAt, in.TripID, nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("userdata record_geofence_event: %w", err)
	}
	return out, nil
}

// EvaluateGeofence = device.fnc_evaluate_geofence (TENANT-SCOPED). SETOF filas.
func (s *PostgresUserDataStore) EvaluateGeofence(
	ctx context.Context, tenantID, deviceID string, points json.RawMessage,
) ([]entities.GeofenceHit, error) {
	var out []entities.GeofenceHit
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			`SELECT geofence_id, name, trigger_id, occurred_at
			   FROM device.fnc_evaluate_geofence($1, $2)`, deviceID, []byte(points))
		if err != nil {
			return err
		}
		defer rows.Close()

		list := make([]entities.GeofenceHit, 0)
		for rows.Next() {
			var h entities.GeofenceHit
			if err := rows.Scan(&h.GeofenceID, &h.Name, &h.TriggerID, &h.OccurredAt); err != nil {
				return err
			}
			list = append(list, h)
		}
		if err := rows.Err(); err != nil {
			return err
		}
		out = list
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("userdata evaluate_geofence: %w", err)
	}
	return out, nil
}

// SyncChanges = device.fnc_sync_changes (TENANT-SCOPED). Devuelve el jsonb tal cual. entities
// nil = todas; since nil = desde 0; limit nil = tope de app_setting.
func (s *PostgresUserDataStore) SyncChanges(
	ctx context.Context, tenantID, deviceID string, ents []string, since *int64, limit *int,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT device.fnc_sync_changes($1, $2, $3, $4)`,
			deviceID, nullTextSlice(ents), since, limit,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("userdata sync_changes: %w", err)
	}
	return out, nil
}

// SyncPush = device.prc_sync_push (TENANT-SCOPED, INOUT p_result). Devuelve el jsonb tal cual.
func (s *PostgresUserDataStore) SyncPush(
	ctx context.Context, tenantID, deviceID string, items json.RawMessage,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL device.prc_sync_push($1, $2, $3)`,
			deviceID, []byte(items), nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("userdata sync_push: %w", err)
	}
	return out, nil
}

// RegisterDevice = device.prc_register_device (FLEET, CON tenant). Corre dentro de
// WithTenantTx con el tenant destino que trae el body: la rutina esta sujeta a RLS.
func (s *PostgresUserDataStore) RegisterDevice(
	ctx context.Context, in entities.RegisterInput,
) (json.RawMessage, error) {
	tenantID := ""
	if in.TenantID != nil {
		tenantID = *in.TenantID
	}
	var out []byte
	err := s.pool.WithTenantTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`CALL device.prc_register_device($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
			in.DeviceID, in.TenantID, in.InstallID, in.Platform, in.AccountID,
			in.OSVersion, in.AppVersion, in.Model, nil,
		).Scan(&out)
	})
	if err != nil {
		return nil, fmt.Errorf("userdata register_device: %w", err)
	}
	return out, nil
}

// ProvisionPersonal = device.prc_provision_personal_tenant (PERSONAL, SIN tenant, DEFINER).
// Es el UNICO camino de escritura que corre con el pool directo, sin app.tenant_id: en este
// momento el tenant todavia no existe. Idempotente por install_id.
func (s *PostgresUserDataStore) ProvisionPersonal(
	ctx context.Context, in entities.RegisterInput,
) (json.RawMessage, error) {
	var out []byte
	err := s.pool.QueryRow(ctx,
		`CALL device.prc_provision_personal_tenant($1,$2,$3,$4,$5,$6,$7)`,
		in.InstallID, in.DeviceID, in.Platform, in.OSVersion, in.AppVersion, in.Model, nil,
	).Scan(&out)
	if err != nil {
		return nil, fmt.Errorf("userdata provision_personal_tenant: %w", err)
	}
	return out, nil
}

// nullTextSlice pasa nil cuando la lista esta vacia, para que fnc_sync_changes reciba NULL
// (= todas las entidades) en vez de un array vacio (= ninguna).
func nullTextSlice(s []string) []string {
	if len(s) == 0 {
		return nil
	}
	return s
}
