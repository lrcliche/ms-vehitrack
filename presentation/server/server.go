package server

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"ms-vehitrack/application/config"
	"ms-vehitrack/presentation/container"
	"ms-vehitrack/presentation/routes"
)

type Server struct {
	container  *container.Container
	httpServer *http.Server
	shutdown   time.Duration
}

func NewServer(ctx context.Context, cfg config.Config) (*Server, error) {
	appContainer, err := container.New(ctx, cfg)
	if err != nil {
		return nil, err
	}

	engine := routes.New(appContainer)

	httpServer := &http.Server{
		Addr:              ":" + cfg.HTTPPort,
		Handler:           engine,
		ReadHeaderTimeout: time.Duration(cfg.ReadHeaderTimeoutSeconds) * time.Second,
		ReadTimeout:       time.Duration(cfg.ReadTimeoutSeconds) * time.Second,
		WriteTimeout:      time.Duration(cfg.WriteTimeoutSeconds) * time.Second,
		IdleTimeout:       time.Duration(cfg.IdleTimeoutSeconds) * time.Second,
	}

	return &Server{
		container:  appContainer,
		httpServer: httpServer,
		shutdown:   time.Duration(cfg.ShutdownTimeoutSeconds) * time.Second,
	}, nil
}

func (s *Server) Run() error {
	defer s.Close()

	log.Printf("[BOOT] operation=start-server message=server running on http://localhost%s", s.httpServer.Addr)

	listenErr := make(chan error, 1)
	go func() {
		if err := s.httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			listenErr <- err
			return
		}
		listenErr <- nil
	}()

	stopSignal := make(chan os.Signal, 1)
	signal.Notify(stopSignal, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(stopSignal)

	select {
	case err := <-listenErr:
		if err != nil {
			return err
		}
		return nil
	case <-stopSignal:
	}

	shutdownContext, cancel := context.WithTimeout(context.Background(), s.shutdown)
	defer cancel()

	if err := s.httpServer.Shutdown(shutdownContext); err != nil {
		return err
	}

	if err := <-listenErr; err != nil {
		return err
	}

	log.Printf("[BOOT] operation=shutdown message=server stopped")
	return nil
}

func (s *Server) Close() {
	if s.container != nil {
		s.container.Close()
	}
}
