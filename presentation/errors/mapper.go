package errors

import (
	"errors"
	"net/http"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

func Map(err error) AppError {
	// SQLSTATE VT* del modelo PG (rutinas prc_/fnc_) primero: son errores de negocio
	// estampados en la BD, con su propio mapeo a HTTP (doc 03 §4).
	if appErr, ok := MapPgError(err); ok {
		return appErr
	}
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
	case errors.Is(err, entities.ErrInvalidTrafficBatchID),
		errors.Is(err, entities.ErrInvalidTrafficSample):
		return New(http.StatusUnprocessableEntity, "validation-error", err.Error())
	case errors.Is(err, entities.ErrTrafficStoreUnavailable):
		return New(http.StatusServiceUnavailable, "traffic-unavailable", err.Error())
	// Validaciones baratas del modelo PG (geocoding/offline/userdata): faltan campos
	// obligatorios en la peticion antes de tocar la BD. Son 400, no 500.
	case errors.Is(err, entities.ErrDeviceIDRequired),
		errors.Is(err, entities.ErrRegionIDRequired),
		errors.Is(err, entities.ErrRouteGeojsonRequired),
		errors.Is(err, entities.ErrIDRequired),
		errors.Is(err, entities.ErrSettingKeyRequired),
		errors.Is(err, entities.ErrSettingValueRequired),
		errors.Is(err, entities.ErrEntityRequired),
		errors.Is(err, entities.ErrSyncItemsRequired),
		errors.Is(err, entities.ErrGeofenceIDRequired),
		errors.Is(err, entities.ErrGeofenceWKTRequired),
		errors.Is(err, entities.ErrRegisterAmbiguous),
		errors.Is(err, entities.ErrWaypointsRequired),
		errors.Is(err, entities.ErrTooFewWaypoints),
		errors.Is(err, entities.ErrBatchIDRequired),
		errors.Is(err, entities.ErrSamplesRequired),
		errors.Is(err, entities.ErrTripIDRequired),
		errors.Is(err, entities.ErrSessionIDRequired),
		errors.Is(err, entities.ErrGeocodeQueryRequired),
		errors.Is(err, entities.ErrProtocolRequired):
		return New(http.StatusBadRequest, "INVALID_REQUEST", err.Error())
	// Geocoding sin resultado (ni PG ni Nominatim): es 404, NO 500. La app lo trata
	// como lista vacia; sin este caso, cada busqueda sin match ensucia el log con 500.
	case errors.Is(err, entities.ErrGeocodeNoResult):
		return New(http.StatusNotFound, "NOT_FOUND", "sin resultados")
	case errors.Is(err, ports.ErrTelemetryPublishFailed):
		return New(http.StatusBadGateway, "telemetry-publish-failed", "Failed to publish telemetry")
	case errors.Is(err, ports.ErrTelemetryStoreFailed):
		return New(http.StatusBadGateway, "telemetry-store-failed", "Failed to store telemetry")
	case errors.Is(err, ports.ErrTrafficStoreFailed):
		return New(http.StatusBadGateway, "traffic-store-failed", "Failed to store traffic")
	case errors.Is(err, ports.ErrTrafficCacheFailed):
		return New(http.StatusBadGateway, "traffic-cache-failed", "Failed to cache traffic")
	default:
		return New(http.StatusInternalServerError, "internal-server-error", "Internal Error")
	}
}

func BadRequest(message string) AppError {
	return New(http.StatusBadRequest, "bad-request", message)
}
