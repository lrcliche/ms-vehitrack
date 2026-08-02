package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/application/geocoding"
	"ms-vehitrack/presentation/dto"
	presentationerrors "ms-vehitrack/presentation/errors"
	"ms-vehitrack/presentation/middleware"
	"ms-vehitrack/presentation/responses"
)

// GeocodingServiceResolver lo cumple el container.
type GeocodingServiceResolver interface {
	ResolveGeocodingService() (*geocoding.Service, bool)
}

type GeocodeHandler struct {
	resolver GeocodingServiceResolver
}

func NewGeocodeHandler(resolver GeocodingServiceResolver) *GeocodeHandler {
	return &GeocodeHandler{resolver: resolver}
}

func (h *GeocodeHandler) service(c *gin.Context) (*geocoding.Service, bool) {
	svc, ok := h.resolver.ResolveGeocodingService()
	if !ok {
		responses.Error(c, http.StatusServiceUnavailable, "geocode-unavailable",
			"geocoder not configured (enable POSTGRES)")
	}
	return svc, ok
}

// Autocomplete = GET /v1/geocode/autocomplete?q=&muni=&lat=&lon=&limit=. Solo local, sin
// Nominatim.
func (h *GeocodeHandler) Autocomplete(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	lat, lon := queryLatLon(c)
	results, err := svc.Autocomplete(c.Request.Context(),
		c.Query("q"), c.Query("muni"), lat, lon, queryLimit(c))
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, gin.H{"results": results})
}

// Search = POST /v1/geocode/search. Cascada local -> Nominatim -> persistir.
func (h *GeocodeHandler) Search(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.SearchRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid search request"))
		return
	}
	limit := req.Limit
	if limit <= 0 {
		limit = 8
	}
	results, err := svc.Search(c.Request.Context(), middleware.DeviceIDFromContext(c),
		req.Query, req.MunicipalityID, req.Lat, req.Lon, limit)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, gin.H{"results": results})
}

// Reverse = POST /v1/geocode/reverse.
func (h *GeocodeHandler) Reverse(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.ReverseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid reverse request"))
		return
	}
	raw, err := svc.Reverse(c.Request.Context(), middleware.DeviceIDFromContext(c),
		req.Lat, req.Lon, req.MaxDistanceM)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

// Normalize = POST /v1/geocode/normalize.
func (h *GeocodeHandler) Normalize(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var req dto.NormalizeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		responses.ErrorFromApp(c, presentationerrors.BadRequest("invalid normalize request"))
		return
	}
	out, err := svc.Normalize(c.Request.Context(), req.Text)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, gin.H{"normalized": out})
}

// Dictionary = GET /v1/dictionary?since_version=N. Sin tenant (global).
func (h *GeocodeHandler) Dictionary(c *gin.Context) {
	svc, ok := h.service(c)
	if !ok {
		return
	}
	var since *int
	if raw := c.Query("since_version"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			since = &n
		}
	}
	raw, err := svc.Dictionary(c.Request.Context(), since)
	if err != nil {
		responses.ErrorFromApp(c, presentationerrors.Map(err))
		return
	}
	responses.Success(c, http.StatusOK, json.RawMessage(raw))
}

func queryLatLon(c *gin.Context) (*float64, *float64) {
	var lat, lon *float64
	if v, err := strconv.ParseFloat(c.Query("lat"), 64); err == nil {
		lat = &v
	}
	if v, err := strconv.ParseFloat(c.Query("lon"), 64); err == nil {
		lon = &v
	}
	return lat, lon
}

func queryLimit(c *gin.Context) int {
	if n, err := strconv.Atoi(c.Query("limit")); err == nil && n > 0 {
		return n
	}
	return 8
}
