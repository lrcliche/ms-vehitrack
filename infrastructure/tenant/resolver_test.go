package tenant

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestResolver_CachesWithinTTL(t *testing.T) {
	calls := 0
	r := NewResolver(func(_ context.Context, _ string) (string, error) {
		calls++
		return "tenant-A", nil
	}, time.Minute)

	for i := 0; i < 3; i++ {
		got, err := r.TenantOf(context.Background(), "dev-1")
		if err != nil || got != "tenant-A" {
			t.Fatalf("TenantOf = (%q,%v), quiero (tenant-A,nil)", got, err)
		}
	}
	if calls != 1 {
		t.Fatalf("lookup se llamó %d veces, quiero 1 (cache)", calls)
	}
}

func TestResolver_RefetchesAfterExpiry(t *testing.T) {
	calls := 0
	r := NewResolver(func(_ context.Context, _ string) (string, error) {
		calls++
		return "tenant-A", nil
	}, time.Minute)

	base := time.Unix(0, 0)
	r.now = func() time.Time { return base }
	if _, err := r.TenantOf(context.Background(), "dev-1"); err != nil {
		t.Fatal(err)
	}
	// avanzar más allá del TTL
	r.now = func() time.Time { return base.Add(2 * time.Minute) }
	if _, err := r.TenantOf(context.Background(), "dev-1"); err != nil {
		t.Fatal(err)
	}
	if calls != 2 {
		t.Fatalf("lookup se llamó %d veces, quiero 2 (expiró)", calls)
	}
}

func TestResolver_DoesNotCacheErrors(t *testing.T) {
	calls := 0
	r := NewResolver(func(_ context.Context, _ string) (string, error) {
		calls++
		return "", ErrDeviceUnknown
	}, time.Minute)

	for i := 0; i < 2; i++ {
		if _, err := r.TenantOf(context.Background(), "dev-x"); !errors.Is(err, ErrDeviceUnknown) {
			t.Fatalf("quiero ErrDeviceUnknown, obtuve %v", err)
		}
	}
	if calls != 2 {
		t.Fatalf("los errores no deben cachearse: lookup %d veces, quiero 2", calls)
	}
}

func TestResolver_Invalidate(t *testing.T) {
	calls := 0
	r := NewResolver(func(_ context.Context, _ string) (string, error) {
		calls++
		return "tenant-A", nil
	}, time.Minute)

	_, _ = r.TenantOf(context.Background(), "dev-1")
	r.Invalidate("dev-1")
	_, _ = r.TenantOf(context.Background(), "dev-1")
	if calls != 2 {
		t.Fatalf("tras Invalidate debe reconsultar: lookup %d veces, quiero 2", calls)
	}
}
