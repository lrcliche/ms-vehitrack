package middleware

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/application/businessauth"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/responses"
)

const businessClaimsKey = "vt.business_claims"

func BusinessJWTAuth(signingKey, issuer string) gin.HandlerFunc {
	auth := businessauth.NewService(nil, signingKey, issuer)
	return func(c *gin.Context) {
		if len(signingKey) < 32 || issuer == "" {
			responses.Error(c, http.StatusServiceUnavailable, "auth-unavailable", "v2 token validation is not configured")
			c.Abort()
			return
		}
		header := strings.Fields(c.GetHeader("Authorization"))
		if len(header) != 2 || !strings.EqualFold(header[0], "Bearer") {
			responses.ErrorFromApp(c, presentationerrors.New(http.StatusUnauthorized, "unauthorized", "Bearer token required"))
			c.Abort()
			return
		}
		claims, err := auth.ValidateToken(header[1])
		if err != nil {
			if errors.Is(err, businessauth.ErrTokenServiceUnavailable) {
				responses.Error(c, http.StatusServiceUnavailable, "auth-unavailable", "v2 token validation is not configured")
			} else {
				responses.ErrorFromApp(c, presentationerrors.New(http.StatusUnauthorized, "unauthorized", "Invalid or expired bearer token"))
			}
			c.Abort()
			return
		}
		c.Set(businessClaimsKey, claims)
		c.Next()
	}
}

func BusinessClaimsFromContext(c *gin.Context) (*businessauth.TokenClaims, bool) {
	value, ok := c.Get(businessClaimsKey)
	if !ok {
		return nil, false
	}
	claims, ok := value.(*businessauth.TokenClaims)
	return claims, ok && claims != nil
}
