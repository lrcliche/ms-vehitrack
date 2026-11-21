package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/application/businessauth"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"
)

type BusinessAuthServiceResolver interface {
	ResolveBusinessAuthService() (*businessauth.Service, bool)
}

type BusinessAuthHandler struct {
	resolver BusinessAuthServiceResolver
}

func NewBusinessAuthHandler(resolver BusinessAuthServiceResolver) *BusinessAuthHandler {
	return &BusinessAuthHandler{resolver: resolver}
}

func (h *BusinessAuthHandler) Login(c *gin.Context) {
	var req dto.BusinessLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid login request"))
		return
	}
	svc, ok := h.resolver.ResolveBusinessAuthService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "auth-unavailable", "business authentication is not configured")
		return
	}
	result, err := svc.Login(c.Request.Context(), req.Email, req.Password, req.TenantID)
	if err != nil {
		switch {
		case errors.Is(err, entities.ErrInvalidBusinessCredentials):
			responses.ErrorFromApp(c, presentationerrors.New(http.StatusUnauthorized, "unauthorized", "Invalid credentials"))
		case errors.Is(err, businessauth.ErrTokenServiceUnavailable):
			responses.Error(c, http.StatusServiceUnavailable, "auth-unavailable", "v2 token signing is not configured")
		default:
			responses.Error(c, http.StatusInternalServerError, "internal-server-error", "Login failed")
		}
		return
	}
	responses.Success(c, http.StatusOK, gin.H{
		"access_token": result.AccessToken,
		"token_type":   "Bearer",
		"expires_in":   result.ExpiresIn,
		"user": gin.H{
			"id":        result.UserID,
			"tenant_id": result.TenantID,
		},
	})
}

func (h *BusinessAuthHandler) CreateUser(c *gin.Context) {
	claims, ok := middleware.BusinessClaimsFromContext(c)
	if !ok {
		responses.Error(c, http.StatusUnauthorized, "unauthorized", "valid business token required")
		return
	}
	var req dto.BusinessCreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid user request"))
		return
	}
	svc, ok := h.resolver.ResolveBusinessAuthService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "auth-unavailable", "business authentication is not configured")
		return
	}
	user, err := svc.CreateUser(c.Request.Context(), claims.TenantID, claims.Subject,
		claims.TenantUserID, req.Email, req.FullName, req.Password, req.RoleCode)
	if err != nil {
		switch {
		case errors.Is(err, entities.ErrBusinessUserForbidden):
			responses.Error(c, http.StatusForbidden, "forbidden", "insufficient permission to create the user or assign the requested role")
		case errors.Is(err, entities.ErrBusinessRoleNotAssignable):
			responses.Error(c, http.StatusBadRequest, "invalid-role", "role is inactive, outside the tenant, or not assignable")
		case errors.Is(err, entities.ErrBusinessEmailAlreadyExists):
			responses.Error(c, http.StatusConflict, "email-already-exists", "a user with this email already exists")
		case errors.Is(err, entities.ErrInvalidBusinessUser):
			responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid user request"))
		default:
			responses.Error(c, http.StatusInternalServerError, "internal-server-error", "User creation failed")
		}
		return
	}
	responses.Success(c, http.StatusCreated, gin.H{
		"id":             user.ID,
		"tenant_user_id": user.TenantUserID,
		"email":          user.Email,
		"full_name":      user.FullName,
		"role_code":      user.RoleCode,
	})
}
