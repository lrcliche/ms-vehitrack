package dto

type BusinessLoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=1,max=72"`
	TenantID string `json:"tenant_id" binding:"required,uuid"`
}

type BusinessPasswordResetRequest struct {
	Email    string `json:"email" binding:"required,email,max=320"`
	TenantID string `json:"tenant_id" binding:"required,uuid"`
}

type BusinessPasswordResetConfirmRequest struct {
	TenantID    string `json:"tenant_id" binding:"required,uuid"`
	Token       string `json:"token" binding:"required,min=32,max=256"`
	NewPassword string `json:"new_password" binding:"required,min=12,max=72"`
}

type BusinessCreateUserRequest struct {
	Email    string `json:"email" binding:"required,email,max=320"`
	FullName string `json:"full_name" binding:"required,min=1,max=200"`
	Password string `json:"password" binding:"required,min=12,max=72"`
	RoleCode string `json:"role_code" binding:"omitempty,max=64"`
}
