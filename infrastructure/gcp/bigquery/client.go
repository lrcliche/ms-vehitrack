package bigquery

import (
	"context"
	"fmt"
	"time"

	"cloud.google.com/go/bigquery"
	gcpconfig "ms-vehitrack/infrastructure/gcp/config"
	"google.golang.org/api/googleapi"
	"google.golang.org/api/option"
)

// Client is a reusable BigQuery adapter without domain knowledge.
type Client struct {
	client    *bigquery.Client
	projectID string
	dataset   string
	timeout   time.Duration
}

// NewClient creates a BigQuery client using GCP configuration.
func NewClient(ctx context.Context, cfg gcpconfig.Config) (*Client, error) {
	opts := make([]option.ClientOption, 0, 1)
	if cfg.HasCredentialsFile() {
		opts = append(opts, option.WithCredentialsFile(cfg.CredentialsFile))
	}

	client, err := bigquery.NewClient(ctx, cfg.ProjectID, opts...)
	if err != nil {
		return nil, fmt.Errorf("create bigquery client: %w", err)
	}

	return &Client{
		client:    client,
		projectID: cfg.ProjectID,
		dataset:   cfg.BigQueryDataset,
		timeout:   cfg.ClientTimeout,
	}, nil
}

// ProjectID returns the configured GCP project identifier.
func (c *Client) ProjectID() string {
	return c.projectID
}

// Dataset returns the configured BigQuery dataset identifier.
func (c *Client) Dataset() string {
	return c.dataset
}

// EnsureDatasetAndTable creates dataset/table when missing.
func (c *Client) EnsureDatasetAndTable(ctx context.Context, table string, schema bigquery.Schema) error {
	if table == "" {
		return fmt.Errorf("bigquery table is required")
	}

	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	dataset := c.client.Dataset(c.dataset)
	if err := dataset.Create(ctx, &bigquery.DatasetMetadata{Location: "US"}); err != nil && !isAlreadyExists(err) {
		return fmt.Errorf("create bigquery dataset %s: %w", c.dataset, err)
	}

	meta := &bigquery.TableMetadata{Schema: schema}
	if err := dataset.Table(table).Create(ctx, meta); err != nil && !isAlreadyExists(err) {
		return fmt.Errorf("create bigquery table %s.%s: %w", c.dataset, table, err)
	}

	return nil
}

// InsertRows inserts rows into the given table within the configured dataset.
func (c *Client) InsertRows(ctx context.Context, table string, rows interface{}) error {
	if table == "" {
		return fmt.Errorf("bigquery table is required")
	}
	if rows == nil {
		return fmt.Errorf("bigquery rows are required")
	}

	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	inserter := c.client.Dataset(c.dataset).Table(table).Inserter()
	if err := inserter.Put(ctx, rows); err != nil {
		return fmt.Errorf("insert bigquery rows into %s.%s: %w", c.dataset, table, err)
	}

	return nil
}

// Close releases BigQuery client resources.
func (c *Client) Close() error {
	if c == nil || c.client == nil {
		return nil
	}
	if err := c.client.Close(); err != nil {
		return fmt.Errorf("close bigquery client: %w", err)
	}
	return nil
}

func isAlreadyExists(err error) bool {
	apiErr, ok := err.(*googleapi.Error)
	return ok && apiErr.Code == 409
}
