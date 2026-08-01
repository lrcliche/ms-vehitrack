-- Copiloto F3: tráfico colaborativo (aplicar manualmente; no auto-migrate al boot).
-- psql "$POSTGRES_DSN" -f migrations/001_traffic.sql

CREATE TABLE IF NOT EXISTS traffic_batches (
    batch_id      TEXT PRIMARY KEY,
    accepted_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    sample_count  INT NOT NULL DEFAULT 0,
    duplicate     BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS traffic_samples (
    id            BIGSERIAL PRIMARY KEY,
    batch_id      TEXT NOT NULL REFERENCES traffic_batches(batch_id) ON DELETE CASCADE,
    cell          TEXT NOT NULL,
    speed_kmh     DOUBLE PRECISION NOT NULL,
    sampled_at    TIMESTAMPTZ NOT NULL,
    accuracy_m    DOUBLE PRECISION,
    session_id    TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_traffic_samples_cell_at
    ON traffic_samples (cell, sampled_at DESC);

CREATE INDEX IF NOT EXISTS idx_traffic_samples_session
    ON traffic_samples (session_id);

-- Agregados por celda + franja de 30 min (slot = hour*2 + (minute>=30)).
-- corridor = prefijo geohash p=5 (misma grilla, corredor más amplio).
CREATE TABLE IF NOT EXISTS traffic_aggregates (
    cell              TEXT NOT NULL,
    slot              INT NOT NULL,
    corridor          TEXT NOT NULL,
    median_speed_kmh  DOUBLE PRECISION NOT NULL,
    sample_count      INT NOT NULL,
    device_count      INT NOT NULL,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (cell, slot, corridor)
);

CREATE INDEX IF NOT EXISTS idx_traffic_agg_corridor_slot
    ON traffic_aggregates (corridor, slot);
