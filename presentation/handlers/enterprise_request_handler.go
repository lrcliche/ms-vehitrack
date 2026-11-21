package handlers

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/application/servicerequests"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"
)

type ServiceRequestServiceResolver interface {
	ResolveServiceRequestService() (*servicerequests.Service, bool)
}

type EnterpriseRequestHandler struct {
	resolver ServiceRequestServiceResolver
}

func NewEnterpriseRequestHandler(resolver ServiceRequestServiceResolver) *EnterpriseRequestHandler {
	return &EnterpriseRequestHandler{resolver: resolver}
}

func (h *EnterpriseRequestHandler) Create(c *gin.Context) {
	claims, ok := middleware.BusinessClaimsFromContext(c)
	if !ok {
		responses.Error(c, http.StatusUnauthorized, "unauthorized", "valid business token required")
		return
	}
	var req dto.CreateEnterpriseRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.Origin == nil || req.Destination == nil ||
		req.Origin.Lat == nil || req.Origin.Lng == nil || req.Destination.Lat == nil ||
		req.Destination.Lng == nil || req.AgreedFareCOP == nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid service request"))
		return
	}
	scheduledAt, err := time.Parse(time.RFC3339, strings.TrimSpace(req.ScheduledAt))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("fecha_servicio must be RFC3339"))
		return
	}
	svc, ok := h.resolver.ResolveServiceRequestService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "service-requests-unavailable", "service request service is not configured")
		return
	}
	result, err := svc.Create(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID,
		entities.CreateServiceRequestCommand{
			CustomerName:  req.CustomerName,
			OriginAddress: req.Origin.Address, OriginLatitude: *req.Origin.Lat, OriginLongitude: *req.Origin.Lng,
			DestinationAddress:  req.Destination.Address,
			DestinationLatitude: *req.Destination.Lat, DestinationLongitude: *req.Destination.Lng,
			ScheduledAt: scheduledAt, PassengerCount: req.Passengers, AgreedFareCOP: *req.AgreedFareCOP,
			Notes: req.Notes,
		})
	if err != nil {
		switch {
		case errors.Is(err, entities.ErrServiceRequestForbidden):
			responses.Error(c, http.StatusForbidden, "forbidden", "insufficient permission to create service requests")
		case errors.Is(err, entities.ErrInvalidServiceRequest):
			responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid service request"))
		case errors.Is(err, entities.ErrServiceRequestRouteUnavailable):
			responses.Error(c, http.StatusBadGateway, "route-unavailable", "could not estimate the passenger route")
		default:
			responses.ErrorFromApp(c, presentationerrors.Map(err))
		}
		return
	}
	request := result.Request
	response := gin.H{
		"id":                    request.ID,
		"nombre_cliente":        request.CustomerName,
		"origen":                gin.H{"direccion": request.OriginAddress, "lat": request.OriginLatitude, "lng": request.OriginLongitude},
		"destino":               gin.H{"direccion": request.DestinationAddress, "lat": request.DestinationLatitude, "lng": request.DestinationLongitude},
		"fecha_servicio":        request.ScheduledAt,
		"pasajeros":             request.PassengerCount,
		"tarifa_pactada":        request.AgreedFareCOP,
		"km_estimados":          result.EstimatedKM,
		"duracion_estimada_min": result.EstimatedDurationMin,
		"estado":                "pendiente",
	}
	if result.DurationInTrafficMin != nil {
		response["duracion_con_trafico_min"] = *result.DurationInTrafficMin
	}
	responses.Success(c, http.StatusCreated, response)
}
