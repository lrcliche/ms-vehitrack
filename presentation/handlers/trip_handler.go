package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/application/tracking"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"
)

// TrackingServiceResolver lo cumple el container.
type TrackingServiceResolver interface {
	ResolveTrackingService() (*tracking.Service, bool)
}

// TrackingHandler sirve la ingesta de telemetria por lote, los viajes y las sesiones OBD. Todo
// es TENANT-SCOPED: el device y el tenant salen del contexto que puso TenantContext.
type TrackingHandler struct {
	resolver TrackingServiceResolver
}

func NewTrackingHandler(resolver TrackingServiceResolver) *TrackingHandler {
	return &TrackingHandler{resolver: resolver}
}

func (h *TrackingHandler) service(c *gin.Context) (*tracking.Service, bool) {
	svc, ok := h.resolver.ResolveTrackingService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "tracking-unavailable",
			"tracking not configured (enable POSTGRES)")
	}
	return svc, ok
}

// TelemetryBatch = POST /v1/telemetry/batch. TENANT-SCOPED. Ingesta idempotente por batchId.
// Responde 202 Accepted con el resultado de la rutina (received/inserted/duplicate...).
func (h *TrackingHandler) TelemetryBatch(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.TelemetryBatchRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid telemetry batch request"))
		return
	}
	raw, err := svc.IngestTelemetry(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c),
		req.BatchID, req.Samples, req.ClientCreatedAt)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusAccepted, json.RawMessage(raw))
}

// UpsertTrip = POST /v1/trips. TENANT-SCOPED. El tripId viaja en el body (uuid v7 de la app).
func (h *TrackingHandler) UpsertTrip(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.UpsertTripRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid trip request"))
		return
	}
	raw, err := svc.UpsertTrip(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c), req.TripID,
		entities.TripUpsert{
			StartedAt: req.StartedAt, EndedAt: req.EndedAt, Status: req.Status,
			FuelLiters: req.FuelLiters, CostCOP: req.CostCOP,
		})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

// CloseTrip = POST /v1/trips/:id/close. TENANT-SCOPED. Materializa la traza del viaje.
func (h *TrackingHandler) CloseTrip(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	raw, err := svc.CloseTrip(c.Request.Context(),
		middleware.TenantIDFromContext(c), c.Param("id"))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

// UpsertObdSession = POST /v1/obd/sessions. TENANT-SCOPED. El sessionId viaja en el body.
func (h *TrackingHandler) UpsertObdSession(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.UpsertObdSessionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid obd session request"))
		return
	}
	raw, err := svc.UpsertObdSession(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c), req.SessionID,
		entities.ObdSessionUpsert{
			Protocol: req.Protocol, TripID: req.TripID, AdapterName: req.AdapterName,
			StartedAt: req.StartedAt, EndedAt: req.EndedAt,
		})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}
