package nominatim

import (
	"context"
	"strconv"

	"ms-vehitrack/domain/entities"
)

// Provider adapta *Client a application/geocoding.Provider: mapea los Result crudos de
// Nominatim al ProviderPlace que espera geo.prc_resolve_from_provider. Vive aquí (no en
// application) para que la capa de aplicación no conozca el shape de Nominatim.
type Provider struct {
	client *Client
}

func NewProvider(client *Client) *Provider {
	return &Provider{client: client}
}

func (p *Provider) Search(ctx context.Context, query, city string, limit int) ([]entities.ProviderPlace, error) {
	res, err := p.client.Search(ctx, query, city, limit)
	if err != nil {
		return nil, err
	}
	out := make([]entities.ProviderPlace, 0, len(res))
	for _, r := range res {
		if pp, ok := toProviderPlace(r); ok {
			out = append(out, pp)
		}
	}
	return out, nil
}

func (p *Provider) Reverse(ctx context.Context, lat, lon float64) (*entities.ProviderPlace, error) {
	r, err := p.client.Reverse(ctx, lat, lon)
	if err != nil || r == nil {
		return nil, err
	}
	if pp, ok := toProviderPlace(*r); ok {
		return &pp, nil
	}
	return nil, nil
}

func toProviderPlace(r Result) (entities.ProviderPlace, bool) {
	lat, err1 := strconv.ParseFloat(r.Lat, 64)
	lon, err2 := strconv.ParseFloat(r.Lon, 64)
	if err1 != nil || err2 != nil {
		return entities.ProviderPlace{}, false
	}
	return entities.ProviderPlace{
		Label:       r.DisplayName,
		Lat:         lat,
		Lon:         lon,
		Kind:        "address",
		ExternalRef: r.ExternalRef(),
	}, true
}
