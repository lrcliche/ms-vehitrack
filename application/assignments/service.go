package assignments

import (
	"context"
	"math"
	"sort"

	"ms-vehitrack/application/routing"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

type RouteEstimator interface {
	EstimateForUser(ctx context.Context, tenantID, userID, tenantUserID string,
		waypoints []entities.Waypoint, profile string) (*routing.RouteEstimate, error)
}

type Service struct {
	store  ports.AssignmentCandidateStore
	routes RouteEstimator
}

func NewService(store ports.AssignmentCandidateStore, routes RouteEstimator) *Service {
	return &Service{store: store, routes: routes}
}

type RequestView struct {
	ID                   string   `json:"id"`
	Status               string   `json:"status"`
	PickupAddress        string   `json:"pickup_address"`
	PickupLatitude       *float64 `json:"pickup_latitude"`
	PickupLongitude      *float64 `json:"pickup_longitude"`
	DestinationAddress   string   `json:"destination_address"`
	DestinationLatitude  *float64 `json:"destination_latitude"`
	DestinationLongitude *float64 `json:"destination_longitude"`
	ScheduledAt          string   `json:"scheduled_at"`
	PassengerCount       int      `json:"passenger_count"`
	AgreedFareCOP        float64  `json:"agreed_fare_cop"`
}

type LegEstimate struct {
	DistanceKM         float64  `json:"distance_km"`
	DurationS          float64  `json:"duration_s"`
	DurationInTrafficS *float64 `json:"duration_in_traffic_s,omitempty"`
}

type CostEstimate struct {
	Available          bool     `json:"available"`
	Reason             string   `json:"reason,omitempty"`
	Currency           string   `json:"currency"`
	Scope              string   `json:"scope,omitempty"`
	CostPerKMCOP       float64  `json:"cost_per_km_cop"`
	DispatchCostCOP    float64  `json:"dispatch_cost_cop"`
	EmptyLegCOP        *float64 `json:"empty_leg_cop,omitempty"`
	ServiceLegCOP      *float64 `json:"service_leg_cop,omitempty"`
	EstimatedCostCOP   *float64 `json:"estimated_cost_cop,omitempty"`
	EstimatedMarginCOP *float64 `json:"estimated_margin_cop,omitempty"`
}

type Candidate struct {
	Vehicle            entities.AssignmentVehicle `json:"vehicle"`
	EmptyLeg           *LegEstimate               `json:"empty_leg"`
	ServiceLeg         *LegEstimate               `json:"service_leg"`
	TotalDistanceKM    *float64                   `json:"total_distance_km"`
	CostEstimate       CostEstimate               `json:"cost_estimate"`
	RoutingStatus      string                     `json:"routing_status"`
	RoutingUnavailable string                     `json:"routing_unavailable_reason,omitempty"`
}

type Result struct {
	ServiceRequest RequestView `json:"service_request"`
	Candidates     []Candidate `json:"candidates"`
}

type RecommendationOption struct {
	VehicleID           string                     `json:"vehicle_id"`
	Plate               string                     `json:"placa"`
	Vehicle             entities.AssignmentVehicle `json:"vehiculo"`
	Driver              entities.AssignmentDriver  `json:"conductor"`
	EmptyKM             *float64                   `json:"km_vacios"`
	ServiceKM           *float64                   `json:"km_servicio"`
	TotalEstimatedKM    *float64                   `json:"km_totales_estimados"`
	EstimatedCostCOP    *float64                   `json:"costo_estimado"`
	ProjectedMarginCOP  *float64                   `json:"margen_proyectado"`
	MarginPercentage    *float64                   `json:"porcentaje_margen"`
	Recommended         bool                       `json:"recomendado"`
	CriteriaExplanation string                     `json:"explicacion_criterios"`
	RoutingStatus       string                     `json:"estado_ruta"`
	RoutingUnavailable  string                     `json:"detalle_ruta,omitempty"`
	CostEstimate        CostEstimate               `json:"detalle_costos"`
}

type RecommendationsResult struct {
	ServiceRequestID string                 `json:"solicitud_id"`
	AgreedFareCOP    float64                `json:"tarifa_pactada"`
	Alternatives     []RecommendationOption `json:"alternativas"`
}

func (s *Service) Candidates(ctx context.Context, tenantID, actorUserID, tenantUserID, requestID string) (*Result, error) {
	request, vehicles, err := s.store.FindAssignmentCandidates(ctx, tenantID, actorUserID, tenantUserID, requestID)
	if err != nil {
		return nil, err
	}
	if request == nil {
		return nil, entities.ErrAssignmentRequestNotFound
	}

	result := &Result{
		ServiceRequest: RequestView{
			ID: request.ID, Status: request.Status,
			PickupAddress: request.OriginAddress, PickupLatitude: request.OriginLatitude,
			PickupLongitude: request.OriginLongitude, DestinationAddress: request.DestinationAddress,
			DestinationLatitude: request.DestinationLatitude, DestinationLongitude: request.DestinationLongitude,
			ScheduledAt:    request.ScheduledAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
			PassengerCount: request.PassengerCount, AgreedFareCOP: request.AgreedFareCOP,
		},
		Candidates: make([]Candidate, 0, len(vehicles)),
	}

	var serviceLeg *LegEstimate
	if request.OriginLatitude != nil && request.OriginLongitude != nil &&
		request.DestinationLatitude != nil && request.DestinationLongitude != nil {
		if route, routeErr := s.routes.EstimateForUser(ctx, tenantID, actorUserID, tenantUserID, []entities.Waypoint{
			{Lat: *request.OriginLatitude, Lon: *request.OriginLongitude},
			{Lat: *request.DestinationLatitude, Lon: *request.DestinationLongitude},
		}, "car"); routeErr == nil && route != nil {
			serviceLeg = toLegEstimate(route)
		}
	}

	for _, vehicle := range vehicles {
		candidate := Candidate{Vehicle: vehicle, ServiceLeg: serviceLeg, RoutingStatus: "ready"}
		if vehicle.CurrentLocation == nil {
			candidate.RoutingStatus = "incomplete"
			candidate.RoutingUnavailable = "vehicle_location_not_available"
			candidate.CostEstimate = unavailableCost(vehicle, "vehicle_location_not_available")
			result.Candidates = append(result.Candidates, candidate)
			continue
		}
		if request.OriginLatitude == nil || request.OriginLongitude == nil {
			candidate.RoutingStatus = "incomplete"
			candidate.RoutingUnavailable = "pickup_coordinates_not_available"
			candidate.CostEstimate = unavailableCost(vehicle, "pickup_coordinates_not_available")
			result.Candidates = append(result.Candidates, candidate)
			continue
		}

		emptyRoute, routeErr := s.routes.EstimateForUser(ctx, tenantID, actorUserID, tenantUserID, []entities.Waypoint{
			{Lat: vehicle.CurrentLocation.Latitude, Lon: vehicle.CurrentLocation.Longitude},
			{Lat: *request.OriginLatitude, Lon: *request.OriginLongitude},
		}, "car")
		if routeErr != nil || emptyRoute == nil {
			candidate.RoutingStatus = "incomplete"
			candidate.RoutingUnavailable = "empty_route_not_available"
			candidate.CostEstimate = unavailableCost(vehicle, "empty_route_not_available")
			result.Candidates = append(result.Candidates, candidate)
			continue
		}
		candidate.EmptyLeg = toLegEstimate(emptyRoute)
		if serviceLeg == nil {
			candidate.RoutingStatus = "partial"
			candidate.RoutingUnavailable = "service_route_not_available"
		}
		candidate.TotalDistanceKM = floatPointer(candidate.EmptyLeg.DistanceKM)
		if serviceLeg != nil {
			candidate.TotalDistanceKM = floatPointer(candidate.EmptyLeg.DistanceKM + serviceLeg.DistanceKM)
		}
		candidate.CostEstimate = estimateCost(vehicle, request.AgreedFareCOP, candidate.EmptyLeg, serviceLeg)
		result.Candidates = append(result.Candidates, candidate)
	}
	return result, nil
}

func (s *Service) Recommendations(ctx context.Context, tenantID, actorUserID, tenantUserID, requestID string) (*RecommendationsResult, error) {
	result, err := s.Candidates(ctx, tenantID, actorUserID, tenantUserID, requestID)
	if err != nil {
		return nil, err
	}
	options := make([]RecommendationOption, 0, len(result.Candidates))
	best := -1
	for i, candidate := range result.Candidates {
		option := RecommendationOption{
			VehicleID: candidate.Vehicle.ID, Plate: candidate.Vehicle.Plate,
			Vehicle: candidate.Vehicle, Driver: candidate.Vehicle.Driver,
			TotalEstimatedKM:   candidate.TotalDistanceKM,
			EstimatedCostCOP:   candidate.CostEstimate.EstimatedCostCOP,
			ProjectedMarginCOP: candidate.CostEstimate.EstimatedMarginCOP,
			Recommended:        false, RoutingStatus: candidate.RoutingStatus,
			RoutingUnavailable: candidate.RoutingUnavailable,
			CostEstimate:       candidate.CostEstimate,
		}
		if candidate.EmptyLeg != nil {
			option.EmptyKM = floatPointer(candidate.EmptyLeg.DistanceKM)
		}
		if candidate.ServiceLeg != nil {
			option.ServiceKM = floatPointer(candidate.ServiceLeg.DistanceKM)
		}
		if candidate.CostEstimate.EstimatedMarginCOP != nil && result.ServiceRequest.AgreedFareCOP > 0 {
			option.MarginPercentage = floatPointer(round(
				*candidate.CostEstimate.EstimatedMarginCOP/result.ServiceRequest.AgreedFareCOP*100, 2))
			if candidate.RoutingStatus == "ready" && candidate.CostEstimate.Available &&
				(best < 0 || *candidate.CostEstimate.EstimatedMarginCOP >
					*result.Candidates[best].CostEstimate.EstimatedMarginCOP) {
				best = i
			}
		}
		switch {
		case candidate.RoutingUnavailable == "vehicle_location_not_available":
			option.CriteriaExplanation = "No hay una ubicación telemétrica disponible para el vehículo."
		case candidate.RoutingUnavailable == "pickup_coordinates_not_available":
			option.CriteriaExplanation = "La solicitud no tiene coordenadas de recogida."
		case candidate.RoutingUnavailable == "empty_route_not_available":
			option.CriteriaExplanation = "No se pudo calcular el recorrido vacío hasta la recogida."
		case candidate.RoutingUnavailable == "service_route_not_available":
			option.CriteriaExplanation = "Se calculó el recorrido vacío, pero no el recorrido del servicio."
		case !candidate.CostEstimate.Available:
			option.CriteriaExplanation = "Configura el costo por kilómetro del vehículo para estimar costos y margen."
		case result.ServiceRequest.AgreedFareCOP <= 0:
			option.CriteriaExplanation = "La solicitud no tiene tarifa pactada para calcular el margen."
		default:
			option.CriteriaExplanation = "Alternativa elegible para comparar costo y margen estimado."
		}
		options = append(options, option)
	}
	if best >= 0 {
		options[best].Recommended = true
		options[best].CriteriaExplanation = "Mayor margen estimado entre los vehículos elegibles."
		for i := range options {
			if i != best && options[i].CriteriaExplanation == "Alternativa elegible para comparar costo y margen estimado." {
				options[i].CriteriaExplanation = "Margen estimado inferior al de la alternativa recomendada."
			}
		}
	}
	sort.SliceStable(options, func(i, j int) bool {
		if options[i].ProjectedMarginCOP == nil {
			return false
		}
		if options[j].ProjectedMarginCOP == nil {
			return true
		}
		return *options[i].ProjectedMarginCOP > *options[j].ProjectedMarginCOP
	})
	return &RecommendationsResult{
		ServiceRequestID: result.ServiceRequest.ID,
		AgreedFareCOP:    result.ServiceRequest.AgreedFareCOP,
		Alternatives:     options,
	}, nil
}

func estimateCost(vehicle entities.AssignmentVehicle, fare float64, empty, service *LegEstimate) CostEstimate {
	estimate := CostEstimate{
		Available: true, Currency: "COP", Scope: "empty_leg_only",
		CostPerKMCOP: vehicle.CostPerKMCOP, DispatchCostCOP: vehicle.DispatchCostCOP,
	}
	if vehicle.CostPerKMCOP <= 0 {
		return unavailableCost(vehicle, "vehicle_cost_per_km_not_configured")
	}
	emptyCost := round(empty.DistanceKM*vehicle.CostPerKMCOP, 2)
	estimate.EmptyLegCOP = floatPointer(emptyCost)
	if service != nil {
		serviceCost := round(service.DistanceKM*vehicle.CostPerKMCOP, 2)
		estimate.ServiceLegCOP = floatPointer(serviceCost)
		estimate.Scope = "empty_and_service_legs"
		total := round(emptyCost+serviceCost+vehicle.DispatchCostCOP, 2)
		estimate.EstimatedCostCOP = floatPointer(total)
		estimate.EstimatedMarginCOP = floatPointer(round(fare-total, 2))
		return estimate
	}
	total := round(emptyCost+vehicle.DispatchCostCOP, 2)
	estimate.EstimatedCostCOP = floatPointer(total)
	return estimate
}

func unavailableCost(vehicle entities.AssignmentVehicle, reason string) CostEstimate {
	return CostEstimate{
		Available: false, Reason: reason, Currency: "COP",
		CostPerKMCOP: vehicle.CostPerKMCOP, DispatchCostCOP: vehicle.DispatchCostCOP,
	}
}

func toLegEstimate(route *routing.RouteEstimate) *LegEstimate {
	return &LegEstimate{
		DistanceKM:         round(route.DistanceM/1000, 3),
		DurationS:          route.DurationS,
		DurationInTrafficS: route.DurationInTrafficS,
	}
}

func round(value float64, places int) float64 {
	factor := math.Pow10(places)
	return math.Round(value*factor) / factor
}

func floatPointer(value float64) *float64 { return &value }
