package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgconn"

	"ms-vehitrack/application/routing"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/logging"
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

	h.writeRouteResponse(c, raw, cacheHit)
}

// RouteV2 acepta el mismo body del endpoint v1, autenticado con JWT de usuario empresarial.
func (h *RoutingHandler) RouteV2(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	claims, ok := middleware.BusinessClaimsFromContext(c)
	if !ok {
		responses.Error(c, http.StatusUnauthorized, "unauthorized", "valid business token required")
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
	raw, cacheHit, err := svc.RouteForUser(c.Request.Context(), claims.TenantID,
		claims.Subject, claims.TenantUserID, waypoints, req.Profile)
	if err != nil {
		appErr := presentationerrors.Map(err)
		if appErr.Status >= http.StatusInternalServerError {
			logRouteV2Error(err)
		}
		responses.ErrorFromApp(c, appErr)
		return
	}
	h.writeRouteResponse(c, raw, cacheHit)
}

func logRouteV2Error(err error) {
	var dbErr *pgconn.PgError
	if errors.As(err, &dbErr) {
		logging.LogComponent("ROUTING_V2_ERROR", fmt.Sprintf(
			"operation=route sqlstate=%s severity=%s message=%q schema=%s table=%s column=%s constraint=%s routine=%s",
			dbErr.Code, dbErr.Severity, dbErr.Message, dbErr.SchemaName, dbErr.TableName,
			dbErr.ColumnName, dbErr.ConstraintName, dbErr.Routine,
		))
		return
	}
	logging.LogError("ROUTING_V2_ERROR", "operation=route", err)
}

func (h *RoutingHandler) writeRouteResponse(c *gin.Context, raw json.RawMessage, cacheHit bool) {
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
