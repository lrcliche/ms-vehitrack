package ports

import (
	"context"
	"encoding/json"
)

type BusinessRoutingStore interface {
	RecordUserHit(ctx context.Context, tenantID, userID, tenantUserID string, routeCacheID int64) error
	StoreUserRoute(
		ctx context.Context, tenantID, userID, tenantUserID string,
		waypoints, geojson json.RawMessage, distanceM float64, durationS int,
		profile string, steps, alternatives json.RawMessage,
	) (json.RawMessage, error)
}
