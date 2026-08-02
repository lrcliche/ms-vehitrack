package nominatim

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestSearch_ParsesResults(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/search" {
			t.Fatalf("path = %s, quiero /search", r.URL.Path)
		}
		if r.URL.Query().Get("q") != "carrera 15, Barranquilla" {
			t.Fatalf("q = %q", r.URL.Query().Get("q"))
		}
		if r.Header.Get("User-Agent") == "" {
			t.Fatal("falta User-Agent")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[
			{"place_id":1,"osm_type":"way","osm_id":456,"display_name":"Carrera 15","lat":"10.99","lon":"-74.79","class":"highway","type":"residential"}
		]`))
	}))
	defer srv.Close()

	c := NewClient(srv.URL, srv.Client())
	res, err := c.Search(context.Background(), "carrera 15", "Barranquilla", 8)
	if err != nil {
		t.Fatal(err)
	}
	if len(res) != 1 {
		t.Fatalf("len = %d, quiero 1", len(res))
	}
	if got := res[0].ExternalRef(); got != "W456" {
		t.Fatalf("ExternalRef = %q, quiero W456", got)
	}
	if res[0].Lat != "10.99" {
		t.Fatalf("Lat = %q", res[0].Lat)
	}
}

func TestReverse_EmptyIsNil(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{}`))
	}))
	defer srv.Close()

	c := NewClient(srv.URL, srv.Client())
	res, err := c.Reverse(context.Background(), 10.99, -74.79)
	if err != nil {
		t.Fatal(err)
	}
	if res != nil {
		t.Fatalf("quiero nil para respuesta vacía, obtuve %+v", res)
	}
}

func TestSearch_Non200IsError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer srv.Close()

	c := NewClient(srv.URL, srv.Client())
	if _, err := c.Search(context.Background(), "x", "", 8); err == nil {
		t.Fatal("quiero error con status 502")
	}
}
