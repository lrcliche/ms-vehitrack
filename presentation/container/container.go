package container

import (
	"context"
	"fmt"
	"log"
	"time"

	assignmentapp "ms-vehitrack/application/assignments"
	"ms-vehitrack/application/businessauth"
	"ms-vehitrack/application/config"
	"ms-vehitrack/application/geocoding"
	"ms-vehitrack/application/packages"
	"ms-vehitrack/application/routing"
	"ms-vehitrack/application/servicerequests"
	"ms-vehitrack/application/services"
	"ms-vehitrack/application/tracking"
	"ms-vehitrack/application/trafficquery"
	"ms-vehitrack/application/usecases"
	"ms-vehitrack/application/userdata"
	"ms-vehitrack/domain/ports"
	"ms-vehitrack/infrastructure/cache"
	"ms-vehitrack/infrastructure/database"
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
	trafficsrc "ms-vehitrack/infrastructure/traffic"
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
	offlineService   *packages.Service
	userDataService  *userdata.Service

	// F4/F6/F7: ruteo (cascada OSRM), ingesta+viajes+OBD, y lecturas de trafico por bbox.
	routingService        *routing.Service
	assignmentService     *assignmentapp.Service
	serviceRequestService *servicerequests.Service
	businessAuthService   *businessauth.Service
	trackingService       *tracking.Service
	trafficQueryService   *trafficquery.Service
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

	// Preferencia: Postgres vía tracking.prc_ingest_telemetry (reemplaza BigQuery).
	if dbPool != nil {
		telemetryStore = stores.NewPostgresTelemetryStore(dbPool)
		log.Printf("[CONTAINER] operation=telemetry-store status=postgres-prc_ingest_telemetry")
	}

	if gcpCfg.BigQueryEnabled {
		client, err := gcpbigquery.NewClient(ctx, gcpCfg)
		if err != nil {
			_ = pubSubClient.Close()
			cleanupDB()
			return nil, err
		}
		bigQueryClient = client

		if telemetryStore == nil {
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
			log.Printf("[CONTAINER] operation=bigquery status=skipped-postgres-preferred")
		}
	} else if telemetryStore == nil {
		log.Printf("[CONTAINER] operation=telemetry-store status=disabled")
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
		// Job de flujo libre: prerequisito para que el ETA con trafico crowd
		// produzca factor (sin free_flow, fnc_route_eta cae a flujo libre). Antes
		// solo lo corria un cron externo; ahora se agenda aqui.
		go runFreeFlowJob(aggCtx, trafficStore)
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

	// Paquetes offline: store PG (offline.* global + device.* tenant-scoped). Requiere BD.
	var offlineService *packages.Service
	if dbPool != nil {
		offlineStore := repositories.NewPostgresOfflineStore(dbPool)
		offlineService = packages.NewService(offlineStore)
		log.Printf("[CONTAINER] operation=offline-packages status=enabled")
	} else {
		log.Printf("[CONTAINER] operation=offline-packages status=disabled")
	}

	// Datos del usuario + sync + registro: store PG (device.* tenant-scoped + provision sin
	// tenant). Requiere BD.
	var userDataService *userdata.Service
	if dbPool != nil {
		userDataStore := repositories.NewPostgresUserDataStore(dbPool)
		userDataService = userdata.NewService(userDataStore)
		log.Printf("[CONTAINER] operation=userdata status=enabled")
	} else {
		log.Printf("[CONTAINER] operation=userdata status=disabled")
	}

	// F4 — Ruteo: store PG (routing.* + device.* tenant-scoped) + motor OSRM (cascada de cache).
	var routingService *routing.Service
	if dbPool != nil {
		routingStore := repositories.NewPostgresRoutingStore(dbPool)
		routingService = routing.NewService(routingStore, osrm.NewEngine(osrmClient))
		// Arranque TomTom: si hay key, el ETA de rutas se rellena desde TomTom Flow para las
		// rutas sin señal colaborativa. Sin key, el ETA se queda en crowd/flujo libre.
		if cfg.TomTomAPIKey != "" {
			routingService = routingService.WithTrafficETA(
				trafficsrc.NewTomTomETA(cfg.TomTomAPIKey, cfg.TrafficBaseURL, nil))
			log.Printf("[CONTAINER] operation=routing-eta source=tomtom status=enabled")
		}
		log.Printf("[CONTAINER] operation=routing status=enabled")
	} else {
		log.Printf("[CONTAINER] operation=routing status=disabled")
	}

	var assignmentService *assignmentapp.Service
	if dbPool != nil {
		assignmentService = assignmentapp.NewService(
			repositories.NewPostgresAssignmentCandidateStore(dbPool), routingService)
		log.Printf("[CONTAINER] operation=assignment-candidates status=enabled")
	} else {
		log.Printf("[CONTAINER] operation=assignment-candidates status=disabled")
	}
	var serviceRequestService *servicerequests.Service
	if dbPool != nil {
		serviceRequestService = servicerequests.NewService(
			repositories.NewPostgresServiceRequestStore(dbPool), routingService)
		log.Printf("[CONTAINER] operation=service-requests status=enabled")
	} else {
		log.Printf("[CONTAINER] operation=service-requests status=disabled")
	}

	// F6 — Ingesta por lote + viajes + sesiones OBD: store PG (tracking.*/device.* tenant-scoped).
	var trackingService *tracking.Service
	if dbPool != nil {
		trackingStore := repositories.NewPostgresTrackingStore(dbPool)
		trackingService = tracking.NewService(trackingStore)
		log.Printf("[CONTAINER] operation=tracking status=enabled")
	} else {
		log.Printf("[CONTAINER] operation=tracking status=disabled")
	}

	// F7 — Lecturas de trafico por bbox: store PG (traffic.* global, sin RLS).
	var trafficQueryService *trafficquery.Service
	if dbPool != nil {
		trafficQueryStore := repositories.NewPostgresTrafficQueryStore(dbPool)
		trafficQueryService = trafficquery.NewService(trafficQueryStore)
		log.Printf("[CONTAINER] operation=traffic-query status=enabled")
	} else {
		log.Printf("[CONTAINER] operation=traffic-query status=disabled")
	}

	var businessAuthService *businessauth.Service
	if dbPool != nil {
		businessAuthService = businessauth.NewService(
			repositories.NewPostgresBusinessAuthStore(dbPool), cfg.JWTSigningKey, cfg.JWTIssuer)
		log.Printf("[CONTAINER] operation=business-auth status=enabled")
	} else {
		log.Printf("[CONTAINER] operation=business-auth status=disabled")
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
		offlineService:          offlineService,
		userDataService:         userDataService,
		routingService:          routingService,
		assignmentService:       assignmentService,
		serviceRequestService:   serviceRequestService,
		trackingService:         trackingService,
		trafficQueryService:     trafficQueryService,
		businessAuthService:     businessAuthService,
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

// runFreeFlowJob recalcula el flujo libre (p85 nocturno, 28 dias) al arrancar y
// luego cada 12 h. Es lo que faltaba: sin free_flow poblado, el ETA con trafico
// crowd nunca produce factor (fnc_route_eta exige free_flow_speed_kmh NOT NULL).
// Idempotente; corre en su propia goroutine y no bloquea el arranque.
func runFreeFlowJob(ctx context.Context, store ports.TrafficStorePort) {
	run := func() {
		if err := store.RecomputeFreeFlow(ctx, 28); err != nil {
			log.Printf("[TRAFFIC] operation=recompute-free-flow error=%v", err)
		} else {
			log.Printf("[TRAFFIC] operation=recompute-free-flow status=ok")
		}
	}
	run() // una vez al arrancar, para poblar free_flow pronto tras el deploy
	ticker := time.NewTicker(12 * time.Hour)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			run()
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
	if c.telemetryStore == nil && c.gcpConfig.BigQueryEnabled {
		return fmt.Errorf("telemetry store is not ready")
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

// ResolveOfflineService devuelve el servicio de paquetes offline; false si Postgres está
// deshabilitado.
func (c *Container) ResolveOfflineService() (*packages.Service, bool) {
	if c.offlineService == nil {
		return nil, false
	}
	return c.offlineService, true
}

// ResolveUserDataService devuelve el servicio de datos del usuario + sync + registro; false si
// Postgres está deshabilitado.
func (c *Container) ResolveUserDataService() (*userdata.Service, bool) {
	if c.userDataService == nil {
		return nil, false
	}
	return c.userDataService, true
}

// ResolveRoutingService devuelve el servicio de ruteo (cascada OSRM); false si Postgres está
// deshabilitado.
func (c *Container) ResolveRoutingService() (*routing.Service, bool) {
	if c.routingService == nil {
		return nil, false
	}
	return c.routingService, true
}

func (c *Container) ResolveAssignmentService() (*assignmentapp.Service, bool) {
	if c.assignmentService == nil {
		return nil, false
	}
	return c.assignmentService, true
}

func (c *Container) ResolveServiceRequestService() (*servicerequests.Service, bool) {
	if c.serviceRequestService == nil {
		return nil, false
	}
	return c.serviceRequestService, true
}

func (c *Container) ResolveBusinessAuthService() (*businessauth.Service, bool) {
	if c.businessAuthService == nil {
		return nil, false
	}
	return c.businessAuthService, true
}

// ResolveTrackingService devuelve el servicio de ingesta por lote + viajes + OBD; false si
// Postgres está deshabilitado.
func (c *Container) ResolveTrackingService() (*tracking.Service, bool) {
	if c.trackingService == nil {
		return nil, false
	}
	return c.trackingService, true
}

// ResolveTrafficQueryService devuelve el servicio de lecturas de trafico por bbox; false si
// Postgres está deshabilitado.
func (c *Container) ResolveTrafficQueryService() (*trafficquery.Service, bool) {
	if c.trafficQueryService == nil {
		return nil, false
	}
	return c.trafficQueryService, true
}
