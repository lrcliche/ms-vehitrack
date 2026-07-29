package container

import (
	"context"
	"fmt"
	"log"

	"ms-vehitrack/application/config"
	"ms-vehitrack/application/services"
	"ms-vehitrack/application/usecases"
	"ms-vehitrack/domain/ports"
	"ms-vehitrack/infrastructure/database"
	gcpbigquery "ms-vehitrack/infrastructure/gcp/bigquery"
	gcpconfig "ms-vehitrack/infrastructure/gcp/config"
	gcppubsub "ms-vehitrack/infrastructure/gcp/pubsub"
	gcpstorage "ms-vehitrack/infrastructure/gcp/storage"
	"ms-vehitrack/infrastructure/publishers"
	"ms-vehitrack/presentation/handlers"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Container struct {
	// config
	config    config.Config
	gcpConfig gcpconfig.Config

	// infrastructure (technical adapters, not used by handlers)
	dbPool         *pgxpool.Pool
	bigQueryClient *gcpbigquery.Client
	pubSubClient   *gcppubsub.Client
	storageClient  *gcpstorage.Client

	// domain ports
	telemetryPublisher ports.TelemetryPublisherPort

	// application
	telemetryService        services.TelemetryService
	publishTelemetryUseCase usecases.PublishTelemetryUseCase

	// presentation
	telemetryHandler *handlers.TelemetryHandler
}

func NewContainer(ctx context.Context, cfg config.Config) (*Container, error) {
	var dbPool *pgxpool.Pool
	if cfg.PostgresEnabled {
		pool, err := database.NewPostgresPool(ctx, cfg.PostgresDSN)
		if err != nil {
			return nil, fmt.Errorf("create postgres pool: %w", err)
		}
		dbPool = pool
		log.Printf("[CONTAINER] operation=postgres status=enabled")
	} else {
		log.Printf("[CONTAINER] operation=postgres status=disabled")
	}

	cleanup := func() {
		if dbPool != nil {
			dbPool.Close()
		}
	}

	gcpCfg, err := gcpconfig.Load()
	if err != nil {
		cleanup()
		return nil, fmt.Errorf("load gcp config: %w", err)
	}

	bigQueryClient, err := gcpbigquery.NewClient(ctx, gcpCfg)
	if err != nil {
		cleanup()
		return nil, err
	}

	pubSubClient, err := gcppubsub.NewClient(ctx, gcpCfg)
	if err != nil {
		_ = bigQueryClient.Close()
		cleanup()
		return nil, err
	}

	storageClient, err := gcpstorage.NewClient(ctx, gcpCfg)
	if err != nil {
		_ = pubSubClient.Close()
		_ = bigQueryClient.Close()
		cleanup()
		return nil, err
	}

	// ports
	telemetryPublisher := ports.TelemetryPublisherPort(
		publishers.NewPubSubTelemetryPublisher(pubSubClient, gcpCfg),
	)

	// use cases + services
	publishTelemetryUseCase := usecases.NewPublishTelemetryUseCase(telemetryPublisher)
	telemetryService := services.NewTelemetryService(publishTelemetryUseCase)

	return &Container{
		config:                  cfg,
		gcpConfig:               gcpCfg,
		dbPool:                  dbPool,
		bigQueryClient:          bigQueryClient,
		pubSubClient:            pubSubClient,
		storageClient:           storageClient,
		telemetryPublisher:      telemetryPublisher,
		telemetryService:        telemetryService,
		publishTelemetryUseCase: publishTelemetryUseCase,
	}, nil
}

func New(ctx context.Context, cfg config.Config) (*Container, error) {
	return NewContainer(ctx, cfg)
}

func (c *Container) Config() config.Config {
	return c.config
}

func (c *Container) GCPConfig() gcpconfig.Config {
	return c.gcpConfig
}

// PostgresEnabled reports whether PostgreSQL was configured and connected.
func (c *Container) PostgresEnabled() bool {
	return c.config.PostgresEnabled && c.dbPool != nil
}

func (c *Container) Close() {
	if c.storageClient != nil {
		if err := c.storageClient.Close(); err != nil {
			log.Printf("[CONTAINER] operation=close-storage error=%v", err)
		}
	}
	if c.pubSubClient != nil {
		if err := c.pubSubClient.Close(); err != nil {
			log.Printf("[CONTAINER] operation=close-pubsub error=%v", err)
		}
	}
	if c.bigQueryClient != nil {
		if err := c.bigQueryClient.Close(); err != nil {
			log.Printf("[CONTAINER] operation=close-bigquery error=%v", err)
		}
	}
	if c.dbPool != nil {
		c.dbPool.Close()
	}
}

func (c *Container) BigQueryClient() *gcpbigquery.Client {
	return c.bigQueryClient
}

func (c *Container) PubSubClient() *gcppubsub.Client {
	return c.pubSubClient
}

func (c *Container) StorageClient() *gcpstorage.Client {
	return c.storageClient
}

func (c *Container) ResolveTelemetryPublisher() ports.TelemetryPublisherPort {
	return c.telemetryPublisher
}

func (c *Container) ResolvePublishTelemetryUseCase() usecases.PublishTelemetryUseCase {
	return c.publishTelemetryUseCase
}

func (c *Container) ResolveTelemetryService() services.TelemetryService {
	return c.telemetryService
}

func (c *Container) ResolveTelemetryHandler() *handlers.TelemetryHandler {
	if c.telemetryHandler == nil {
		c.telemetryHandler = handlers.NewTelemetryHandler(c)
	}
	return c.telemetryHandler
}
