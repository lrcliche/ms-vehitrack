package routes

import (
	"context"
	"net/http"
	"time"

	"ms-vehitrack/presentation/container"
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

	v1 := engine.Group("/api/v1")
	v1.Use(middleware.APIKeyAuth(cfg.APIKey))
	v1.Use(middleware.RateLimit(cfg.RateLimitRPS, cfg.RateLimitBurst))
	{
		v1.POST("/telemetry", telemetryHandler.Publish)
	}

	return engine
}
