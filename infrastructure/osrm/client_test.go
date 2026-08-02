package osrm

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRoute_OK(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/route/v1/driving/") {
			t.Fatalf("path = %s", r.URL.Path)
		}
		// dos waypoints, lon,lat;lon,lat (FormatFloat -1 => forma mínima: -74.8, 11)
		if !strings.Contains(r.URL.Path, "-74.79,10.99;-74.8,11") {
			t.Fatalf("coords mal formadas: %s", r.URL.Path)
		}
		if r.URL.Query().Get("geometries") != "geojson" || r.URL.Query().Get("steps") != "true" {
			t.Fatalf("query = %s", r.URL.RawQuery)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"code":"Ok",
			"routes":[{"distance":1234.5,"duration":300.0,"geometry":{"type":"LineString","coordinates":[[-74.79,10.99],[-74.80,11.00]]},"legs":[]}]
		}`))
	}))
	defer srv.Close()

	c := NewClient(srv.URL, srv.Client())
	route, err := c.Route(context.Background(), []Waypoint{
		{Lon: -74.79, Lat: 10.99},
		{Lon: -74.80, Lat: 11.00},
	}, "")
	if err != nil {
		t.Fatal(err)
	}
	if route.DistanceM != 1234.5 || route.DurationS != 300.0 {
		t.Fatalf("distance/duration = %v/%v", route.DistanceM, route.DurationS)
	}
	if len(route.GeometryJS) == 0 {
		t.Fatal("geometry vacía")
	}
}

func TestRoute_NeedsTwoWaypoints(t *testing.T) {
	c := NewClient("http://127.0.0.1:21002", nil)
	if _, err := c.Route(context.Background(), []Waypoint{{Lon: 1, Lat: 1}}, ""); err == nil {
		t.Fatal("quiero error con un solo waypoint")
	}
}

func TestRoute_NoRouteIsError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"code":"NoRoute","routes":[]}`))
	}))
	defer srv.Close()

	c := NewClient(srv.URL, srv.Client())
	_, err := c.Route(context.Background(), []Waypoint{
		{Lon: -74.79, Lat: 10.99}, {Lon: -74.80, Lat: 11.00},
	}, "")
	if err == nil {
		t.Fatal("quiero error con code=NoRoute")
	}
}
