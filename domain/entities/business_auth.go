package entities

import "errors"

var (
	ErrInvalidBusinessCredentials = errors.New("business auth: invalid credentials")
	ErrBusinessRoutingUnavailable = errors.New("business routing store is unavailable")
	ErrBusinessUserForbidden      = errors.New("business auth: user creation forbidden")
	ErrBusinessRoleNotAssignable  = errors.New("business auth: role is not assignable")
	ErrBusinessEmailAlreadyExists = errors.New("business auth: email already exists")
	ErrInvalidBusinessUser        = errors.New("business auth: invalid user input")
)

type BusinessUserCredential struct {
	UserID       string
	TenantUserID string
	TenantID     string
	Email        string
	PasswordHash string
}

type CreateBusinessUserCommand struct {
	TenantID          string
	ActorUserID       string
	ActorTenantUserID string
	Email             string
	FullName          string
	PasswordHash      string
	RoleCode          string
}

type CreatedBusinessUser struct {
	ID           string
	TenantUserID string
	RoleCode     string
	Email        string
	FullName     string
}
