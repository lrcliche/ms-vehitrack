package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"
)

// SyncChanges = GET /v1/sync/changes?since=N&entities=a,b&limit=M. TENANT-SCOPED. Devuelve el
// jsonb de device.fnc_sync_changes tal cual (passthrough): {next_version, has_more, entities}.
// El delta esta paginado POR VERSION: si has_more es true, el cliente vuelve a pedir con el
// next_version recibido.
func (h *UserDataHandler) SyncChanges(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}

	var since *int64
	if raw := c.Query("since"); raw != "" {
		if n, err := strconv.ParseInt(raw, 10, 64); err == nil {
			since = &n
		}
	}
	var limit *int
	if raw := c.Query("limit"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			limit = &n
		}
	}
	var ents []string
	if raw := c.Query("entities"); raw != "" {
		for _, e := range strings.Split(raw, ",") {
			if e = strings.TrimSpace(e); e != "" {
				ents = append(ents, e)
			}
		}
	}

	raw, err := svc.SyncChanges(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c), ents, since, limit)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

// SyncPush = POST /v1/sync/push (body {items:[...]}). TENANT-SCOPED. Devuelve el jsonb de
// device.prc_sync_push tal cual: {applied, skipped, failed[], next_version}. Reenviar el
// mismo lote es esperado (cola offline idempotente), no un 409.
func (h *UserDataHandler) SyncPush(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.SyncPushRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid sync push request"))
		return
	}
	raw, err := svc.SyncPush(c.Request.Context(),
		middleware.TenantIDFromContext(c), middleware.DeviceIDFromContext(c), req.Items)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}
