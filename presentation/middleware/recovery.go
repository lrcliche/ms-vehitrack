package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/responses"
)

func Recovery() gin.HandlerFunc {
	return gin.CustomRecovery(func(c *gin.Context, recovered any) {
		responses.ErrorFromApp(c, presentationerrors.New(http.StatusInternalServerError, "internal-server-error", "Internal Error"))
	})
}
