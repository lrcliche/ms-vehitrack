package database

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Pool wraps a PostgreSQL connection pool without leaking driver details to callers.
type Pool struct {
	inner *pgxpool.Pool
}

// NewPostgresPool creates a PostgreSQL pool from a DSN.
func NewPostgresPool(ctx context.Context, dsn string) (*Pool, error) {
	log.Printf("[DATABASE] Connecting to PostgreSQL host=%s", redactDSNHost(dsn))

	config, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("parse postgres dsn: %w", err)
	}

	inner, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("create postgres pool: %w", err)
	}

	if err := inner.Ping(ctx); err != nil {
		inner.Close()
		return nil, fmt.Errorf("ping postgres: %w", err)
	}

	return &Pool{inner: inner}, nil
}

// Ping verifies database connectivity.
func (p *Pool) Ping(ctx context.Context) error {
	if p == nil || p.inner == nil {
		return fmt.Errorf("postgres pool is not initialized")
	}
	return p.inner.Ping(ctx)
}

// Close releases pool resources.
func (p *Pool) Close() {
	if p != nil && p.inner != nil {
		p.inner.Close()
	}
}

func (p *Pool) Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error) {
	return p.inner.Exec(ctx, sql, args...)
}

func (p *Pool) Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error) {
	return p.inner.Query(ctx, sql, args...)
}

func (p *Pool) QueryRow(ctx context.Context, sql string, args ...any) pgx.Row {
	return p.inner.QueryRow(ctx, sql, args...)
}

func (p *Pool) Begin(ctx context.Context) (pgx.Tx, error) {
	return p.inner.Begin(ctx)
}

func redactDSNHost(dsn string) string {
	parsed, err := url.Parse(dsn)
	if err != nil || parsed.Host == "" {
		return "unknown"
	}
	host := parsed.Host
	if parsed.Path != "" && parsed.Path != "/" {
		return host + strings.TrimSuffix(parsed.Path, "/")
	}
	return host
}
