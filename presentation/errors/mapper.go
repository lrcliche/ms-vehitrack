package errors

import (
	"errors"
	"net/http"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

func Map(err error) AppError {
	switch {
	case errors.Is(err, entities.ErrInvalidTelemetryDeviceID),
		errors.Is(err, entities.ErrInvalidTelemetryTimestamp),
		errors.Is(err, entities.ErrInvalidTelemetryLatitude),
		errors.Is(err, entities.ErrInvalidTelemetryLongitude),
		errors.Is(err, entities.ErrInvalidTelemetryProtocol),
		errors.Is(err, entities.ErrInvalidTelemetryVIN),
		errors.Is(err, entities.ErrInvalidTelemetrySpeedGPS),
		errors.Is(err, entities.ErrInvalidTelemetrySpeedOBD),
		errors.Is(err, entities.ErrInvalidTelemetryRPM),
		errors.Is(err, entities.ErrInvalidTelemetryFuelLevel),
		errors.Is(err, entities.ErrStaleTelemetryTimestamp),
		errors.Is(err, entities.ErrFutureTelemetryTimestamp):
		return New(http.StatusUnprocessableEntity, "validation-error", err.Error())
	case errors.Is(err, ports.ErrTelemetryPublishFailed):
		return New(http.StatusBadGateway, "telemetry-publish-failed", "Failed to publish telemetry")
	case errors.Is(err, ports.ErrTelemetryStoreFailed):
		return New(http.StatusBadGateway, "telemetry-store-failed", "Failed to store telemetry")
	default:
		return New(http.StatusInternalServerError, "internal-server-error", "Internal Error")
	}
}

func BadRequest(message string) AppError {
	return New(http.StatusBadRequest, "bad-request", message)
}
