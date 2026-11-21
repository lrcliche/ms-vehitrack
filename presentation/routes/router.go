package routes

import (
	"context"
	"net/http"
	"time"

	"ms-vehitrack/presentation/container"
	"ms-vehitrack/presentation/handlers"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"

	"github.com/gin-gonic/gin"
)

func New(appContainer *container.Container) *gin.Engine {
	cfg := appContainer.Config()
	if cfg.AppEnv == "production" || cfg.AppEnv == "prod" {
		gin.SetMode(gin.ReleaseMode)
	}

	engine := gin.New()
	engine.Use(middleware.Recovery())
	engine.Use(middleware.SecurityHeaders())
	engine.Use(middleware.HTTPTrace())
	engine.Use(middleware.BodyLimit(cfg.MaxBodyBytes))

	engine.GET("/health", func(c *gin.Context) {
		responses.Success(c, http.StatusOK, gin.H{"status": "ok"})
	})

	engine.GET("/ready", func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()

		if err := appContainer.Ready(ctx); err != nil {
			responses.Error(c, http.StatusServiceUnavailable, "not-ready", "Service dependencies are not ready")
			return
		}

		responses.Success(c, http.StatusOK, gin.H{"status": "ready"})
	})

	telemetryHandler := appContainer.ResolveTelemetryHandler()
	trafficHandler := handlers.NewTrafficHandler(appContainer)
	geocodeHandler := handlers.NewGeocodeHandler(appContainer)
	offlineHandler := handlers.NewOfflineHandler(appContainer)
	userDataHandler := handlers.NewUserDataHandler(appContainer)
	routingHandler := handlers.NewRoutingHandler(appContainer)
	assignmentHandler := handlers.NewAssignmentHandler(appContainer)
	enterpriseOperationsHandler := handlers.NewEnterpriseOperationsHandler(appContainer)
	enterpriseRequestHandler := handlers.NewEnterpriseRequestHandler(appContainer)
	businessAuthHandler := handlers.NewBusinessAuthHandler(appContainer)
	trackingHandler := handlers.NewTrackingHandler(appContainer)
	trafficBBoxHandler := handlers.NewTrafficBBoxHandler(appContainer)

	v1 := engine.Group("/api/v1")
	v1.Use(middleware.APIKeyAuth(cfg.APIKey))
	v1.Use(middleware.RateLimit(cfg.RateLimitRPS, cfg.RateLimitBurst))
	{
		v1.POST("/telemetry", telemetryHandler.Publish)
		v1.POST("/traffic/batches", trafficHandler.IngestBatch)
		v1.GET("/traffic/aggregates", trafficHandler.Aggregates)

		// F7 — Lecturas de trafico por bbox: GLOBALES (traffic.* son agregados anonimos sin
		// RLS). No llevan tenant. Se agregan junto al path GCP heredado, sin tocarlo.
		v1.GET("/traffic/live", trafficBBoxHandler.Live)
		v1.GET("/traffic/profile", trafficBBoxHandler.Profile)

		// Geocoding y diccionario: rutas GLOBALES (geo.* no lleva tenant). DeviceContext solo
		// extrae X-Device-Id para auditoría/ranking; no resuelve tenant.
		geo := v1.Group("")
		geo.Use(middleware.DeviceContext())
		{
			geo.GET("/geocode/autocomplete", geocodeHandler.Autocomplete)
			geo.POST("/geocode/search", geocodeHandler.Search)
			geo.POST("/geocode/reverse", geocodeHandler.Reverse)
			geo.POST("/geocode/normalize", geocodeHandler.Normalize)
			geo.GET("/dictionary", geocodeHandler.Dictionary)
		}

		// Paquetes offline GLOBALES (offline.* no lleva tenant): manifiesto de región y
		// descarga predictiva por ruta. DeviceContext solo extrae X-Device-Id.
		regionsGlobal := v1.Group("")
		regionsGlobal.Use(middleware.DeviceContext())
		{
			regionsGlobal.GET("/regions/:id/manifest", offlineHandler.Manifest)
			regionsGlobal.POST("/regions/for-route", offlineHandler.RegionsForRoute)
		}

		// Paquetes offline TENANT-SCOPED (device.device_package tiene RLS): listado de
		// instalados y tracking install/touch/remove. TenantContext resuelve y fija el tenant.
		regionsTenant := v1.Group("")
		regionsTenant.Use(middleware.TenantContext(appContainer.ResolveTenantResolver()))
		{
			regionsTenant.GET("/regions/installed", offlineHandler.ListInstalled)
			regionsTenant.POST("/regions/:id/installed", offlineHandler.TrackPackage)
		}

		// Datos del usuario + sync bidireccional: TENANT-SCOPED (device.* con RLS). El device
		// y el tenant salen de TenantContext; el store abre WithTenantTx con ese tenant.
		userData := v1.Group("")
		userData.Use(middleware.TenantContext(appContainer.ResolveTenantResolver()))
		{
			userData.GET("/favorites", userDataHandler.ListFavorites)
			userData.PUT("/favorites/:id", userDataHandler.UpsertFavorite)
			userData.DELETE("/favorites/:id", userDataHandler.DeleteFavorite)
			userData.PUT("/places/:id", userDataHandler.UpsertPlace)
			userData.PUT("/geofences/:id", userDataHandler.UpsertGeofence)
			userData.POST("/geofences/events", userDataHandler.RecordGeofenceEvent)
			userData.POST("/geofences/evaluate", userDataHandler.EvaluateGeofence)
			userData.PUT("/settings/:key", userDataHandler.UpsertSetting)
			userData.GET("/sync/changes", userDataHandler.SyncChanges)
			userData.POST("/sync/push", userDataHandler.SyncPush)
		}

		// F4 (ruteo) + F6 (ingesta por lote, viajes, OBD): TENANT-SCOPED. routing.route_request,
		// tracking.* y device.obd_session llevan RLS; el device y el tenant salen de
		// TenantContext y el store abre WithTenantTx con ese tenant.
		tracked := v1.Group("")
		tracked.Use(middleware.TenantContext(appContainer.ResolveTenantResolver()))
		{
			tracked.POST("/routes", routingHandler.Route)
			tracked.POST("/telemetry/batch", trackingHandler.TelemetryBatch)
			tracked.POST("/trips", trackingHandler.UpsertTrip)
			tracked.POST("/trips/:id/close", trackingHandler.CloseTrip)
			tracked.POST("/obd/sessions", trackingHandler.UpsertObdSession)
		}

		// Registro de dispositivo: la UNICA ruta NO tenant-scoped. Personal (provision, DEFINER,
		// sin tenant) vs fleet (register, con tenant) se decide en el servicio segun el body. Se
		// acota POR IP porque expone la fabrica de tenants personales sin auth de negocio (R4).
		v1.POST("/devices/register",
			middleware.IPRateLimit(cfg.RegisterRateRPS, cfg.RegisterRateBurst),
			userDataHandler.Register)
	}

	// V2 empresarial: login emite el bearer token; todas las operaciones funcionales del grupo
	// quedan bajo JWT. La autenticación de v1 no cambia.
	v2 := engine.Group("/api/v2")
	v2.Use(middleware.RateLimit(cfg.RateLimitRPS, cfg.RateLimitBurst))
	{
		v2.POST("/auth/login",
			middleware.IPRateLimit(cfg.RegisterRateRPS, cfg.RegisterRateBurst), businessAuthHandler.Login)

		protected := v2.Group("")
		protected.Use(middleware.BusinessJWTAuth(cfg.JWTSigningKey, cfg.JWTIssuer))
		protected.POST("/routes", routingHandler.RouteV2)
		protected.GET("/service-requests/:serviceRequestID/assignment-candidates", assignmentHandler.Candidates)
		protected.GET("/enterprise/dashboard/kpis", enterpriseOperationsHandler.DashboardKPIs)
		protected.GET("/enterprise/dashboard/financial-summary", enterpriseOperationsHandler.FinancialSummary)
		protected.POST("/enterprise/vehicles", enterpriseOperationsHandler.UpsertVehicle)
		protected.PUT("/enterprise/vehicles/:id", enterpriseOperationsHandler.UpsertVehicle)
		protected.GET("/enterprise/vehicles", enterpriseOperationsHandler.ListVehicles)
		protected.PATCH("/enterprise/vehicles/:id/status", enterpriseOperationsHandler.UpdateVehicleStatus)
		protected.POST("/enterprise/drivers", enterpriseOperationsHandler.UpsertDriver)
		protected.PUT("/enterprise/drivers/:id", enterpriseOperationsHandler.UpsertDriver)
		protected.GET("/enterprise/drivers", enterpriseOperationsHandler.ListDrivers)
		protected.PATCH("/enterprise/drivers/:id/availability", enterpriseOperationsHandler.UpdateDriverAvailability)
		protected.POST("/enterprise/requests", enterpriseRequestHandler.Create)
		protected.GET("/enterprise/requests", enterpriseOperationsHandler.ListServiceRequests)
		protected.PATCH("/enterprise/requests/:serviceRequestID/status", enterpriseOperationsHandler.ChangeServiceRequestStatus)
		protected.GET("/enterprise/requests/:serviceRequestID/recommendations", assignmentHandler.Recommendations)
		protected.POST("/enterprise/assignments", assignmentHandler.Confirm)
		protected.POST("/enterprise/trips/:assignmentID/close-expenses", enterpriseOperationsHandler.CloseTripExpenses)
		protected.GET("/enterprise/reports/profitability", enterpriseOperationsHandler.ProfitabilityReport)
		protected.POST("/auth/users", businessAuthHandler.CreateUser)
	}

	return engine
}
