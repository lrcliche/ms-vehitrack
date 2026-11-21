package handlers

import (
	"fmt"
	"net/http"
	"net/url"
	"time"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/application/businessauth"
	"ms-vehitrack/application/drivers"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"
)

type DriverAppServiceResolver interface {
	ResolveDriverAppService() (*drivers.Service, bool)
}

type DriverAppHandler struct{ resolver DriverAppServiceResolver }

func NewDriverAppHandler(resolver DriverAppServiceResolver) *DriverAppHandler {
	return &DriverAppHandler{resolver: resolver}
}

func (h *DriverAppHandler) Profile(c *gin.Context) {
	claims, service, ok := h.context(c)
	if !ok {
		return
	}
	result, err := service.Profile(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID)
	if err != nil {
		h.respondError(c, err)
		return
	}
	responses.Success(c, http.StatusOK, result)
}

func (h *DriverAppHandler) Documents(c *gin.Context) {
	claims, service, ok := h.context(c)
	if !ok {
		return
	}
	owner := c.Query("owner")
	if owner != "conductor" && owner != "vehiculo" {
		responses.Error(c, http.StatusBadRequest, "invalid-request", "owner debe ser conductor o vehiculo")
		return
	}
	result, err := service.Documents(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, owner)
	if err != nil {
		h.respondError(c, err)
		return
	}
	responses.Success(c, http.StatusOK, result)
}

func (h *DriverAppHandler) DaySummary(c *gin.Context) {
	claims, service, ok := h.context(c)
	if !ok {
		return
	}
	date := c.Query("fecha")
	if _, err := time.Parse("2006-01-02", date); err != nil {
		responses.Error(c, http.StatusBadRequest, "invalid-request", "fecha debe usar YYYY-MM-DD")
		return
	}
	result, err := service.DaySummary(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, date)
	if err != nil {
		h.respondError(c, err)
		return
	}
	responses.Success(c, http.StatusOK, result)
}

func (h *DriverAppHandler) Services(c *gin.Context) {
	claims, service, ok := h.context(c)
	if !ok {
		return
	}
	result, err := service.Services(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID)
	if err != nil {
		h.respondError(c, err)
		return
	}
	responses.Success(c, http.StatusOK, result)
}

func (h *DriverAppHandler) StartService(c *gin.Context) {
	h.transitionService(c, true)
}

func (h *DriverAppHandler) FinishService(c *gin.Context) {
	h.transitionService(c, false)
}

func (h *DriverAppHandler) transitionService(c *gin.Context, start bool) {
	claims, service, ok := h.context(c)
	if !ok {
		return
	}
	id := c.Param("id")
	var result interface{}
	var err error
	if start {
		result, err = service.StartService(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, id)
	} else {
		result, err = service.FinishService(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID, id)
	}
	if err != nil {
		h.respondError(c, err)
		return
	}
	responses.Success(c, http.StatusOK, result)
}

func (h *DriverAppHandler) DocumentFile(c *gin.Context) {
	claims, service, ok := h.context(c)
	if !ok {
		return
	}
	file, err := service.OpenDocument(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID,
		c.Param("owner"), c.Param("documentID"))
	if err != nil {
		h.respondError(c, err)
		return
	}
	defer file.Reader.Close()
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename*=UTF-8''%s", url.PathEscape(file.FileName)))
	c.Header("Cache-Control", "private, no-store")
	c.Header("X-Content-Type-Options", "nosniff")
	c.DataFromReader(http.StatusOK, -1, file.ContentType, file.Reader, nil)
}

func (h *DriverAppHandler) context(c *gin.Context) (claims *businessauth.TokenClaims, service *drivers.Service, ok bool) {
	claims, ok = middleware.BusinessClaimsFromContext(c)
	if !ok {
		responses.Error(c, http.StatusUnauthorized, "unauthorized", "valid business token required")
		return
	}
	service, ok = h.resolver.ResolveDriverAppService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "driver-app-unavailable", "driver app service is not configured")
		return
	}
	return claims, service, true
}

func (h *DriverAppHandler) respondError(c *gin.Context, err error) {
	if err == drivers.ErrDriverAppInvalid {
		responses.Error(c, http.StatusBadRequest, "invalid-request", "invalid driver app request")
		return
	}
	if err == drivers.ErrDriverAppUnavailable {
		responses.Error(c, http.StatusServiceUnavailable, "driver-app-unavailable", "driver app service is not configured")
		return
	}
	// The same mapper used by the enterprise handlers keeps PostgreSQL VT* errors consistent.
	responses.ErrorFromApp(c, presentationerrors.Map(err))
}
