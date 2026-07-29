package stores

import (
	"context"
	"fmt"
	"time"

	"cloud.google.com/go/bigquery"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"
	gcpbigquery "ms-vehitrack/infrastructure/gcp/bigquery"
	gcpconfig "ms-vehitrack/infrastructure/gcp/config"
)

var _ ports.TelemetryStorePort = (*BigQueryTelemetryStore)(nil)

type telemetryRow struct {
	DeviceID    string    `bigquery:"device_id"`
	EventTime   time.Time `bigquery:"event_timestamp"`
	Latitude    float64   `bigquery:"latitude"`
	Longitude   float64   `bigquery:"longitude"`
	SpeedGPS    float64   `bigquery:"speed_gps"`
	SpeedOBD    float64   `bigquery:"speed_obd"`
	RPM         float64   `bigquery:"rpm"`
	CoolantTemp float64   `bigquery:"coolant_temp"`
	FuelLevel   float64   `bigquery:"fuel_level"`
	Protocol    string    `bigquery:"protocol"`
	VIN         string    `bigquery:"vin"`
	IngestedAt  time.Time `bigquery:"ingested_at"`
}

// BigQueryTelemetryStore persists telemetry rows in BigQuery.
type BigQueryTelemetryStore struct {
	client *gcpbigquery.Client
	table  string
}

// NewBigQueryTelemetryStore creates a TelemetryStorePort backed by BigQuery.
func NewBigQueryTelemetryStore(ctx context.Context, client *gcpbigquery.Client, cfg gcpconfig.Config) (*BigQueryTelemetryStore, error) {
	store := &BigQueryTelemetryStore{
		client: client,
		table:  cfg.BigQueryTable,
	}

	schema := bigquery.Schema{
		{Name: "device_id", Type: bigquery.StringFieldType, Required: true},
		{Name: "event_timestamp", Type: bigquery.TimestampFieldType, Required: true},
		{Name: "latitude", Type: bigquery.FloatFieldType, Required: true},
		{Name: "longitude", Type: bigquery.FloatFieldType, Required: true},
		{Name: "speed_gps", Type: bigquery.FloatFieldType},
		{Name: "speed_obd", Type: bigquery.FloatFieldType},
		{Name: "rpm", Type: bigquery.FloatFieldType},
		{Name: "coolant_temp", Type: bigquery.FloatFieldType},
		{Name: "fuel_level", Type: bigquery.FloatFieldType},
		{Name: "protocol", Type: bigquery.StringFieldType},
		{Name: "vin", Type: bigquery.StringFieldType},
		{Name: "ingested_at", Type: bigquery.TimestampFieldType, Required: true},
	}

	if err := client.EnsureDatasetAndTable(ctx, cfg.BigQueryTable, schema); err != nil {
		return nil, fmt.Errorf("%w: ensure schema: %v", ports.ErrTelemetryStoreFailed, err)
	}

	return store, nil
}

// Save inserts one telemetry event into BigQuery.
func (s *BigQueryTelemetryStore) Save(ctx context.Context, telemetry entities.Telemetry) error {
	row := telemetryRow{
		DeviceID:    telemetry.DeviceID,
		EventTime:   telemetry.Timestamp.UTC(),
		Latitude:    telemetry.Latitude,
		Longitude:   telemetry.Longitude,
		SpeedGPS:    telemetry.SpeedGPS,
		SpeedOBD:    telemetry.SpeedOBD,
		RPM:         telemetry.RPM,
		CoolantTemp: telemetry.CoolantTemp,
		FuelLevel:   telemetry.FuelLevel,
		Protocol:    telemetry.Protocol,
		VIN:         telemetry.VIN,
		IngestedAt:  time.Now().UTC(),
	}

	if err := s.client.InsertRows(ctx, s.table, []*telemetryRow{&row}); err != nil {
		return fmt.Errorf("%w: %v", ports.ErrTelemetryStoreFailed, err)
	}

	return nil
}
