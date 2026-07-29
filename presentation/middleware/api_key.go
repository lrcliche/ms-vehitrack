package middleware

import (
	"crypto/subtle"
	"net/http"

	"github.com/gin-gonic/gin"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/responses"
)

const apiKeyHeader = "X-API-Key"

// APIKeyAuth rejects requests that do not present a valid API key.
func APIKeyAuth(expectedAPIKey string) gin.HandlerFunc {
	expected := []byte(expectedAPIKey)

	return func(c *gin.Context) {
		provided := []byte(c.GetHeader(apiKeyHeader))
		if subtle.ConstantTimeCompare(provided, expected) != 1 {
			responses.ErrorFromApp(c, presentationerrors.New(http.StatusUnauthorized, "unauthorized", "Invalid or missing API key"))
			c.Abort()
			return
		}
		c.Next()
	}
}
