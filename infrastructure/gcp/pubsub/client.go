package pubsub

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"cloud.google.com/go/pubsub/v2"
	gcpconfig "ms-vehitrack/infrastructure/gcp/config"
	"google.golang.org/api/option"
)

// Client is a reusable Pub/Sub adapter without domain knowledge.
type Client struct {
	client     *pubsub.Client
	timeout    time.Duration
	publishers map[string]*pubsub.Publisher
	mu         sync.Mutex
}

// NewClient creates a Pub/Sub client using GCP configuration.
func NewClient(ctx context.Context, cfg gcpconfig.Config) (*Client, error) {
	opts := make([]option.ClientOption, 0, 1)
	if cfg.HasCredentialsFile() {
		opts = append(opts, option.WithCredentialsFile(cfg.CredentialsFile))
	}

	client, err := pubsub.NewClient(ctx, cfg.ProjectID, opts...)
	if err != nil {
		return nil, fmt.Errorf("create pubsub client: %w", err)
	}

	return &Client{
		client:     client,
		timeout:    cfg.ClientTimeout,
		publishers: make(map[string]*pubsub.Publisher),
	}, nil
}

// Topic returns a reusable publisher for the given topic identifier.
func (c *Client) Topic(topicID string) (*pubsub.Publisher, error) {
	if topicID == "" {
		return nil, fmt.Errorf("pubsub topic id is required")
	}

	c.mu.Lock()
	defer c.mu.Unlock()

	if publisher, ok := c.publishers[topicID]; ok {
		return publisher, nil
	}

	publisher := c.client.Publisher(topicID)
	c.publishers[topicID] = publisher
	return publisher, nil
}

// PublishAsync enqueues a message for publish and returns once accepted by the local client.
// Delivery acknowledgment is confirmed asynchronously to keep the HTTP hot path non-blocking.
func (c *Client) PublishAsync(ctx context.Context, topicID string, data []byte, attributes map[string]string) error {
	if len(data) == 0 {
		return fmt.Errorf("pubsub message data is required")
	}

	publisher, err := c.Topic(topicID)
	if err != nil {
		return err
	}

	if err := ctx.Err(); err != nil {
		return fmt.Errorf("publish pubsub message to %s: %w", topicID, err)
	}

	result := publisher.Publish(ctx, &pubsub.Message{
		Data:       data,
		Attributes: attributes,
	})

	go func() {
		ackCtx, cancel := context.WithTimeout(context.Background(), c.timeout)
		defer cancel()
		if _, err := result.Get(ackCtx); err != nil {
			log.Printf("[PUBSUB] operation=PublishAsync status=ack-failed topic=%s error=%v", topicID, err)
		}
	}()

	return nil
}

// Ready reports whether the client is initialized.
func (c *Client) Ready() bool {
	return c != nil && c.client != nil
}

// Close stops publishers and releases Pub/Sub client resources.
func (c *Client) Close() error {
	if c == nil {
		return nil
	}

	c.mu.Lock()
	for topicID, publisher := range c.publishers {
		publisher.Stop()
		delete(c.publishers, topicID)
	}
	c.mu.Unlock()

	if c.client == nil {
		return nil
	}
	if err := c.client.Close(); err != nil {
		return fmt.Errorf("close pubsub client: %w", err)
	}
	return nil
}
