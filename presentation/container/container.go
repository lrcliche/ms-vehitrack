package container

import (
	"context"
	"fmt"
	"log"
	"time"

	"ms-vehitrack/application/config"
	"ms-vehitrack/application/geocoding"
	"ms-vehitrack/application/services"
	"ms-vehitrack/application/usecases"
	"ms-vehitrack/domain/ports"
	"ms-vehitrack/infrastructure/database"
	"ms-vehitrack/infrastructure/cache"
	gcpbigquery "ms-vehitrack/infrastructure/gcp/bigquery"
	gcpconfig "ms-vehitrack/infrastructure/gcp/config"
	gcppubsub "ms-vehitrack/infrastructure/gcp/pubsub"
	gcpstorage "ms-vehitrack/infrastructure/gcp/storage"
	"ms-vehitrack/infrastructure/nominatim"
	"ms-vehitrack/infrastructure/osrm"
	"ms-vehitrack/infrastructure/publishers"
	"ms-vehitrack/infrastructure/repositories"
	"ms-vehitrack/infrastructure/stores"
	"ms-vehitrack/infrastructure/tenant"
	"ms-vehitrack/presentation/handlers"
)

type Container struct {
	config    config.Config
	gcpConfig gcpconfig.Config

	dbPool         *database.Pool
	bigQueryClient *gcpbigquery.Client
	pubSubClient   *gcppubsub.Client
	storageClient  *gcpstorage.Client
	redisCache     *cache.RedisTrafficCache

	telemetryPublisher ports.TelemetryPublisherPort
	telemetryStore     ports.TelemetryStorePort
	trafficStore       ports.TrafficStorePort
	trafficCache       ports.TrafficCachePort

	telemetryService        services.TelemetryService
	trafficService          services.TrafficService
	publishTelemetryUseCase usecases.PublishTelemetryUseCase

	telemetryHandler *handlers.TelemetryHandler
	aggStop          context.CancelFunc

	// Geo (modelo PG multi-tenant). Listos para F1: geocoder, rutas y middleware de tenant.
	nominatimClient  *nominatim.Client
	osrmClient       *osrm.Client
	tenantResolver   *tenant.Resolver
	geocodingService *geocoding.Service
}

func NewContainer(ctx context.Context, cfg config.Config) (*Container, error) {
	var dbPool *database.Pool
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

	cleanupDB := func() {
		if dbPool != nil {
			dbPool.Close()
		}
	}

	gcpCfg, err := gcpconfig.Load()
	if err != nil {
		cleanupDB()
		return nil, fmt.Errorf("load gcp config: %w", err)
	}

	pubSubClient, err := gcppubsub.NewClient(ctx, gcpCfg)
	if err != nil {
		cleanupDB()
		return nil, err
	}

	var bigQueryClient *gcpbigquery.Client
	var telemetryStore ports.TelemetryStorePort
	if gcpCfg.BigQueryEnabled {
		client, err := gcpbigquery.NewClient(ctx, gcpCfg)
		if err != nil {
			_ = pubSubClient.Close()
			cleanupDB()
			return nil, err
		}
		bigQueryClient = client

		store, err := stores.NewBigQueryTelemetryStore(ctx, client, gcpCfg)
		if err != nil {
			_ = bigQueryClient.Close()
			_ = pubSubClient.Close()
			cleanupDB()
			return nil, err
		}
		telemetryStore = store
		log.Printf("[CONTAINER] operation=bigquery status=enabled dataset=%s table=%s", gcpCfg.BigQueryDataset, gcpCfg.BigQueryTable)
	} else {
		log.Printf("[CONTAINER] operation=bigquery status=disabled")
	}

	var storageClient *gcpstorage.Client
	if gcpCfg.StorageEnabled {
		client, err := gcpstorage.NewClient(ctx, gcpCfg)
		if err != nil {
			if bigQueryClient != nil {
				_ = bigQueryClient.Close()
			}
			_ = pubSubClient.Close()
			cleanupDB()
			return nil, err
		}
		storageClient = client
		log.Printf("[CONTAINER] operation=storage status=enabled")
	} else {
		log.Printf("[CONTAINER] operation=storage status=disabled")
	}

	telemetryPublisher := ports.TelemetryPublisherPort(
		publishers.NewPubSubTelemetryPublisher(pubSubClient, gcpCfg),
	)

	publishTelemetryUseCase := usecases.NewPublishTelemetryUseCase(
		telemetryPublisher,
		telemetryStore,
		time.Duration(cfg.TelemetryMaxAgeSeconds)*time.Second,
		time.Duration(cfg.TelemetryMaxSkewSeconds)*time.Second,
	)
	telemetryService := services.NewTelemetryService(publishTelemetryUseCase)

	var trafficStore ports.TrafficStorePort
	var trafficCache ports.TrafficCachePort
	var redisCache *cache.RedisTrafficCache
	var trafficService services.TrafficService
	var aggStop context.CancelFunc

	if dbPool != nil {
		trafficStore = repositories.NewPostgresTrafficStore(dbPool)
		log.Printf("[CONTAINER] operation=traffic-store status=postgres")
	} else {
		log.Printf("[CONTAINER] operation=traffic-store status=disabled")
	}

	if cfg.RedisEnabled {
		rc, err := cache.NewRedisTrafficCache(cfg.RedisAddr, cfg.RedisPassword, cfg.RedisDB)
		if err != nil {
			if bigQueryClient != nil {
				_ = bigQueryClient.Close()
			}
			_ = pubSubClient.Close()
			if storageClient != nil {
				_ = storageClient.Close()
			}
			cleanupDB()
			return nil, fmt.Errorf("create redis cache: %w", err)
		}
		redisCache = rc
		trafficCache = rc
		log.Printf("[CONTAINER] operation=redis status=enabled addr=%s", cfg.RedisAddr)
	} else {
		log.Printf("[CONTAINER] operation=redis status=disabled")
	}

	if trafficStore != nil {
		ingestUC := usecases.NewIngestTrafficBatchUseCase(trafficStore, trafficCache)
		getUC := usecases.NewGetTrafficAggregatesUseCase(
			trafficStore,
			trafficCache,
			cfg.TrafficMinSamples,
			cfg.TrafficMinDevices,
			cfg.TrafficCacheTTLSeconds,
		)
		trafficService = services.NewTrafficService(ingestUC, getUC)

		// Job ligero: refresca agregados cada 10 min.
		aggCtx, cancel := context.WithCancel(context.Background())
		aggStop = cancel
		go runAggregateJob(aggCtx, trafficStore)
	}

	// Clientes geo (sin conexión en construcción: solo envuelven un http.Client con base URL).
	nominatimClient := nominatim.NewClient(cfg.NominatimURL, nil)
	osrmClient := osrm.NewClient(cfg.OSRMURL, nil)

	// Resolver de tenant: requiere BD. OJO: la Lookup debe ver todos los tenants (dueño o
	// rol BYPASSRLS) o el tenant venir del JWT — device.device tiene RLS. Ver tenant.Lookup.
	var tenantResolver *tenant.Resolver
	if dbPool != nil {
		tenantResolver = tenant.NewResolver(
			tenant.PoolLookup(dbPool),
			time.Duration(cfg.TenantCacheTTLSeconds)*time.Second,
		)
		log.Printf("[CONTAINER] operation=tenant-resolver status=enabled ttl=%ds", cfg.TenantCacheTTLSeconds)
	} else {
		log.Printf("[CONTAINER] operation=tenant-resolver status=disabled")
	}

	// Geocoder: store PG + proveedor Nominatim. Requiere BD (geo.* vive en PG).
	var geocodingService *geocoding.Service
	if dbPool != nil {
		geoStore := repositories.NewPostgresGeocodeStore(dbPool)
		geoProvider := nominatim.NewProvider(nominatimClient)
		geocodingService = geocoding.NewService(geoStore, geoProvider)
		log.Printf("[CONTAINER] operation=geocoding status=enabled")
	} else {
		log.Printf("[CONTAINER] operation=geocoding status=disabled")
	}

	return &Container{
		config:                  cfg,
		gcpConfig:               gcpCfg,
		dbPool:                  dbPool,
		bigQueryClient:          bigQueryClient,
		pubSubClient:            pubSubClient,
		storageClient:           storageClient,
		redisCache:              redisCache,
		telemetryPublisher:      telemetryPublisher,
		telemetryStore:          telemetryStore,
		trafficStore:            trafficStore,
		trafficCache:            trafficCache,
		telemetryService:        telemetryService,
		trafficService:          trafficService,
		publishTelemetryUseCase: publishTelemetryUseCase,
		aggStop:                 aggStop,
		nominatimClient:         nominatimClient,
		osrmClient:              osrmClient,
		tenantResolver:          tenantResolver,
		geocodingService:        geocodingService,
	}, nil
}

func runAggregateJob(ctx context.Context, store ports.TrafficStorePort) {
	ticker := time.NewTicker(10 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := store.RefreshAggregates(ctx, nil, 60); err != nil {
				log.Printf("[TRAFFIC] operation=refresh-aggregates error=%v", err)
			} else {
				log.Printf("[TRAFFIC] operation=refresh-aggregates status=ok")
			}
		}
	}
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

func (c *Container) PostgresEnabled() bool {
	return c.config.PostgresEnabled && c.dbPool != nil
}

func (c *Container) Ready(ctx context.Context) error {
	if c.pubSubClient == nil || !c.pubSubClient.Ready() {
		return fmt.Errorf("pubsub client is not ready")
	}
	if c.gcpConfig.BigQueryEnabled && c.telemetryStore == nil {
		return fmt.Errorf("bigquery store is not ready")
	}
	if c.PostgresEnabled() {
		if err := c.dbPool.Ping(ctx); err != nil {
			return fmt.Errorf("postgres is not ready: %w", err)
		}
	}
	return nil
}

func (c *Container) Close() {
	if c.aggStop != nil {
		c.aggStop()
	}
	if c.redisCache != nil {
		if err := c.redisCache.Close(); err != nil {
			log.Printf("[CONTAINER] operation=close-redis error=%v", err)
		}
	}
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

func (c *Container) ResolveTelemetryPublisher() ports.TelemetryPublisherPort {
	return c.telemetryPublisher
}

func (c *Container) ResolveTelemetryStore() ports.TelemetryStorePort {
	return c.telemetryStore
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

func (c *Container) ResolveTrafficService() (services.TrafficService, bool) {
	if c.trafficService == nil {
		return nil, false
	}
	return c.trafficService, true
}

// ResolveNominatimClient devuelve el cliente del geocoder de respaldo (siempre disponible).
func (c *Container) ResolveNominatimClient() *nominatim.Client {
	return c.nominatimClient
}

// ResolveOSRMClient devuelve el cliente de ruteo (siempre disponible).
func (c *Container) ResolveOSRMClient() *osrm.Client {
	return c.osrmClient
}

// ResolveTenantResolver devuelve el resolver de tenant; nil si Postgres está deshabilitado.
// Lo usará el middleware TenantContext en las rutas del modelo PG (F1+).
func (c *Container) ResolveTenantResolver() *tenant.Resolver {
	return c.tenantResolver
}

// DBPool expone el pool para los repositorios PG (que llaman WithTenantTx). nil si Postgres
// está deshabilitado.
func (c *Container) DBPool() *database.Pool {
	return c.dbPool
}

// ResolveGeocodingService devuelve el servicio de geocoding; false si Postgres está
// deshabilitado.
func (c *Container) ResolveGeocodingService() (*geocoding.Service, bool) {
	if c.geocodingService == nil {
		return nil, false
	}
	return c.geocodingService, true
}
