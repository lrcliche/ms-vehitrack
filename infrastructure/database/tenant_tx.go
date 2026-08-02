package database

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// WithTenantTx abre una transacción, fija el tenant de la petición y ejecuta fn dentro de
// ella. Es el ÚNICO punto por el que pasa el estampado de tenant: ningún repositorio recibe
// tenant_id como parámetro (doc 03 §2). Los repos reciben la pgx.Tx ya con app.tenant_id
// puesto y solo llaman a prc_/fnc_.
//
// Usa set_config('app.tenant_id', $1, true) — equivalente parametrizable de `SET LOCAL`:
//   - is_local = true  => vive solo hasta el fin de la transacción, nunca se queda pegado en
//     la conexión del pool (ese es EL bug clásico de multi-tenant con pool: un SET normal
//     hereda el tenant del request anterior y devuelve datos de otro cliente, sin error).
//   - parametrizado => evita inyección; `SET LOCAL app.tenant_id = <texto>` no admite bind.
//
// Si fn devuelve error, hace rollback y propaga; si todo va bien, commit.
func (p *Pool) WithTenantTx(ctx context.Context, tenantID string, fn func(pgx.Tx) error) (err error) {
	tx, err := p.inner.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tenant tx: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback(ctx)
		}
	}()

	if _, err = tx.Exec(ctx, "SELECT set_config('app.tenant_id', $1, true)", tenantID); err != nil {
		return fmt.Errorf("set app.tenant_id: %w", err)
	}

	if err = fn(tx); err != nil {
		return err
	}

	if err = tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit tenant tx: %w", err)
	}
	return nil
}
