package entities

import "errors"

var (
	ErrServiceRequestForbidden        = errors.New("service request: permission denied")
	ErrInvalidServiceRequest          = errors.New("service request: invalid input")
	ErrServiceRequestRouteUnavailable = errors.New("service request: route estimate unavailable")
)
