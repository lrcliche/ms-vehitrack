package dto

// SearchRequest = POST /v1/geocode/search.
type SearchRequest struct {
	Query          string   `json:"query" binding:"required"`
	MunicipalityID string   `json:"municipalityId"`
	Lat            *float64 `json:"lat"`
	Lon            *float64 `json:"lon"`
	Limit          int      `json:"limit"`
}

// ReverseRequest = POST /v1/geocode/reverse.
type ReverseRequest struct {
	Lat           float64  `json:"lat" binding:"required"`
	Lon           float64  `json:"lon" binding:"required"`
	MaxDistanceM  *float64 `json:"maxDistanceM"`
}

// NormalizeRequest = POST /v1/geocode/normalize.
type NormalizeRequest struct {
	Text string `json:"text" binding:"required"`
}
