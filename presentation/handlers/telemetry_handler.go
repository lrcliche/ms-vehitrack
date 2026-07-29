package handlers

import (
	"fmt"
	"net/http"
	"time"

	"ms-vehitrack/application/usecases"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/dto"
	"ms-vehitrack/presentation/logging"
	"ms-vehitrack/presentation/responses"

	"github.com/gin-gonic/gin"
)

// TelemetryUseCaseResolver resolves the publish telemetry use case.
type TelemetryUseCaseResolver interface {
	ResolvePublishTelemetryUseCase() usecases.PublishTelemetryUseCase
}

// TelemetryHandler exposes HTTP endpoints for telemetry ingestion.
type TelemetryHandler struct {
	useCaseResolver TelemetryUseCaseResolver
}

// NewTelemetryHandler creates a TelemetryHandler.
func NewTelemetryHandler(useCaseResolver TelemetryUseCaseResolver) *TelemetryHandler {
	return &TelemetryHandler{useCaseResolver: useCaseResolver}
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
	if err := h.useCaseResolver.ResolvePublishTelemetryUseCase().Execute(c.Request.Context(), telemetry); err != nil {
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
