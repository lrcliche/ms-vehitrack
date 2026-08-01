// Package tenant resuelve el tenant dueño de un device y lo cachea con TTL corto. Es lo que
// alimenta al middleware de tenant del ms (doc 03 §2).
package tenant

import (
	"context"
	"database/sql"
	"errors"
	"sync"
	"time"

	"ms-vehitrack/infrastructure/database"
)

// ErrDeviceUnknown = el device no está registrado (o no es visible para la conexión de
// resolución). El middleware lo traduce a 404.
var ErrDeviceUnknown = errors.New("tenant: device desconocido")

// Lookup resuelve deviceID -> tenantID contra el origen de verdad. Se inyecta para que la
// DECISIÓN de PRIVILEGIO viva en el wiring, no aquí:
//
//	device.device tiene RLS `USING (tenant_id = fnc_current_tenant())`. Una conexión como
//	vehitrack_app SIN app.tenant_id no ve ninguna fila, así que NO puede resolver el tenant
//	de un device con la SELECT normal (huevo-y-gallina). Opciones de wiring, a decidir:
//	  a) tenant_id viaja en el JWT del device (camino común, sin round-trip a BD); o
//	  b) esta Lookup corre sobre una conexión que ve todos los tenants (dueño / rol BYPASSRLS),
//	     acotada a esta única consulta de sistema.
//	ADR-006 reserva SECURITY DEFINER solo para prc_provision_personal_tenant, así que no se
//	convierte fnc_tenant_of_device en DEFINER.
type Lookup func(ctx context.Context, deviceID string) (tenantID string, err error)

// PoolLookup implementa Lookup vía device.fnc_tenant_of_device. IMPORTANTE: el pool que se le
// pase debe poder ver todos los tenants (dueño o rol con BYPASSRLS); con el pool tenant-scoped
// de la app devolvería siempre ErrDeviceUnknown por RLS. Ver la nota de Lookup.
func PoolLookup(pool *database.Pool) Lookup {
	return func(ctx context.Context, deviceID string) (string, error) {
		var t sql.NullString
		err := pool.QueryRow(ctx,
			"SELECT device.fnc_tenant_of_device($1)::text", deviceID).Scan(&t)
		if err != nil {
			return "", err
		}
		if !t.Valid {
			return "", ErrDeviceUnknown
		}
		return t.String, nil
	}
}

type entry struct {
	tenantID string
	expires  time.Time
}

// Resolver cachea deviceID -> tenantID con TTL. Seguro para uso concurrente.
type Resolver struct {
	lookup Lookup
	ttl    time.Duration
	now    func() time.Time // inyectable para tests

	mu    sync.RWMutex
	cache map[string]entry
}

// NewResolver crea un resolver. ttl<=0 desactiva el cache (siempre consulta).
func NewResolver(lookup Lookup, ttl time.Duration) *Resolver {
	return &Resolver{
		lookup: lookup,
		ttl:    ttl,
		now:    time.Now,
		cache:  make(map[string]entry),
	}
}

// TenantOf devuelve el tenant del device, del cache si está fresco. No cachea errores.
func (r *Resolver) TenantOf(ctx context.Context, deviceID string) (string, error) {
	if r.ttl > 0 {
		r.mu.RLock()
		e, ok := r.cache[deviceID]
		r.mu.RUnlock()
		if ok && r.now().Before(e.expires) {
			return e.tenantID, nil
		}
	}

	tenantID, err := r.lookup(ctx, deviceID)
	if err != nil {
		return "", err
	}

	if r.ttl > 0 {
		r.mu.Lock()
		r.cache[deviceID] = entry{tenantID: tenantID, expires: r.now().Add(r.ttl)}
		r.mu.Unlock()
	}
	return tenantID, nil
}

// Invalidate saca un device del cache (p.ej. si se bloqueó o cambió de tenant).
func (r *Resolver) Invalidate(deviceID string) {
	r.mu.Lock()
	delete(r.cache, deviceID)
	r.mu.Unlock()
}
