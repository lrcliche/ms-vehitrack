package entities

import "io"

// DriverAppDocumentFile is internal metadata returned by a tenant-scoped database routine.
// StorageKey is never serialized to the Driver App.
type DriverAppDocumentFile struct {
	StorageKey string `json:"storage_key"`
	FileName   string `json:"file_name"`
}

type DriverAppFile struct {
	Reader      io.ReadCloser
	FileName    string
	ContentType string
}
