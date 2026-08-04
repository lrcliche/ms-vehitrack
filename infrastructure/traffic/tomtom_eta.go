// Package traffic contiene fuentes externas de trafico. TomTomETA implementa
// application/routing.TrafficETA con TomTom Traffic Flow (Flow Segment Data) como ARRANQUE del
// ETA de rutas mientras el trafico colaborativo (traffic.live_state) aun no cubre.
package traffic

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// TomTomETA muestrea hasta maxSamples puntos equiespaciados de la geometria de la ruta y en
// cada uno compara la velocidad actual con la de flujo libre (flowSegmentData). El promedio de
// (flujo_libre / actual) —topado a x3— escala la duracion de flujo libre. Sin key o sin dato
// devuelve (_, false): no altera el ETA. Nunca lanza; cualquier fallo por punto se ignora.
type TomTomETA struct {
	apiKey     string
	baseURL    string
	client     *http.Client
	maxSamples int
	zoom       int
}

// NewTomTomETA crea la fuente. baseURL vacia => api.tomtom.com; permite un proxy propio que
// replique el contrato flowSegmentData (p. ej. para no exponer la key). client nil => 6s.
func NewTomTomETA(apiKey, baseURL string, client *http.Client) *TomTomETA {
	if baseURL == "" {
		baseURL = "https://api.tomtom.com"
	}
	if client == nil {
		client = &http.Client{Timeout: 6 * time.Second}
	}
	return &TomTomETA{
		apiKey:     apiKey,
		baseURL:    strings.TrimRight(baseURL, "/"),
		client:     client,
		maxSamples: 10,
		zoom:       12,
	}
}

type latLon struct{ lat, lon float64 }

// AdjustedDuration implementa routing.TrafficETA.
func (t *TomTomETA) AdjustedDuration(
	ctx context.Context, geometryGeoJSON json.RawMessage, freeFlowS float64,
) (float64, bool) {
	if t.apiKey == "" || freeFlowS <= 0 {
		return 0, false
	}
	pts := parseLineString(geometryGeoJSON)
	if len(pts) < 2 {
		return 0, false
	}

	n := len(pts)
	count := t.maxSamples
	if n < count {
		count = n
	}
	var sum float64
	var got int
	for i := 0; i < count; i++ {
		idx := 0
		if count > 1 {
			idx = i * (n - 1) / (count - 1)
		}
		if f, ok := t.factorAt(ctx, pts[idx]); ok {
			sum += f
			got++
		}
	}
	if got == 0 {
		return 0, false
	}
	factor := sum / float64(got)
	if factor < 1 {
		factor = 1
	}
	return freeFlowS * factor, true
}

// factorAt = flujo_libre / actual en un punto (1..3). Cierre de via => 3. Sin dato => false.
func (t *TomTomETA) factorAt(ctx context.Context, p latLon) (float64, bool) {
	endpoint := fmt.Sprintf(
		"%s/traffic/services/4/flowSegmentData/absolute/%d/json", t.baseURL, t.zoom)
	q := url.Values{}
	q.Set("key", t.apiKey)
	q.Set("point", fmt.Sprintf("%f,%f", p.lat, p.lon))
	q.Set("unit", "KMPH")

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint+"?"+q.Encode(), nil)
	if err != nil {
		return 0, false
	}
	resp, err := t.client.Do(req)
	if err != nil {
		return 0, false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 0, false
	}

	var body struct {
		Flow struct {
			CurrentSpeed  float64 `json:"currentSpeed"`
			FreeFlowSpeed float64 `json:"freeFlowSpeed"`
			RoadClosure   bool    `json:"roadClosure"`
		} `json:"flowSegmentData"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return 0, false
	}
	if body.Flow.RoadClosure {
		return 3, true
	}
	if body.Flow.CurrentSpeed <= 0 || body.Flow.FreeFlowSpeed <= 0 {
		return 0, false
	}
	factor := body.Flow.FreeFlowSpeed / body.Flow.CurrentSpeed
	if factor < 1 {
		factor = 1
	}
	if factor > 3 {
		factor = 3
	}
	return factor, true
}

// parseLineString acepta un GeoJSON LineString ({type,coordinates:[[lon,lat],...]}) o el arreglo
// de coordenadas suelto. GeoJSON es [lon,lat]; se devuelve como {lat,lon}.
func parseLineString(raw json.RawMessage) []latLon {
	var obj struct {
		Coordinates [][]float64 `json:"coordinates"`
	}
	if err := json.Unmarshal(raw, &obj); err == nil && len(obj.Coordinates) > 0 {
		return toLatLon(obj.Coordinates)
	}
	var arr [][]float64
	if err := json.Unmarshal(raw, &arr); err == nil && len(arr) > 0 {
		return toLatLon(arr)
	}
	return nil
}

func toLatLon(coords [][]float64) []latLon {
	out := make([]latLon, 0, len(coords))
	for _, c := range coords {
		if len(c) >= 2 {
			out = append(out, latLon{lat: c[1], lon: c[0]})
		}
	}
	return out
}
