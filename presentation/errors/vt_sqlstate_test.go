package errors

import (
	"errors"
	"fmt"
	"net/http"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
)

func TestMapPgError_MappedCodes(t *testing.T) {
	cases := []struct {
		code       string
		wantStatus int
		wantCode   string
	}{
		{"VT002", http.StatusForbidden, "DEVICE_BLOCKED"},
		{"VT022", http.StatusPaymentRequired, "DEVICE_QUOTA_EXCEEDED"},
		{"VT044", http.StatusConflict, "CONFLICT"},
		{"VT072", http.StatusConflict, "CONFLICT"},
		{"VT010", http.StatusServiceUnavailable, "NOT_READY"},
		{"VT070", http.StatusServiceUnavailable, "NOT_READY"},
		{"VT071", http.StatusNotFound, "REGION_NOT_FOUND"},
		{"VT021", http.StatusNotFound, "TENANT_NOT_FOUND"},
		{"VT041", http.StatusNotFound, "NOT_FOUND"},
		{"VT062", http.StatusUnprocessableEntity, "UNPROCESSABLE"},
		{"VT060", http.StatusBadRequest, "INVALID_REQUEST"},
	}
	for _, c := range cases {
		t.Run(c.code, func(t *testing.T) {
			// envuelto, para probar que errors.As lo destapa
			err := fmt.Errorf("call failed: %w", &pgconn.PgError{Code: c.code, Message: "boom"})
			got, ok := MapPgError(err)
			if !ok {
				t.Fatalf("MapPgError(%s) ok=false, quiero true", c.code)
			}
			if got.Status != c.wantStatus || got.Code != c.wantCode {
				t.Fatalf("MapPgError(%s) = (%d,%s), quiero (%d,%s)",
					c.code, got.Status, got.Code, c.wantStatus, c.wantCode)
			}
		})
	}
}

func TestMapPgError_UnmappedVTFallsTo500(t *testing.T) {
	err := &pgconn.PgError{Code: "VT999", Message: "desconocido"}
	got, ok := MapPgError(err)
	if !ok {
		t.Fatalf("VT999 ok=false, quiero true (VT* sin mapear cae a 500 con code preservado)")
	}
	if got.Status != http.StatusInternalServerError || got.Code != "VT_UNMAPPED_VT999" {
		t.Fatalf("VT999 = (%d,%s), quiero (500,VT_UNMAPPED_VT999)", got.Status, got.Code)
	}
}

func TestMapPgError_NonPgErrorIgnored(t *testing.T) {
	if _, ok := MapPgError(errors.New("cualquier cosa")); ok {
		t.Fatal("un error no-pg debe devolver ok=false para seguir la cascada")
	}
	// un SQLSTATE no-VT (p.ej. 23505 unique_violation) tampoco lo toma este mapeador
	if _, ok := MapPgError(&pgconn.PgError{Code: "23505"}); ok {
		t.Fatal("un SQLSTATE no-VT debe devolver ok=false")
	}
}
