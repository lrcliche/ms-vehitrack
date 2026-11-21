package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/application/assignments"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"
)

type AssignmentServiceResolver interface {
	ResolveAssignmentService() (*assignments.Service, bool)
}

type AssignmentHandler struct {
	resolver AssignmentServiceResolver
}

func NewAssignmentHandler(resolver AssignmentServiceResolver) *AssignmentHandler {
	return &AssignmentHandler{resolver: resolver}
}

func (h *AssignmentHandler) Candidates(c *gin.Context) {
	claims, ok := middleware.BusinessClaimsFromContext(c)
	if !ok {
		responses.Error(c, http.StatusUnauthorized, "unauthorized", "valid business token required")
		return
	}
	var uri dto.AssignmentCandidatesURI
	if err := c.ShouldBindUri(&uri); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid service request id"))
		return
	}
	svc, ok := h.resolver.ResolveAssignmentService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "assignments-unavailable", "assignment service is not configured")
		return
	}
	result, err := svc.Candidates(c.Request.Context(), claims.TenantID, claims.Subject,
		claims.TenantUserID, uri.ServiceRequestID)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, result)
}

func (h *AssignmentHandler) Recommendations(c *gin.Context) {
	claims, ok := middleware.BusinessClaimsFromContext(c)
	if !ok {
		responses.Error(c, http.StatusUnauthorized, "unauthorized", "valid business token required")
		return
	}
	var uri dto.AssignmentCandidatesURI
	if err := c.ShouldBindUri(&uri); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid service request id"))
		return
	}
	svc, ok := h.resolver.ResolveAssignmentService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "assignments-unavailable", "assignment service is not configured")
		return
	}
	result, err := svc.Recommendations(c.Request.Context(), claims.TenantID, claims.Subject,
		claims.TenantUserID, uri.ServiceRequestID)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, result)
}

func (h *AssignmentHandler) Confirm(c *gin.Context) {
	claims, ok := middleware.BusinessClaimsFromContext(c)
	if !ok {
		responses.Error(c, http.StatusUnauthorized, "unauthorized", "valid business token required")
		return
	}
	var req dto.EnterpriseAssignmentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid assignment request"))
		return
	}
	svc, ok := h.resolver.ResolveAssignmentService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "assignments-unavailable", "assignment service is not configured")
		return
	}
	result, err := svc.Confirm(c.Request.Context(), claims.TenantID, claims.Subject, claims.TenantUserID,
		entities.EnterpriseAssignmentCommand{RequestID: req.ServiceRequestID, VehicleID: req.VehicleID,
			DriverID: req.DriverID, Reason: req.SelectionReason})
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusCreated, result)
}
