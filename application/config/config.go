package config

import (
	"log"
	"os"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

type Config struct {
	AppEnv              string
	HTTPPort            string
	ReadTimeoutSeconds  int
	WriteTimeoutSeconds int
	PostgresEnabled     bool
	PostgresDSN         string
}

func MustLoad() Config {
	err := godotenv.Load()
	if err != nil {
		log.Println("No .env file found")
	}

	cfg := Config{
		AppEnv:              getEnv("APP_ENV", "development"),
		HTTPPort:            getEnv("HTTP_PORT", "8080"),
		ReadTimeoutSeconds:  getEnvAsInt("READ_TIMEOUT_SECONDS", 10),
		WriteTimeoutSeconds: getEnvAsInt("WRITE_TIMEOUT_SECONDS", 10),
		PostgresEnabled:     getEnvAsBool("POSTGRES_ENABLED", false),
		PostgresDSN:         os.Getenv("POSTGRES_DSN"),
	}

	if cfg.PostgresEnabled && cfg.PostgresDSN == "" {
		log.Fatal("POSTGRES_DSN is required when POSTGRES_ENABLED=true")
	}

	return cfg
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func getEnvAsInt(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}

	return parsed
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
