package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/application/userdata"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"
)

// UserDataServiceResolver lo cumple el container.
type UserDataServiceResolver interface {
	ResolveUserDataService() (*userdata.Service, bool)
}

// UserDataHandler sirve favoritos, POI propios, geocercas, ajustes, el sync bidireccional y el
// registro de dispositivo. Las rutas de datos son TENANT-SCOPED (el device y el tenant salen
// del contexto que puso TenantContext). El registro es la excepcion (ver device_register.go).
type UserDataHandler struct {
	resolver UserDataServiceResolver
}

func NewUserDataHandler(resolver UserDataServiceResolver) *UserDataHandler {
	return &UserDataHandler{resolver: resolver}
}

func (h *UserDataHandler) service(c *gin.Context) (*userdata.Service, bool) {
	svc, ok := h.resolver.ResolveUserDataService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "userdata-unavailable",
			"user data not configured (enable POSTGRES)")
	}
	return svc, ok
}

// ListFavorites = GET /v1/favorites?include_deleted=. TENANT-SCOPED.
func (h *UserDataHandler) ListFavorites(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	includeDeleted := c.Query("include_deleted") == "true"
	favorites, err := svc.ListFavorites(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c), includeDeleted)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, gin.H{"favorites": favorites})
}

// UpsertFavorite = PUT /v1/favorites/:id. TENANT-SCOPED.
func (h *UserDataHandler) UpsertFavorite(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.UpsertFavoriteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid favorite request"))
		return
	}
	raw, err := svc.UpsertFavorite(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c), c.Param("id"),
		entities.FavoriteUpsert{
			Label: req.Label, Lat: req.Lat, Lon: req.Lon, Kind: req.Kind,
			Description: req.Description, Icon: req.Icon, ColorHex: req.ColorHex,
			PlaceID: req.PlaceID, ClientUpdatedAt: req.ClientUpdatedAt,
		})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

// DeleteFavorite = DELETE /v1/favorites/:id -> soft_delete('favorite_place'). TENANT-SCOPED.
func (h *UserDataHandler) DeleteFavorite(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	raw, err := svc.SoftDelete(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c),
		"favorite_place", c.Param("id"))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

// UpsertPlace = PUT /v1/places/:id. TENANT-SCOPED.
func (h *UserDataHandler) UpsertPlace(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.UpsertPlaceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid place request"))
		return
	}
	raw, err := svc.UpsertPlace(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c), c.Param("id"),
		entities.PlaceUpsert{
			Name: req.Name, Lat: req.Lat, Lon: req.Lon, CategoryID: req.CategoryID,
			Description: req.Description, ClientUpdatedAt: req.ClientUpdatedAt,
		})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

// UpsertGeofence = PUT /v1/geofences/:id. TENANT-SCOPED. isActive por defecto true.
func (h *UserDataHandler) UpsertGeofence(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.UpsertGeofenceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid geofence request"))
		return
	}
	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}
	raw, err := svc.UpsertGeofence(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c), c.Param("id"),
		entities.GeofenceUpsert{
			Name: req.Name, GeomWKT: req.GeomWKT, Shape: req.Shape, RadiusM: req.RadiusM,
			Trigger: req.Trigger, CooldownS: req.CooldownS, IsActive: isActive,
			ClientUpdatedAt: req.ClientUpdatedAt,
		})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

// RecordGeofenceEvent = POST /v1/geofences/events. TENANT-SCOPED. Idempotente por (geofence, ts).
func (h *UserDataHandler) RecordGeofenceEvent(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.GeofenceEventRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid geofence event request"))
		return
	}
	raw, err := svc.RecordGeofenceEvent(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c),
		entities.GeofenceEventInput{
			GeofenceID: req.GeofenceID, Trigger: req.Trigger, Lat: req.Lat, Lon: req.Lon,
			OccurredAt: req.OccurredAt, TripID: req.TripID,
		})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

// EvaluateGeofence = POST /v1/geofences/evaluate. TENANT-SCOPED. Auditoria/reproceso.
func (h *UserDataHandler) EvaluateGeofence(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.EvaluateGeofenceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid evaluate request"))
		return
	}
	hits, err := svc.EvaluateGeofence(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c), req.Points)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, gin.H{"hits": hits})
}

// UpsertSetting = PUT /v1/settings/:key. TENANT-SCOPED.
func (h *UserDataHandler) UpsertSetting(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.UpsertSettingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid setting request"))
		return
	}
	raw, err := svc.UpsertSetting(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c),
		c.Param("key"), req.Value)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}
