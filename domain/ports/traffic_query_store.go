package ports

import (
	"context"
	"encoding/json"
	"time"

	"ms-vehitrack/domain/entities"
)

// TrafficQueryStore es el puerto de las lecturas agregadas de trafico por bbox (doc 03 §3):
// estado en vivo y perfil tipico. Envuelve traffic.fnc_live_by_bbox y traffic.fnc_profile_by_bbox.
//
// Estas tablas (traffic.live_state, traffic.link, traffic.profile) son GLOBALES (sin RLS): son
// agregados anonimos del corredor, no datos de un tenant. El store usa el pool directo. Cada
// metodo devuelve el jsonb ya con la geometria como GeoJSON (passthrough).
type TrafficQueryStore interface {
	// LiveByBBox = traffic.fnc_live_by_bbox. minDeviceCount nil -> umbral de app_setting.
	LiveByBBox(ctx context.Context, bbox entities.BBox, minDeviceCount *int) (json.RawMessage, error)
	// ProfileByBBox = traffic.fnc_profile_by_bbox. at nil -> now() (la funcion deriva day_kind
	// y time_slot del instante). minDeviceCount nil -> umbral de app_setting.
	ProfileByBBox(ctx context.Context, bbox entities.BBox, at *time.Time, minDeviceCount *int) (json.RawMessage, error)
}
