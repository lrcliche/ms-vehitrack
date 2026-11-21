package drivers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"mime"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
)

var (
	ErrDriverAppUnavailable = errors.New("driver app: service unavailable")
	ErrDriverAppInvalid     = errors.New("driver app: invalid request")
)

type Service struct {
	store   ports.DriverAppStore
	storage ports.DriverAppDocumentStorage
}

func NewService(store ports.DriverAppStore, storage ports.DriverAppDocumentStorage) *Service {
	return &Service{store: store, storage: storage}
}

func (s *Service) Profile(ctx context.Context, tenantID, userID, tenantUserID string) (json.RawMessage, error) {
	if s == nil || s.store == nil {
		return nil, ErrDriverAppUnavailable
	}
	return s.store.Profile(ctx, tenantID, userID, tenantUserID)
}

func (s *Service) Documents(ctx context.Context, tenantID, userID, tenantUserID, owner string) (json.RawMessage, error) {
	if s == nil || s.store == nil {
		return nil, ErrDriverAppUnavailable
	}
	if owner != "conductor" && owner != "vehiculo" {
		return nil, ErrDriverAppInvalid
	}
	return s.store.Documents(ctx, tenantID, userID, tenantUserID, owner)
}

func (s *Service) DaySummary(ctx context.Context, tenantID, userID, tenantUserID, date string) (json.RawMessage, error) {
	if s == nil || s.store == nil {
		return nil, ErrDriverAppUnavailable
	}
	if _, err := time.Parse("2006-01-02", date); err != nil {
		return nil, ErrDriverAppInvalid
	}
	return s.store.DaySummary(ctx, tenantID, userID, tenantUserID, date)
}

func (s *Service) Services(ctx context.Context, tenantID, userID, tenantUserID string) (json.RawMessage, error) {
	if s == nil || s.store == nil {
		return nil, ErrDriverAppUnavailable
	}
	return s.store.Services(ctx, tenantID, userID, tenantUserID)
}

func (s *Service) StartService(ctx context.Context, tenantID, userID, tenantUserID, serviceID string) (json.RawMessage, error) {
	if s == nil || s.store == nil {
		return nil, ErrDriverAppUnavailable
	}
	if uuid.Validate(serviceID) != nil {
		return nil, ErrDriverAppInvalid
	}
	return s.store.StartService(ctx, tenantID, userID, tenantUserID, serviceID)
}

func (s *Service) FinishService(ctx context.Context, tenantID, userID, tenantUserID, serviceID string) (json.RawMessage, error) {
	if s == nil || s.store == nil {
		return nil, ErrDriverAppUnavailable
	}
	if uuid.Validate(serviceID) != nil {
		return nil, ErrDriverAppInvalid
	}
	return s.store.FinishService(ctx, tenantID, userID, tenantUserID, serviceID)
}

func (s *Service) OpenDocument(ctx context.Context, tenantID, userID, tenantUserID, owner, documentID string) (*entities.DriverAppFile, error) {
	if s == nil || s.store == nil || s.storage == nil {
		return nil, ErrDriverAppUnavailable
	}
	if (owner != "conductor" && owner != "vehiculo") || uuid.Validate(documentID) != nil {
		return nil, ErrDriverAppInvalid
	}
	file, err := s.store.DocumentFile(ctx, tenantID, userID, tenantUserID, owner, documentID)
	if err != nil {
		return nil, err
	}
	reader, err := s.storage.Open(ctx, file.StorageKey)
	if err != nil {
		return nil, fmt.Errorf("open driver document: %w", err)
	}
	contentType := mime.TypeByExtension(filepath.Ext(file.FileName))
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	return &entities.DriverAppFile{Reader: reader, FileName: filepath.Base(strings.ReplaceAll(file.FileName, "\\", "/")), ContentType: contentType}, nil
}
