package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/application/packages"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"
)

// OfflineServiceResolver lo cumple el container.
type OfflineServiceResolver interface {
	ResolveOfflineService() (*packages.Service, bool)
}

type OfflineHandler struct {
	resolver OfflineServiceResolver
}

func NewOfflineHandler(resolver OfflineServiceResolver) *OfflineHandler {
	return &OfflineHandler{resolver: resolver}
}

func (h *OfflineHandler) service(c *gin.Context) (*packages.Service, bool) {
	svc, ok := h.resolver.ResolveOfflineService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "offline-unavailable",
			"offline packages not configured (enable POSTGRES)")
	}
	return svc, ok
}

// Manifest = GET /v1/regions/:id/manifest?installed_version=N. GLOBAL (DeviceContext). Devuelve
// el jsonb de la rutina tal cual. VT070 (región sin paquete) → 503 vía presentationerrors.Map.
func (h *OfflineHandler) Manifest(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var installed *int
	if raw := c.Query("installed_version"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			installed = &n
		}
	}
	raw, err := svc.Manifest(c.Request.Context(), c.Param("id"), installed)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

// RegionsForRoute = POST /v1/regions/for-route. GLOBAL (DeviceContext).
func (h *OfflineHandler) RegionsForRoute(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.RegionsForRouteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid for-route request"))
		return
	}
	regions, err := svc.RegionsForRoute(c.Request.Context(), req.RouteGeojson)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, gin.H{"regions": regions})
}

// ListInstalled = GET /v1/regions/installed. TENANT-SCOPED (TenantContext). El device y el
// tenant salen del contexto que puso el middleware.
func (h *OfflineHandler) ListInstalled(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	regions, err := svc.ListInstalled(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, gin.H{"regions": regions})
}

// TrackPackage = POST /v1/regions/:id/installed. TENANT-SCOPED (TenantContext).
func (h *OfflineHandler) TrackPackage(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.TrackPackageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid track request"))
		return
	}
	raw, err := svc.TrackPackage(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c),
		c.Param("id"), req.Operation, req.Version, req.SizeBytes, req.IsProtected)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}
