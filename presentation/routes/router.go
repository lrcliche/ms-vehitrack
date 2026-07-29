package routes

import (
	"net/http"

	"ms-vehitrack/presentation/container"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"

	"github.com/gin-gonic/gin"
)

func New(appContainer *container.Container) *gin.Engine {
	engine := gin.New()
	engine.Use(middleware.HTTPTrace())
	engine.Use(middleware.Recovery())

	engine.GET("/health", func(c *gin.Context) {
		responses.Success(c, http.StatusOK, gin.H{"status": "ok"})
	})

	telemetryHandler := appContainer.ResolveTelemetryHandler()

	v1 := engine.Group("/api/v1")
	{
		v1.POST("/telemetry", telemetryHandler.Publish)
	}

	return engine
}
