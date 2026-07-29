package handlers

import (
	"fmt"
	"net/http"
	"time"

	"ms-vehitrack/application/services"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/logging"
	"ms-vehitrack/presentation/responses"

	"github.com/gin-gonic/gin"
)

// TelemetryServiceResolver resolves the telemetry application service.
type TelemetryServiceResolver interface {
	ResolveTelemetryService() services.TelemetryService
}

// TelemetryHandler exposes HTTP endpoints for telemetry ingestion.
type TelemetryHandler struct {
	serviceResolver TelemetryServiceResolver
}

// NewTelemetryHandler creates a TelemetryHandler.
func NewTelemetryHandler(serviceResolver TelemetryServiceResolver) *TelemetryHandler {
	return &TelemetryHandler{serviceResolver: serviceResolver}
}

// Publish handles POST /api/v1/telemetry.
func (h *TelemetryHandler) Publish(c *gin.Context) {
	start := time.Now()
	logging.LogComponent("TELEMETRY_HANDLER", "operation=Publish status=started")

	var request dto.TelemetryRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		logging.LogError("TELEMETRY_HANDLER", "BindJSON", err)
		responses.ErrorFromApp(c, presentationerrors.BadRequest("Invalid request body"))
		return
	}

	telemetry := request.ToDomain()
	if err := h.serviceResolver.ResolveTelemetryService().Publish(c.Request.Context(), telemetry); err != nil {
		h.handleError(c, err)
		return
	}

	logging.LogComponent(
		"TELEMETRY_HANDLER",
		fmt.Sprintf("operation=Publish status=success deviceId=%s latency=%s", telemetry.DeviceID, time.Since(start)),
	)

	responses.Success(c, http.StatusAccepted, gin.H{
		"deviceId":  telemetry.DeviceID,
		"timestamp": telemetry.Timestamp,
		"status":    "accepted",
	})
}

func (h *TelemetryHandler) handleError(c *gin.Context, err error) {
	logging.LogError("TELEMETRY_HANDLER", "Publish", err)
	responses.ErrorFromApp(c, presentationerrors.Map(err))
}
