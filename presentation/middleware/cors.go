package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

var allowedOrigins = map[string]struct{}{
	"https://acalderon474.github.io": {},
	"http://localhost:4200":          {},
}

var allowedMethods = map[string]struct{}{
	http.MethodGet: {}, http.MethodPost: {}, http.MethodPut: {}, http.MethodPatch: {}, http.MethodOptions: {},
}

var allowedHeaders = map[string]struct{}{
	"authorization": {}, "content-type": {},
}

func CORS() gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if _, ok := allowedOrigins[origin]; ok {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
			c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, OPTIONS")
			c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type")
			c.Header("Access-Control-Max-Age", "600")
		}

		if c.Request.Method == http.MethodOptions {
			requestedMethod := c.GetHeader("Access-Control-Request-Method")
			requestedHeaders := strings.Split(c.GetHeader("Access-Control-Request-Headers"), ",")
			_, originAllowed := allowedOrigins[origin]
			_, methodAllowed := allowedMethods[requestedMethod]
			headersAllowed := true
			for _, header := range requestedHeaders {
				if header = strings.ToLower(strings.TrimSpace(header)); header != "" {
					if _, ok := allowedHeaders[header]; !ok {
						headersAllowed = false
						break
					}
				}
			}
			if originAllowed && methodAllowed && headersAllowed {
				c.AbortWithStatus(http.StatusNoContent)
				return
			}
			c.AbortWithStatus(http.StatusForbidden)
			return
		}

		c.Next()
	}
}
