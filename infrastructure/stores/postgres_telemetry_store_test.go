package stores_test

import (
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
	"ms-vehitrack/infrastructure/stores"
)

func TestStableDeviceUUID_ParsesUUID(t *testing.T) {
	id := uuid.MustParse("11111111-1111-1111-1111-111111111111")
	got := stores.StableDeviceUUID(id.String())
	require.Equal(t, id, got)
}

func TestStableDeviceUUID_HashesOpaque(t *testing.T) {
	a := stores.StableDeviceUUID("ssa-android-abc")
	b := stores.StableDeviceUUID("ssa-android-abc")
	c := stores.StableDeviceUUID("other")
	require.Equal(t, a, b)
	require.NotEqual(t, a, c)
}

func TestDefaultTenantID(t *testing.T) {
	require.Equal(t, "00000000-0000-0000-0000-000000000001", stores.DefaultTenantID.String())
}
