package ports

import (
	"context"
	"io"
)

type DriverAppDocumentStorage interface {
	Open(ctx context.Context, storageKey string) (io.ReadCloser, error)
}
