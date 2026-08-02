package middleware

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"ms-vehitrack/infrastructure/tenant"
)

func newResolver(lookup tenant.Lookup) *tenant.Resolver {
	return tenant.NewResolver(lookup, time.Minute)
}

func runWithTenant(t *testing.T, resolver *tenant.Resolver, deviceHeader string) (*httptest.ResponseRecorder, string, string) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	r := gin.New()
	var gotDevice, gotTenant string
	r.Use(TenantContext(resolver))
	r.GET("/probe", func(c *gin.Context) {
		gotDevice = DeviceIDFromContext(c)
		gotTenant = TenantIDFromContext(c)
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/probe", nil)
	if deviceHeader != "" {
		req.Header.Set(DeviceIDHeader, deviceHeader)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w, gotDevice, gotTenant
}

func TestTenantContext_OK(t *testing.T) {
	resolver := newResolver(func(_ context.Context, deviceID string) (string, error) {
		if deviceID != "dev-1" {
			t.Fatalf("deviceID inesperado: %s", deviceID)
		}
		return "tenant-A", nil
	})
	w, gotDevice, gotTenant := runWithTenant(t, resolver, "dev-1")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, quiero 200", w.Code)
	}
	if gotDevice != "dev-1" || gotTenant != "tenant-A" {
		t.Fatalf("context = (%q,%q), quiero (dev-1,tenant-A)", gotDevice, gotTenant)
	}
}

func TestTenantContext_MissingHeader400(t *testing.T) {
	resolver := newResolver(func(_ context.Context, _ string) (string, error) {
		t.Fatal("lookup no debe llamarse sin header")
		return "", nil
	})
	w, _, _ := runWithTenant(t, resolver, "")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, quiero 400", w.Code)
	}
}

func TestTenantContext_UnknownDevice404(t *testing.T) {
	resolver := newResolver(func(_ context.Context, _ string) (string, error) {
		return "", tenant.ErrDeviceUnknown
	})
	w, _, _ := runWithTenant(t, resolver, "dev-desconocido")
	if w.Code != http.StatusNotFound {
		t.Fatalf("status = %d, quiero 404", w.Code)
	}
}
