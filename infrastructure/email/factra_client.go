package email

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"ms-vehitrack/domain/ports"
)

type FactraClient struct {
	endpoint, apiKey, empresaID string
	client                      *http.Client
}

func NewFactraClient(endpoint, apiKey, empresaID string) *FactraClient {
	return &FactraClient{endpoint: strings.TrimSpace(endpoint), apiKey: apiKey, empresaID: strings.TrimSpace(empresaID), client: &http.Client{Timeout: 8 * time.Second}}
}

func (c *FactraClient) Send(ctx context.Context, message ports.EmailMessage) error {
	empresaID, err := strconv.Atoi(c.empresaID)
	if c.endpoint == "" || c.apiKey == "" || err != nil || empresaID <= 0 {
		return errors.New("Factra email endpoint is not configured")
	}
	body, err := json.Marshal(map[string]string{"to": message.To, "subject": message.Subject, "text": message.Text, "html": message.HTML})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Basic "+base64.StdEncoding.EncodeToString([]byte(c.apiKey)))
	if message.IdempotencyKey != "" {
		req.Header.Set("Idempotency-Key", message.IdempotencyKey)
	}
	req.Header.Set("X-Factra-Empresa-Id", c.empresaID)
	resp, err := c.client.Do(req)
	if err != nil {
		return errors.New("Factra email request failed")
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return errors.New("Factra email service returned an unsuccessful status")
	}
	var result struct {
		Respuesta string `json:"respuesta"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return errors.New("Factra email response is invalid")
	}
	if !strings.EqualFold(result.Respuesta, "Enviado") {
		return errors.New("Factra email service did not confirm delivery")
	}
	return nil
}
