package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Config holds Google Cloud settings loaded from environment variables.
type Config struct {
	ProjectID                 string
	CredentialsFile           string
	PubSubTopic               string
	BigQueryEnabled           bool
	BigQueryDataset           string
	StorageEnabled            bool
	StorageBucket             string
	ClientTimeout             time.Duration
	PubSubPublishRetries      int
	PubSubPublishRetryBackoff time.Duration
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
		CredentialsFile:           strings.TrimSpace(os.Getenv("GOOGLE_APPLICATION_CREDENTIALS")),
		PubSubTopic:               os.Getenv("GCP_PUBSUB_TOPIC"),
		BigQueryEnabled:           getEnvAsBool("GCP_BIGQUERY_ENABLED", false),
		BigQueryDataset:           os.Getenv("GCP_BIGQUERY_DATASET"),
		StorageEnabled:            getEnvAsBool("GCP_STORAGE_ENABLED", false),
		StorageBucket:             os.Getenv("GCP_STORAGE_BUCKET"),
		ClientTimeout:             time.Duration(timeoutSeconds) * time.Second,
		PubSubPublishRetries:      retries,
		PubSubPublishRetryBackoff: time.Duration(backoffMillis) * time.Millisecond,
	}

	if err := cfg.validate(); err != nil {
		return Config{}, err
	}

	if cfg.CredentialsFile != "" {
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
	}

	return cfg, nil
}

func (c Config) validate() error {
	if c.ProjectID == "" {
		return fmt.Errorf("GCP_PROJECT_ID is required")
	}
	if c.PubSubTopic == "" {
		return fmt.Errorf("GCP_PUBSUB_TOPIC is required")
	}
	if c.BigQueryEnabled && c.BigQueryDataset == "" {
		return fmt.Errorf("GCP_BIGQUERY_DATASET is required when GCP_BIGQUERY_ENABLED=true")
	}
	if c.StorageEnabled && c.StorageBucket == "" {
		return fmt.Errorf("GCP_STORAGE_BUCKET is required when GCP_STORAGE_ENABLED=true")
	}
	return nil
}

// ClientOptions returns credential path when configured (empty means ADC).
func (c Config) HasCredentialsFile() bool {
	return c.CredentialsFile != ""
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

func getEnvAsBool(key string, fallback bool) bool {
	value := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}
