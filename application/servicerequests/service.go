package servicerequests

import (
	"context"
	"errors"
	"math"
	"strings"

	"ms-vehitrack/application/routing"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

type RouteEstimator interface {
	EstimateForUser(ctx context.Context, tenantID, userID, tenantUserID string,
		waypoints []entities.Waypoint, profile string) (*routing.RouteEstimate, error)
}

type Service struct {
	store  ports.ServiceRequestStore
	routes RouteEstimator
}

func NewService(store ports.ServiceRequestStore, routes RouteEstimator) *Service {
	return &Service{store: store, routes: routes}
}

type Result struct {
	Request              *entities.CreatedServiceRequest
	EstimatedKM          float64
	EstimatedDurationMin int
	DurationInTrafficMin *int
}

func (s *Service) Create(ctx context.Context, tenantID, actorUserID, tenantUserID string,
	command entities.CreateServiceRequestCommand) (*Result, error) {
	if strings.TrimSpace(command.CustomerName) == "" || strings.TrimSpace(command.OriginAddress) == "" ||
		strings.TrimSpace(command.DestinationAddress) == "" || command.PassengerCount < 1 ||
		command.AgreedFareCOP < 0 || command.ScheduledAt.IsZero() ||
		command.OriginLatitude < -90 || command.OriginLatitude > 90 ||
		command.DestinationLatitude < -90 || command.DestinationLatitude > 90 ||
		command.OriginLongitude < -180 || command.OriginLongitude > 180 ||
		command.DestinationLongitude < -180 || command.DestinationLongitude > 180 {
		return nil, entities.ErrInvalidServiceRequest
	}

	route, err := s.routes.EstimateForUser(ctx, tenantID, actorUserID, tenantUserID, []entities.Waypoint{
		{Lat: command.OriginLatitude, Lon: command.OriginLongitude},
		{Lat: command.DestinationLatitude, Lon: command.DestinationLongitude},
	}, "car")
	if err != nil {
		return nil, errors.Join(entities.ErrServiceRequestRouteUnavailable, err)
	}
	request, err := s.store.CreateServiceRequest(ctx, tenantID, actorUserID, tenantUserID, command)
	if err != nil {
		return nil, err
	}
	eta := route.DurationS
	if route.DurationInTrafficS != nil && *route.DurationInTrafficS > 0 {
		eta = *route.DurationInTrafficS
	}
	minutes := int(math.Round(eta / 60))
	var trafficMinutes *int
	if route.DurationInTrafficS != nil {
		v := int(math.Round(*route.DurationInTrafficS / 60))
		trafficMinutes = &v
	}
	return &Result{
		Request:              request,
		EstimatedKM:          math.Round(route.DistanceM/100) / 10,
		EstimatedDurationMin: minutes,
		DurationInTrafficMin: trafficMinutes,
	}, nil
}
