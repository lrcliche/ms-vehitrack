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

	v1 := engine.Group("/api/v1")
	v1.Use(middleware.APIKeyAuth(cfg.APIKey))
	v1.Use(middleware.RateLimit(cfg.RateLimitRPS, cfg.RateLimitBurst))
	{
		v1.POST("/telemetry", telemetryHandler.Publish)
		v1.POST("/traffic/batches", trafficHandler.IngestBatch)
		v1.GET("/traffic/aggregates", trafficHandler.Aggregates)

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
	}

	return engine
}
