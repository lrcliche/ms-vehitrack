package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

// Config holds Google Cloud settings loaded from environment variables.
type Config struct {
	ProjectID                    string
	CredentialsFile              string
	BigQueryDataset              string
	PubSubTopic                  string
	StorageBucket                string
	ClientTimeout                time.Duration
	PubSubPublishRetries         int
	PubSubPublishRetryBackoff    time.Duration
}

// Load reads and validates GCP configuration from the process environment.
func Load() (Config, error) {
	timeoutSeconds, err := getRequiredPositiveInt("GCP_CLIENT_TIMEOUT_SECONDS")
	if err != nil {
		return Config{}, err
	}

	retries, err := getRequiredPositiveInt("GCP_PUBSUB_PUBLISH_RETRIES")
	if err != nil {
		return Config{}, err
	}

	backoffMillis, err := getRequiredPositiveInt("GCP_PUBSUB_RETRY_BACKOFF_MS")
	if err != nil {
		return Config{}, err
	}

	cfg := Config{
		ProjectID:                 os.Getenv("GCP_PROJECT_ID"),
		CredentialsFile:           os.Getenv("GOOGLE_APPLICATION_CREDENTIALS"),
		BigQueryDataset:           os.Getenv("GCP_BIGQUERY_DATASET"),
		PubSubTopic:               os.Getenv("GCP_PUBSUB_TOPIC"),
		StorageBucket:             os.Getenv("GCP_STORAGE_BUCKET"),
		ClientTimeout:             time.Duration(timeoutSeconds) * time.Second,
		PubSubPublishRetries:      retries,
		PubSubPublishRetryBackoff: time.Duration(backoffMillis) * time.Millisecond,
	}

	if err := cfg.validate(); err != nil {
		return Config{}, err
	}

	credentialsPath, err := filepath.Abs(cfg.CredentialsFile)
	if err != nil {
		return Config{}, fmt.Errorf("resolve GOOGLE_APPLICATION_CREDENTIALS: %w", err)
	}
	if _, err := os.Stat(credentialsPath); err != nil {
		return Config{}, fmt.Errorf("GOOGLE_APPLICATION_CREDENTIALS file not found: %w", err)
	}

	cfg.CredentialsFile = credentialsPath
	if err := os.Setenv("GOOGLE_APPLICATION_CREDENTIALS", credentialsPath); err != nil {
		return Config{}, fmt.Errorf("set GOOGLE_APPLICATION_CREDENTIALS: %w", err)
	}

	return cfg, nil
}

func (c Config) validate() error {
	required := map[string]string{
		"GCP_PROJECT_ID":                 c.ProjectID,
		"GOOGLE_APPLICATION_CREDENTIALS": c.CredentialsFile,
		"GCP_BIGQUERY_DATASET":           c.BigQueryDataset,
		"GCP_PUBSUB_TOPIC":               c.PubSubTopic,
		"GCP_STORAGE_BUCKET":             c.StorageBucket,
	}

	for key, value := range required {
		if value == "" {
			return fmt.Errorf("%s is required", key)
		}
	}

	return nil
}

func getRequiredPositiveInt(key string) (int, error) {
	raw := os.Getenv(key)
	if raw == "" {
		return 0, fmt.Errorf("%s is required", key)
	}

	value, err := strconv.Atoi(raw)
	if err != nil {
		return 0, fmt.Errorf("%s must be an integer: %w", key, err)
	}
	if value <= 0 {
		return 0, fmt.Errorf("%s must be greater than zero", key)
	}

	return value, nil
}
