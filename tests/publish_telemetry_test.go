package tests

import (
	"context"
	"errors"
	"testing"
	"time"

	"ms-vehitrack/application/services"
	"ms-vehitrack/application/usecases"
	"ms-vehitrack/domain/entities"
	"ms-vehitrack/domain/ports"

	"github.com/stretchr/testify/require"
)

type fakeTelemetryPublisher struct {
	err      error
	received []entities.Telemetry
}

func (f *fakeTelemetryPublisher) Publish(_ context.Context, telemetry entities.Telemetry) error {
	f.received = append(f.received, telemetry)
	return f.err
}

func newTelemetryService(publisher ports.TelemetryPublisherPort) services.TelemetryService {
	return services.NewTelemetryService(
		usecases.NewPublishTelemetryUseCase(publisher, nil, 24*time.Hour, 5*time.Minute),
	)
}

func TestTelemetryService_PublishSuccess(t *testing.T) {
	publisher := &fakeTelemetryPublisher{}
	service := newTelemetryService(publisher)

	telemetry := validTelemetry()
	err := service.Publish(context.Background(), telemetry)

	require.NoError(t, err)
	require.Len(t, publisher.received, 1)
	require.Equal(t, telemetry.DeviceID, publisher.received[0].DeviceID)
}

func TestTelemetryService_ValidationError(t *testing.T) {
	publisher := &fakeTelemetryPublisher{}
	service := newTelemetryService(publisher)

	telemetry := validTelemetry()
	telemetry.DeviceID = ""

	err := service.Publish(context.Background(), telemetry)

	require.ErrorIs(t, err, entities.ErrInvalidTelemetryDeviceID)
	require.Empty(t, publisher.received)
}

func TestTelemetryService_PublishError(t *testing.T) {
	publisher := &fakeTelemetryPublisher{err: ports.ErrTelemetryPublishFailed}
	service := newTelemetryService(publisher)

	err := service.Publish(context.Background(), validTelemetry())

	require.Error(t, err)
	require.True(t, errors.Is(err, ports.ErrTelemetryPublishFailed))
}

func TestTelemetryValidate(t *testing.T) {
	require.NoError(t, validTelemetry().Validate())

	invalid := validTelemetry()
	invalid.Latitude = 120
	require.ErrorIs(t, invalid.Validate(), entities.ErrInvalidTelemetryLatitude)

	stale := validTelemetry()
	stale.Timestamp = time.Now().UTC().Add(-48 * time.Hour)
	require.ErrorIs(t, stale.Validate(), entities.ErrStaleTelemetryTimestamp)

	future := validTelemetry()
	future.Timestamp = time.Now().UTC().Add(1 * time.Hour)
	require.ErrorIs(t, future.Validate(), entities.ErrFutureTelemetryTimestamp)
}

func validTelemetry() entities.Telemetry {
	return entities.Telemetry{
		DeviceID:    "logan2021",
		Timestamp:   time.Now().UTC(),
		Latitude:    10.98,
		Longitude:   -74.80,
		SpeedGPS:    82,
		SpeedOBD:    81,
		RPM:         2500,
		CoolantTemp: 91,
		FuelLevel:   44,
		Protocol:    "CAN11",
		VIN:         "VF1XXXXXXXX",
	}
}
