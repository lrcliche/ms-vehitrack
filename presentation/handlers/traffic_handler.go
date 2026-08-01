package handlers

import (
	"net/http"
	"strconv"

	"ms-vehitrack/application/services"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/responses"

	"github.com/gin-gonic/gin"
)

type TrafficServiceResolver interface {
	ResolveTrafficService() (services.TrafficService, bool)
}

type TrafficHandler struct {
	resolver TrafficServiceResolver
}

func NewTrafficHandler(resolver TrafficServiceResolver) *TrafficHandler {
	return &TrafficHandler{resolver: resolver}
}

func (h *TrafficHandler) IngestBatch(c *gin.Context) {
	svc, ok := h.resolver.ResolveTrafficService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "traffic-unavailable",
			"traffic store not configured (enable POSTGRES)")
		return
	}

	var req dto.TrafficBatchRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid batch"))
		return
	}

	batch, err := req.ToDomain()
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}

	result, err := svc.IngestBatch(c.Request.Context(), batch)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}

	responses.Success(c, http.StatusOK, gin.H{
		"batchId":   result.BatchID,
		"accepted":  result.Accepted,
		"duplicate": result.Duplicate,
		"samples":   result.SampleCount,
	})
}

func (h *TrafficHandler) Aggregates(c *gin.Context) {
	svc, ok := h.resolver.ResolveTrafficService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "traffic-unavailable",
			"traffic store not configured (enable POSTGRES)")
		return
	}

	corridor := c.Query("corridor")
	slot := -1
	if raw := c.Query("slot"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			slot = n
		}
	}

	result, err := svc.Aggregates(c.Request.Context(), corridor, slot)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}

	responses.Success(c, http.StatusOK, gin.H{
		"corridor": result.Corridor,
		"slot":     result.Slot,
		"cached":   result.Cached,
		"cells":    result.Cells,
	})
}