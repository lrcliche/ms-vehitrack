package storage

import (
	"context"
	"fmt"
	"io"
	"time"

	"cloud.google.com/go/storage"
	gcpconfig "ms-vehitrack/infrastructure/gcp/config"
	"google.golang.org/api/option"
)

// Client is a reusable Cloud Storage adapter without domain knowledge.
type Client struct {
	client        *storage.Client
	defaultBucket string
	timeout       time.Duration
}

// NewClient creates a Cloud Storage client using GCP configuration.
func NewClient(ctx context.Context, cfg gcpconfig.Config) (*Client, error) {
	client, err := storage.NewClient(
		ctx,
		option.WithCredentialsFile(cfg.CredentialsFile),
	)
	if err != nil {
		return nil, fmt.Errorf("create storage client: %w", err)
	}

	return &Client{
		client:        client,
		defaultBucket: cfg.StorageBucket,
		timeout:       cfg.ClientTimeout,
	}, nil
}

// DefaultBucket returns the configured default bucket name.
func (c *Client) DefaultBucket() string {
	return c.defaultBucket
}

// CreateBucket creates a bucket in the given project.
func (c *Client) CreateBucket(ctx context.Context, projectID, bucketName string) error {
	if projectID == "" {
		return fmt.Errorf("storage project id is required")
	}
	if bucketName == "" {
		return fmt.Errorf("storage bucket name is required")
	}

	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	if err := c.client.Bucket(bucketName).Create(ctx, projectID, nil); err != nil {
		return fmt.Errorf("create storage bucket %s: %w", bucketName, err)
	}

	return nil
}

// Upload writes object content to the given bucket and object path.
func (c *Client) Upload(ctx context.Context, bucket, object string, content []byte, contentType string) error {
	writer := c.NewWriter(ctx, bucket, object)
	if contentType != "" {
		writer.ContentType = contentType
	}

	if _, err := writer.Write(content); err != nil {
		_ = writer.Close()
		return fmt.Errorf("write storage object %s/%s: %w", bucket, object, err)
	}

	if err := writer.Close(); err != nil {
		return fmt.Errorf("close storage writer %s/%s: %w", bucket, object, err)
	}

	return nil
}

// Download reads the full object content from the given bucket and object path.
func (c *Client) Download(ctx context.Context, bucket, object string) ([]byte, error) {
	reader, err := c.NewReader(ctx, bucket, object)
	if err != nil {
		return nil, err
	}
	defer reader.Close()

	data, err := io.ReadAll(reader)
	if err != nil {
		return nil, fmt.Errorf("read storage object %s/%s: %w", bucket, object, err)
	}

	return data, nil
}

// Delete removes an object from the given bucket.
func (c *Client) Delete(ctx context.Context, bucket, object string) error {
	if bucket == "" {
		return fmt.Errorf("storage bucket is required")
	}
	if object == "" {
		return fmt.Errorf("storage object is required")
	}

	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	if err := c.client.Bucket(bucket).Object(object).Delete(ctx); err != nil {
		return fmt.Errorf("delete storage object %s/%s: %w", bucket, object, err)
	}

	return nil
}

// NewReader opens a reader for the given object.
func (c *Client) NewReader(ctx context.Context, bucket, object string) (*storage.Reader, error) {
	if bucket == "" {
		return nil, fmt.Errorf("storage bucket is required")
	}
	if object == "" {
		return nil, fmt.Errorf("storage object is required")
	}

	reader, err := c.client.Bucket(bucket).Object(object).NewReader(ctx)
	if err != nil {
		return nil, fmt.Errorf("open storage reader %s/%s: %w", bucket, object, err)
	}

	return reader, nil
}

// NewWriter opens a writer for the given object.
func (c *Client) NewWriter(ctx context.Context, bucket, object string) *storage.Writer {
	return c.client.Bucket(bucket).Object(object).NewWriter(ctx)
}

// Close releases Cloud Storage client resources.
func (c *Client) Close() error {
	if c == nil || c.client == nil {
		return nil
	}
	if err := c.client.Close(); err != nil {
		return fmt.Errorf("close storage client: %w", err)
	}
	return nil
}
