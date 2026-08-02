// Package nominatim es el cliente HTTP del geocoder de respaldo (127.0.0.1:21001). El ms solo
// le pega cuando geo.fnc_search_place devuelve 0 filas (doc 03 §3, ADR-001); nunca en
// autocompletado. El resultado OK se persiste luego con geo.prc_resolve_from_provider.
package nominatim

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Client habla con una instancia Nominatim detrás del reverse proxy o en localhost.
type Client struct {
	base string
	http *http.Client
}

// NewClient crea el cliente. baseURL p.ej. "http://127.0.0.1:21001". Si hc es nil usa uno con
// timeout razonable.
func NewClient(baseURL string, hc *http.Client) *Client {
	if hc == nil {
		hc = &http.Client{Timeout: 5 * time.Second}
	}
	return &Client{base: strings.TrimRight(baseURL, "/"), http: hc}
}

// Result es una fila cruda de Nominatim. El ms la mapea al payload de
// geo.prc_resolve_from_provider {label, lat, lon, external_ref, ...}.
type Result struct {
	PlaceID     int64  `json:"place_id"`
	OSMType     string `json:"osm_type"`
	OSMID       int64  `json:"osm_id"`
	DisplayName string `json:"display_name"`
	Lat         string `json:"lat"`
	Lon         string `json:"lon"`
	Class       string `json:"class"`
	Type        string `json:"type"`
}

// ExternalRef arma el ref estable para geo.place.external_ref (p.ej. "N123", "W456").
func (r Result) ExternalRef() string {
	if r.OSMType == "" {
		return ""
	}
	return strings.ToUpper(r.OSMType[:1]) + strconv.FormatInt(r.OSMID, 10)
}

// Search consulta /search. Va SOLO en el fallback de /geocode/search, nunca en autocomplete.
func (c *Client) Search(ctx context.Context, query, city string, limit int) ([]Result, error) {
	if limit <= 0 {
		limit = 8
	}
	q := url.Values{}
	q.Set("format", "jsonv2")
	q.Set("addressdetails", "1")
	q.Set("limit", strconv.Itoa(limit))
	if city != "" {
		q.Set("q", query+", "+city)
	} else {
		q.Set("q", query)
	}

	var out []Result
	if err := c.getJSON(ctx, "/search?"+q.Encode(), &out); err != nil {
		return nil, err
	}
	return out, nil
}

// Reverse resuelve una coordenada a un lugar (/reverse). Alimenta el fallback de
// /geocode/reverse.
func (c *Client) Reverse(ctx context.Context, lat, lon float64) (*Result, error) {
	q := url.Values{}
	q.Set("format", "jsonv2")
	q.Set("addressdetails", "1")
	q.Set("lat", strconv.FormatFloat(lat, 'f', -1, 64))
	q.Set("lon", strconv.FormatFloat(lon, 'f', -1, 64))

	var out Result
	if err := c.getJSON(ctx, "/reverse?"+q.Encode(), &out); err != nil {
		return nil, err
	}
	if out.Lat == "" && out.Lon == "" {
		return nil, nil
	}
	return &out, nil
}

func (c *Client) getJSON(ctx context.Context, path string, dst any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.base+path, nil)
	if err != nil {
		return err
	}
	// Nominatim exige identificar al cliente.
	req.Header.Set("User-Agent", "ms-vehitrack/1.0")
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("nominatim: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("nominatim: status %d", resp.StatusCode)
	}
	if err := json.NewDecoder(resp.Body).Decode(dst); err != nil {
		return fmt.Errorf("nominatim: decode: %w", err)
	}
	return nil
}
