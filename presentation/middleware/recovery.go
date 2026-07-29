package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/logging"
	"ms-vehitrack/presentation/responses"
)

func Recovery() gin.HandlerFunc {
	return gin.CustomRecovery(func(c *gin.Context, recovered any) {
		logging.LogComponent("RECOVERY", "operation=panic recovered="+stringifyRecovered(recovered))
		responses.ErrorFromApp(c, presentationerrors.New(http.StatusInternalServerError, "internal-server-error", "Internal Error"))
	})
}

func stringifyRecovered(recovered any) string {
	switch value := recovered.(type) {
	case error:
		return value.Error()
	case string:
		return value
	default:
		return "unknown"
	}
}
