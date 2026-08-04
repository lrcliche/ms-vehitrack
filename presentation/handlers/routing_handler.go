package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/application/routing"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"
)

// RoutingServiceResolver lo cumple el container.
type RoutingServiceResolver interface {
	ResolveRoutingService() (*routing.Service, bool)
}

// RoutingHandler sirve POST /routes con la cascada de cache de rutas. TENANT-SCOPED: el device
// y el tenant salen del contexto que puso TenantContext (routing.route_request tiene RLS).
type RoutingHandler struct {
	resolver RoutingServiceResolver
}

func NewRoutingHandler(resolver RoutingServiceResolver) *RoutingHandler {
	return &RoutingHandler{resolver: resolver}
}

func (h *RoutingHandler) service(c *gin.Context) (*routing.Service, bool) {
	svc, ok := h.resolver.ResolveRoutingService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "routing-unavailable",
			"routing not configured (enable POSTGRES)")
	}
	return svc, ok
}

// Route = POST /v1/routes. Body {waypoints:[{lat,lon}], profile?}. Devuelve la ruta (geometry,
// distance, duration, steps, expiresAt) bajo "route" y el flag cacheHit.
func (h *RoutingHandler) Route(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.RouteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid route request"))
		return
	}

	waypoints := make([]entities.Waypoint, len(req.Waypoints))
	for i, w := range req.Waypoints {
		waypoints[i] = entities.Waypoint{Lat: w.Lat, Lon: w.Lon}
	}

	raw, cacheHit, err := svc.Route(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c),
		waypoints, req.Profile)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}

	// Se re-mapea el jsonb del modelo PG (routes[] con geojson/distance_m/duration_s/
	// duration_in_traffic_s) al contrato de la app (geometry/distance/duration/
	// duration_in_traffic) y se expone como lista `routes` = principal + alternativas (la app
	// lee `data.routes[]`). `route` se conserva crudo por compatibilidad.
	body := gin.H{
		"cacheHit": cacheHit,
		"route":    json.RawMessage(raw),
	}
	if views, mapped := dto.RouteViewsFromStored(json.RawMessage(raw)); mapped {
		body["routes"] = views
	}
	responses.Success(c, http.StatusOK, body)
}
