package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/responses"
)

// Register = POST /v1/devices/register. Es la UNICA ruta que NO es tenant-scoped: no lleva
// TenantContext, porque el device puede no existir aun (registrarlo es justo el punto que crea
// el contexto de tenant). El servicio decide el camino a partir del body:
//   - tenantId presente -> FLEET: device.prc_register_device dentro del tenant destino (el
//     store lo corre en WithTenantTx con ese tenant; la rutina esta sujeta a RLS).
//   - sin tenantId pero con installId -> PERSONAL: device.prc_provision_personal_tenant, el
//     unico camino de escritura SIN contexto de tenant (SECURITY DEFINER), que crea tenant +
//     device en una transaccion. Idempotente por install_id.
//
// La ruta lleva un rate limit POR IP (middleware.IPRateLimit): es una fabrica de tenants sin
// autenticar de negocio, asi que se acota por IP para que descubrir el endpoint no permita
// crear tenants sin freno (R4). Devuelve el jsonb de la rutina tal cual.
func (h *UserDataHandler) Register(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.RegisterDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid register request"))
		return
	}
	raw, err := svc.Register(c.Request.Context(), entities.RegisterInput{
		DeviceID:   req.DeviceID,
		InstallID:  req.InstallID,
		TenantID:   req.TenantID,
		AccountID:  req.AccountID,
		Platform:   req.Platform,
		OSVersion:  req.OSVersion,
		AppVersion: req.AppVersion,
		Model:      req.Model,
	})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}
