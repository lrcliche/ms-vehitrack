package dto

type AssignmentCandidatesURI struct {
	ServiceRequestID string `uri:"serviceRequestID" binding:"required,uuid"`
}
