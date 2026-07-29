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
	"ms-vehitrack/infrastructure/repositories"
	"ms-vehitrack/presentation/handlers"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Container struct {
	config                     config.Config
	gcpConfig                  gcpconfig.Config
	dbPool                     *pgxpool.Pool
	bigQueryClient             *gcpbigquery.Client
	pubSubClient               *gcppubsub.Client
	storageClient              *gcpstorage.Client
	productRepository          ports.ProductRepository
	telemetryPublisher         ports.TelemetryPublisherPort
	productService             services.ProductService
	publishTelemetryUseCase    usecases.PublishTelemetryUseCase
	productHandler             *handlers.ProductHandler
	telemetryHandler           *handlers.TelemetryHandler
}

func NewContainer(ctx context.Context, cfg config.Config) (*Container, error) {
	dbPool, err := database.NewPostgresPool(ctx, cfg.PostgresDSN)
	if err != nil {
		return nil, fmt.Errorf("create postgres pool: %w", err)
	}

	gcpCfg, err := gcpconfig.Load()
	if err != nil {
		dbPool.Close()
		return nil, fmt.Errorf("load gcp config: %w", err)
	}

	bigQueryClient, err := gcpbigquery.NewClient(ctx, gcpCfg)
	if err != nil {
		dbPool.Close()
		return nil, err
	}

	pubSubClient, err := gcppubsub.NewClient(ctx, gcpCfg)
	if err != nil {
		_ = bigQueryClient.Close()
		dbPool.Close()
		return nil, err
	}

	storageClient, err := gcpstorage.NewClient(ctx, gcpCfg)
	if err != nil {
		_ = pubSubClient.Close()
		_ = bigQueryClient.Close()
		dbPool.Close()
		return nil, err
	}

	return &Container{
		config:         cfg,
		gcpConfig:      gcpCfg,
		dbPool:         dbPool,
		bigQueryClient: bigQueryClient,
		pubSubClient:   pubSubClient,
		storageClient:  storageClient,
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

func (c *Container) ResolveProductRepository() ports.ProductRepository {
	if c.productRepository == nil {
		c.productRepository = repositories.NewPostgresProductRepository(c.dbPool)
	}
	return c.productRepository
}

func (c *Container) ResolveTelemetryPublisher() ports.TelemetryPublisherPort {
	if c.telemetryPublisher == nil {
		c.telemetryPublisher = publishers.NewPubSubTelemetryPublisher(c.pubSubClient, c.gcpConfig)
	}
	return c.telemetryPublisher
}

func (c *Container) ResolveProductService() services.ProductService {
	if c.productService == nil {
		c.productService = services.NewProductService(c.ResolveProductRepository())
	}
	return c.productService
}

func (c *Container) ResolvePublishTelemetryUseCase() usecases.PublishTelemetryUseCase {
	if c.publishTelemetryUseCase == nil {
		c.publishTelemetryUseCase = usecases.NewPublishTelemetryUseCase(c.ResolveTelemetryPublisher())
	}
	return c.publishTelemetryUseCase
}

func (c *Container) ResolveProductHandler() *handlers.ProductHandler {
	if c.productHandler == nil {
		c.productHandler = handlers.NewProductHandler(c)
	}
	return c.productHandler
}

func (c *Container) ResolveTelemetryHandler() *handlers.TelemetryHandler {
	if c.telemetryHandler == nil {
		c.telemetryHandler = handlers.NewTelemetryHandler(c)
	}
	return c.telemetryHandler
}
