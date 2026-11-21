package errors

import (
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5/pgconn"
)

// vtStatus mapea cada SQLSTATE VT* (que levantan las rutinas prc_/fnc_ del modelo PG) a su
// (status HTTP, error.code) segun la tabla del doc 03 §4. Un VT* que NO este aqui cae a 500
// + log: preferimos enterarnos a devolver un 400 generico que oculta un bug.
var vtStatus = map[string]struct {
	Status int
	Code   string
}{
	// 404 NOT_FOUND
	"VT001": {http.StatusNotFound, "NOT_FOUND"}, // device/telemetria inexistente
	"VT026": {http.StatusNotFound, "NOT_FOUND"},
	"VT033": {http.StatusNotFound, "NOT_FOUND"}, // place inexistente
	"VT041": {http.StatusNotFound, "NOT_FOUND"}, // device no visible en el tenant
	"VT049": {http.StatusNotFound, "NOT_FOUND"}, // registro inexistente o ya eliminado
	"VT052": {http.StatusNotFound, "NOT_FOUND"},
	"VT075": {http.StatusConflict, "CONFLICT"},
	"VT076": {http.StatusConflict, "CONFLICT"},

	// 403 DEVICE_BLOCKED
	"VT002": {http.StatusForbidden, "DEVICE_BLOCKED"},

	// 409 CONFLICT
	"VT003": {http.StatusConflict, "CONFLICT"}, // lote de otro device
	"VT023": {http.StatusConflict, "CONFLICT"},
	"VT025": {http.StatusConflict, "CONFLICT"},
	"VT044": {http.StatusConflict, "CONFLICT"}, // ya existe casa/trabajo
	"VT072": {http.StatusConflict, "CONFLICT"}, // version de paquete ya publicada (inmutable)

	// 404 TENANT_NOT_FOUND / REGION_NOT_FOUND
	"VT021": {http.StatusNotFound, "TENANT_NOT_FOUND"},
	"VT071": {http.StatusNotFound, "REGION_NOT_FOUND"},

	// 402 DEVICE_QUOTA_EXCEEDED
	"VT022": {http.StatusPaymentRequired, "DEVICE_QUOTA_EXCEEDED"},

	// 403 FORBIDDEN
	"VT080": {http.StatusForbidden, "FORBIDDEN"},

	// 503 NOT_READY (despliegue incompleto: falta clave en app_setting / diccionario / paquete)
	"VT010": {http.StatusServiceUnavailable, "NOT_READY"},
	"VT030": {http.StatusServiceUnavailable, "NOT_READY"},
	"VT070": {http.StatusServiceUnavailable, "NOT_READY"}, // región sin paquete publicado

	// 400 INVALID_REQUEST
	"VT024": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT031": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT032": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT034": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT035": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT040": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT042": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT043": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT045": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT046": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT047": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT048": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT050": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT060": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT061": {http.StatusBadRequest, "INVALID_REQUEST"},
	"VT074": {http.StatusBadRequest, "INVALID_REQUEST"},

	// 422 UNPROCESSABLE
	"VT027": {http.StatusUnprocessableEntity, "UNPROCESSABLE"},
	"VT051": {http.StatusUnprocessableEntity, "UNPROCESSABLE"}, // lote demasiado grande
	"VT062": {http.StatusUnprocessableEntity, "UNPROCESSABLE"}, // demasiados waypoints
	"VT073": {http.StatusUnprocessableEntity, "UNPROCESSABLE"}, // faltan artefactos obligatorios
}

// MapPgError traduce un *pgconn.PgError con SQLSTATE VT* a AppError. El segundo retorno es
// false cuando el error no es un VT* mapeado, para que el llamador siga la cascada normal.
func MapPgError(err error) (AppError, bool) {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) {
		return AppError{}, false
	}
	if m, ok := vtStatus[pgErr.Code]; ok {
		return New(m.Status, m.Code, pgErr.Message), true
	}
	// VT* sin mapear -> 500 + se conserva el SQLSTATE en el code para el log.
	if len(pgErr.Code) == 5 && pgErr.Code[:2] == "VT" {
		return New(http.StatusInternalServerError, "VT_UNMAPPED_"+pgErr.Code, pgErr.Message), true
	}
	return AppError{}, false
}
