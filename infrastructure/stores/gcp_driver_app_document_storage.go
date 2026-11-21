package stores

import (
	"context"
	"fmt"
	"io"

	gcpstorage "ms-vehitrack/infrastructure/gcp/storage"
)

type GCPDriverAppDocumentStorage struct{ client *gcpstorage.Client }

func NewGCPDriverAppDocumentStorage(client *gcpstorage.Client) *GCPDriverAppDocumentStorage {
	return &GCPDriverAppDocumentStorage{client: client}
}

func (s *GCPDriverAppDocumentStorage) Open(ctx context.Context, key string) (io.ReadCloser, error) {
	if s == nil || s.client == nil || s.client.DefaultBucket() == "" {
		return nil, fmt.Errorf("document storage is not configured")
	}
	return s.client.NewReader(ctx, s.client.DefaultBucket(), key)
}
