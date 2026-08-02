package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"

	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/responses"
)

// IPRateLimit es un token bucket POR IP (c.ClientIP()), con su PROPIO juego de buckets, para
// acotar una ruta concreta al margen del RateLimit global. Se usa en POST /v1/devices/register:
// esa ruta expone prc_provision_personal_tenant, el unico camino que crea un tenant + device
// sin autenticacion de negocio. Sin este freno, descubrir el endpoint es una fabrica gratuita
// de tenants (R4). rps/burst son deliberadamente bajos: registrar es raro por dispositivo.
//
// Reutiliza el mismo ipRateLimiter/clientIP del RateLimit global (mismo paquete), pero con una
// instancia separada: los buckets del registro no se mezclan con los del trafico normal.
func IPRateLimit(rps float64, burst int) gin.HandlerFunc {
	limiterSet := newIPRateLimiter(rps, burst)

	return func(c *gin.Context) {
		ip := clientIP(c)
		if !limiterSet.get(ip).Allow() {
			responses.ErrorFromApp(c, presentationerrors.New(
				http.StatusTooManyRequests, "rate-limit-exceeded", "Too many registration attempts"))
			c.Abort()
			return
		}
		c.Next()
	}
}
