package entities

import "errors"

var (
	ErrAssignmentRequestNotFound      = errors.New("assignment: service request not found")
	ErrAssignmentRequestNotPending    = errors.New("assignment: service request is not pending")
	ErrAssignmentCandidatesForbidden  = errors.New("assignment: permission denied")
	ErrAssignmentCandidateUnavailable = errors.New("assignment: selected vehicle and driver are not eligible")
)
