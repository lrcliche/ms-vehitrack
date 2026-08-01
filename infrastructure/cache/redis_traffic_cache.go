package cache

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"

	"github.com/redis/go-redis/v9"
)

// RedisTrafficCache caches corridor aggregates with short TTL.
type RedisTrafficCache struct {
	client *redis.Client
}

func NewRedisTrafficCache(addr string, password string, db int) (*RedisTrafficCache, error) {
	client := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: password,
		DB:       db,
	})
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := client.Ping(ctx).Err(); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("redis ping: %w", err)
	}
	return &RedisTrafficCache{client: client}, nil
}

func (c *RedisTrafficCache) Close() error {
	if c == nil || c.client == nil {
		return nil
	}
	return c.client.Close()
}

func cacheKey(corridor string, slot int) string {
	return fmt.Sprintf("traffic:agg:%s:%d", corridor, slot)
}

func (c *RedisTrafficCache) GetAggregates(
	ctx context.Context,
	corridor string,
	slot int,
) ([]entities.TrafficAggregate, bool, error) {
	raw, err := c.client.Get(ctx, cacheKey(corridor, slot)).Bytes()
	if err == redis.Nil {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, fmt.Errorf("%w: get: %v", ports.ErrTrafficCacheFailed, err)
	}
	var rows []entities.TrafficAggregate
	if err := json.Unmarshal(raw, &rows); err != nil {
		return nil, false, fmt.Errorf("%w: unmarshal: %v", ports.ErrTrafficCacheFailed, err)
	}
	return rows, true, nil
}

func (c *RedisTrafficCache) SetAggregates(
	ctx context.Context,
	corridor string,
	slot int,
	rows []entities.TrafficAggregate,
	ttlSeconds int,
) error {
	if ttlSeconds <= 0 {
		ttlSeconds = 600
	}
	raw, err := json.Marshal(rows)
	if err != nil {
		return fmt.Errorf("%w: marshal: %v", ports.ErrTrafficCacheFailed, err)
	}
	if err := c.client.Set(ctx, cacheKey(corridor, slot), raw, time.Duration(ttlSeconds)*time.Second).Err(); err != nil {
		return fmt.Errorf("%w: set: %v", ports.ErrTrafficCacheFailed, err)
	}
	return nil
}

func (c *RedisTrafficCache) InvalidateCorridor(ctx context.Context, corridor string, slot int) error {
	if err := c.client.Del(ctx, cacheKey(corridor, slot)).Err(); err != nil {
		return fmt.Errorf("%w: del: %v", ports.ErrTrafficCacheFailed, err)
	}
	return nil
}
