package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/application/trafficquery"
	"ms-vehitrack/domain/entities"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/responses"
)

// TrafficQueryServiceResolver lo cumple el container.
type TrafficQueryServiceResolver interface {
	ResolveTrafficQueryService() (*trafficquery.Service, bool)
}

// TrafficBBoxHandler sirve las lecturas agregadas de trafico por bbox (estado en vivo y perfil).
// Son lecturas GLOBALES (agregados anonimos del corredor): no llevan tenant.
type TrafficBBoxHandler struct {
	resolver TrafficQueryServiceResolver
}

func NewTrafficBBoxHandler(resolver TrafficQueryServiceResolver) *TrafficBBoxHandler {
	return &TrafficBBoxHandler{resolver: resolver}
}

func (h *TrafficBBoxHandler) service(c *gin.Context) (*trafficquery.Service, bool) {
	svc, ok := h.resolver.ResolveTrafficQueryService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "traffic-query-unavailable",
			"traffic queries not configured (enable POSTGRES)")
	}
	return svc, ok
}

// Live = GET /v1/traffic/live?bbox=minLon,minLat,maxLon,maxLat&min_devices=N. GLOBAL.
func (h *TrafficBBoxHandler) Live(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	bbox, err := entities.ParseBBox(c.Query("bbox"))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest(err.Error()))
		return
	}
	raw, err := svc.Live(c.Request.Context(), bbox, queryIntPtr(c, "min_devices"))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

// Profile = GET /v1/traffic/profile?bbox=...&at=RFC3339&min_devices=N. GLOBAL. La funcion PG
// deriva day_kind y time_slot del instante at (por defecto now()); no toma day_kind/time_slot
// sueltos (ver migrations/001 traffic.fnc_profile_by_bbox).
func (h *TrafficBBoxHandler) Profile(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	bbox, err := entities.ParseBBox(c.Query("bbox"))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest(err.Error()))
		return
	}
	var at *time.Time
	if raw := c.Query("at"); raw != "" {
		t, perr := time.Parse(time.RFC3339, raw)
		if perr != nil {
			responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid at (expected RFC3339)"))
			return
		}
		at = &t
	}
	raw, err := svc.Profile(c.Request.Context(), bbox, at, queryIntPtr(c, "min_devices"))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

// queryIntPtr devuelve *int para un query param entero, o nil si falta o no parsea.
func queryIntPtr(c *gin.Context, key string) *int {
	if raw := c.Query(key); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			return &n
		}
	}
	return nil
}
