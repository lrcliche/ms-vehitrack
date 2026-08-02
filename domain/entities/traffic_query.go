package entities

import (
	"errors"
	"strconv"
	"strings"
)

// BBox es la caja de consulta de los lecturas de trafico por bbox: min/max lon/lat en 4326.
type BBox struct {
	MinLon float64
	MinLat float64
	MaxLon float64
	MaxLat float64
}

var (
	// ErrBBoxRequired = falta el parametro bbox.
	ErrBBoxRequired = errors.New("traffic: bbox requerido")
	// ErrBBoxInvalid = bbox mal formado (se espera minLon,minLat,maxLon,maxLat).
	ErrBBoxInvalid = errors.New("traffic: bbox invalido (minLon,minLat,maxLon,maxLat)")
)

// ParseBBox lee "minLon,minLat,maxLon,maxLat". Exige min < max en ambos ejes.
func ParseBBox(raw string) (BBox, error) {
	if raw == "" {
		return BBox{}, ErrBBoxRequired
	}
	parts := strings.Split(raw, ",")
	if len(parts) != 4 {
		return BBox{}, ErrBBoxInvalid
	}
	vals := make([]float64, 4)
	for i, p := range parts {
		v, err := strconv.ParseFloat(strings.TrimSpace(p), 64)
		if err != nil {
			return BBox{}, ErrBBoxInvalid
		}
		vals[i] = v
	}
	b := BBox{MinLon: vals[0], MinLat: vals[1], MaxLon: vals[2], MaxLat: vals[3]}
	if b.MinLon >= b.MaxLon || b.MinLat >= b.MaxLat {
		return BBox{}, ErrBBoxInvalid
	}
	return b, nil
}
