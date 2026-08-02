package middleware

import (
	goerrors "errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/infrastructure/tenant"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/responses"
)

// DeviceIDHeader: el device_id viaja en TODA la API (doc 02). El middleware lo lee de aquí
// (más adelante también del JWT) y resuelve el tenant antes de tocar datos.
const DeviceIDHeader = "X-Device-Id"

// Claves en el gin.Context. Los handlers geo leen de aquí y pasan el tenant a
// database.WithTenantTx; nunca reciben tenant_id como parámetro de negocio.
const (
	ctxDeviceID = "vt.device_id"
	ctxTenantID = "vt.tenant_id"
)

// TenantContext resuelve el tenant del device y lo deja en el contexto. Rechaza la petición
// si falta X-Device-Id (400) o si el device no está registrado (404). Este middleware NO va
// en las rutas del path GCP heredado (telemetría/tráfico), que no tienen contexto de tenant;
// solo en las rutas del modelo PG multi-tenant.
func TenantContext(resolver *tenant.Resolver) gin.HandlerFunc {
	return func(c *gin.Context) {
		deviceID := c.GetHeader(DeviceIDHeader)
		if deviceID == "" {
			responses.ErrorFromApp(c, presentationerrors.New(
				http.StatusBadRequest, "INVALID_REQUEST", "missing "+DeviceIDHeader))
			c.Abort()
			return
		}

		tenantID, err := resolver.TenantOf(c.Request.Context(), deviceID)
		if err != nil {
			if goerrors.Is(err, tenant.ErrDeviceUnknown) {
				responses.ErrorFromApp(c, presentationerrors.New(
					http.StatusNotFound, "NOT_FOUND", "device not registered"))
			} else {
				responses.ErrorFromApp(c, presentationerrors.New(
					http.StatusInternalServerError, "internal-server-error", "tenant resolution failed"))
			}
			c.Abort()
			return
		}

		c.Set(ctxDeviceID, deviceID)
		c.Set(ctxTenantID, tenantID)
		c.Next()
	}
}

// DeviceContext solo extrae X-Device-Id y lo deja en el contexto, SIN resolver tenant. Es
// para las rutas globales (geocoding, diccionario): geo.* no lleva tenant, pero las rutinas
// sí quieren el device_id para auditoría y ranking (first_device_id). El device_id es
// opcional aquí: el autocompletado funciona sin él.
func DeviceContext() gin.HandlerFunc {
	return func(c *gin.Context) {
		if deviceID := c.GetHeader(DeviceIDHeader); deviceID != "" {
			c.Set(ctxDeviceID, deviceID)
		}
		c.Next()
	}
}

// DeviceIDFromContext devuelve el device_id resuelto por TenantContext ("" si no está).
func DeviceIDFromContext(c *gin.Context) string {
	if v, ok := c.Get(ctxDeviceID); ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

// TenantIDFromContext devuelve el tenant_id resuelto por TenantContext ("" si no está).
func TenantIDFromContext(c *gin.Context) string {
	if v, ok := c.Get(ctxTenantID); ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}
