package config

import (
	"log"
	"os"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

type Config struct {
	AppEnv                   string
	HTTPPort                 string
	ReadTimeoutSeconds       int
	WriteTimeoutSeconds      int
	ReadHeaderTimeoutSeconds int
	IdleTimeoutSeconds       int
	ShutdownTimeoutSeconds   int
	MaxBodyBytes             int64
	APIKey                   string
	RateLimitRPS             float64
	RateLimitBurst           int
	PostgresEnabled          bool
	PostgresDSN              string
	RedisEnabled             bool
	RedisAddr                string
	RedisPassword            string
	RedisDB                  int
	TrafficCacheTTLSeconds   int
	TrafficMinSamples        int
	TrafficMinDevices        int
	TelemetryMaxAgeSeconds   int
	TelemetryMaxSkewSeconds  int
	// Geo (modelo PG multi-tenant)
	NominatimURL          string
	OSRMURL               string
	TenantCacheTTLSeconds int
}

func MustLoad() Config {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found")
	}

	cfg := Config{
		AppEnv:                   getEnv("APP_ENV", "development"),
		HTTPPort:                 getEnv("HTTP_PORT", "19560"),
		ReadTimeoutSeconds:       getEnvAsInt("READ_TIMEOUT_SECONDS", 10),
		WriteTimeoutSeconds:      getEnvAsInt("WRITE_TIMEOUT_SECONDS", 10),
		ReadHeaderTimeoutSeconds: getEnvAsInt("READ_HEADER_TIMEOUT_SECONDS", 5),
		IdleTimeoutSeconds:       getEnvAsInt("IDLE_TIMEOUT_SECONDS", 60),
		ShutdownTimeoutSeconds:   getEnvAsInt("SHUTDOWN_TIMEOUT_SECONDS", 10),
		MaxBodyBytes:             int64(getEnvAsInt("MAX_BODY_BYTES", 65536)),
		APIKey:                   os.Getenv("API_KEY"),
		RateLimitRPS:             getEnvAsFloat("RATE_LIMIT_RPS", 20),
		RateLimitBurst:           getEnvAsInt("RATE_LIMIT_BURST", 40),
		PostgresEnabled:          getEnvAsBool("POSTGRES_ENABLED", false),
		PostgresDSN:              os.Getenv("POSTGRES_DSN"),
		RedisEnabled:             getEnvAsBool("REDIS_ENABLED", false),
		RedisAddr:                getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword:            os.Getenv("REDIS_PASSWORD"),
		RedisDB:                  getEnvAsInt("REDIS_DB", 0),
		TrafficCacheTTLSeconds:   getEnvAsInt("TRAFFIC_CACHE_TTL_SECONDS", 600),
		TrafficMinSamples:        getEnvAsInt("TRAFFIC_MIN_SAMPLES", 5),
		TrafficMinDevices:        getEnvAsInt("TRAFFIC_MIN_DEVICES", 3),
		TelemetryMaxAgeSeconds:   getEnvAsInt("TELEMETRY_MAX_AGE_SECONDS", 86400),
		TelemetryMaxSkewSeconds:  getEnvAsInt("TELEMETRY_MAX_SKEW_SECONDS", 300),
		NominatimURL:             getEnv("NOMINATIM_URL", "http://127.0.0.1:21001"),
		OSRMURL:                  getEnv("OSRM_URL", "http://127.0.0.1:21002"),
		TenantCacheTTLSeconds:    getEnvAsInt("TENANT_CACHE_TTL_SECONDS", 60),
	}

	if cfg.APIKey == "" {
		log.Fatal("API_KEY is required")
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

func getEnvAsFloat(key string, fallback float64) float64 {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseFloat(value, 64)
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
