// Package osrm es el cliente HTTP del motor de ruteo (127.0.0.1:21002). El ms lo consulta en
// POST /routes cuando routing.fnc_get_route no tiene la ruta en cache; el resultado se
// persiste con routing.prc_store_route (doc 03 §3).
package osrm

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

// Client habla con una instancia osrm-backend (perfil car compilado).
type Client struct {
	base string
	http *http.Client
}

// NewClient crea el cliente. baseURL p.ej. "http://127.0.0.1:21002".
func NewClient(baseURL string, hc *http.Client) *Client {
	if hc == nil {
		hc = &http.Client{Timeout: 5 * time.Second}
	}
	return &Client{base: strings.TrimRight(baseURL, "/"), http: hc}
}

// Waypoint es lon/lat (orden OSRM: {lon},{lat}).
type Waypoint struct {
	Lon float64
	Lat float64
}

// Route es la ruta lista para routing.prc_store_route: geometría GeoJSON, distancia, duración
// y maniobras crudas (steps) que el dispositivo persiste para navegar sin red.
type Route struct {
	DistanceM  float64         `json:"distance"`
	DurationS  float64         `json:"duration"`
	GeometryJS json.RawMessage `json:"geometry"` // GeoJSON LineString
	Legs       json.RawMessage `json:"legs"`     // contiene los steps cuando steps=true
}

type routeResponse struct {
	Code    string  `json:"code"`
	Message string  `json:"message"`
	Routes  []Route `json:"routes"`
}

// Route calcula UNA ruta por los waypoints (la primera de OSRM). profile default "driving".
func (c *Client) Route(ctx context.Context, wps []Waypoint, profile string) (*Route, error) {
	routes, err := c.routes(ctx, wps, profile, false)
	if err != nil {
		return nil, err
	}
	return &routes[0], nil
}

// RouteAll calcula la ruta y sus ALTERNATIVAS (alternatives=3). Devuelve todas las rutas que
// dio OSRM en orden (la [0] es la principal). OSRM solo alterna punto a punto (2 waypoints);
// con vias intermedias devuelve una sola, y aqui se devuelve esa sola sin error.
func (c *Client) RouteAll(ctx context.Context, wps []Waypoint, profile string) ([]Route, error) {
	return c.routes(ctx, wps, profile, true)
}

func (c *Client) routes(
	ctx context.Context, wps []Waypoint, profile string, alternatives bool,
) ([]Route, error) {
	if len(wps) < 2 {
		return nil, fmt.Errorf("osrm: se requieren al menos 2 waypoints")
	}
	if profile == "" {
		profile = "driving"
	}

	coords := make([]string, len(wps))
	for i, w := range wps {
		coords[i] = strconv.FormatFloat(w.Lon, 'f', -1, 64) + "," +
			strconv.FormatFloat(w.Lat, 'f', -1, 64)
	}

	q := url.Values{}
	q.Set("overview", "full")
	q.Set("geometries", "geojson")
	q.Set("steps", "true")
	// alternatives=3 pide hasta 3 rutas (OSRM puede devolver menos). "false" = solo la principal.
	if alternatives {
		q.Set("alternatives", "3")
	} else {
		q.Set("alternatives", "false")
	}

	path := "/route/v1/" + profile + "/" + strings.Join(coords, ";") + "?" + q.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.base+path, nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("osrm: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("osrm: status %d", resp.StatusCode)
	}

	var out routeResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("osrm: decode: %w", err)
	}
	if out.Code != "Ok" || len(out.Routes) == 0 {
		return nil, fmt.Errorf("osrm: sin ruta (code=%s)", out.Code)
	}
	return out.Routes, nil
}
