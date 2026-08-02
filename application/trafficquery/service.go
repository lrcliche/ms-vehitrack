// Package trafficquery orquesta las lecturas agregadas de trafico por bbox (doc 03 §3): estado
// en vivo y perfil tipico del corredor. El trabajo real vive en funciones PG globales
// (traffic.fnc_live_by_bbox / traffic.fnc_profile_by_bbox); el servicio valida el bbox y hace
// passthrough del jsonb.
package trafficquery

import (
	"context"
	"encoding/json"
	"time"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

// Service implementa las lecturas de trafico por bbox sobre el store PG.
type Service struct {
	store ports.TrafficQueryStore
}

func NewService(store ports.TrafficQueryStore) *Service {
	return &Service{store: store}
}

// Live = traffic.fnc_live_by_bbox. Estado en vivo por link dentro del bbox.
func (s *Service) Live(
	ctx context.Context, bbox entities.BBox, minDeviceCount *int,
) (json.RawMessage, error) {
	return s.store.LiveByBBox(ctx, bbox, minDeviceCount)
}

// Profile = traffic.fnc_profile_by_bbox. Perfil tipico por link para el instante at (nil = now).
func (s *Service) Profile(
	ctx context.Context, bbox entities.BBox, at *time.Time, minDeviceCount *int,
) (json.RawMessage, error) {
	return s.store.ProfileByBBox(ctx, bbox, at, minDeviceCount)
}
