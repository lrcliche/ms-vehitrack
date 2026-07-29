# Environment deployment guide — ms-vehitrack

Production environment files live on the VPS, outside GitHub:

```text
/etc/factra/env/global.env
/etc/factra/env/ms-vehitrack.env
```

systemd unit template: `deploy/systemd/ms-vehitrack.service`

Layout on VPS:

```text
/srv/ms-vehitrack/
  releases/<RUN_NUMBER>_<SHA>/ms-vehitrack
  current -> /srv/ms-vehitrack/releases/<...>
```

## GitHub Secrets (deploy access only)

- `VPS_HOST`
- `VPS_USER`
- `VPS_PORT`
- `VPS_SSH_KEY`

## GitHub Variables (non-sensitive deploy controls)

- `MS_VEHITRACK_PORT` — required (production port, e.g. `19560`)
- `VERIFY_MS_VEHITRACK_PORT` — optional preflight port
- `MS_VEHITRACK_HEALTH_PATH` — default `/health`
- `MS_VEHITRACK_PUBLIC_HEALTH_URL` — optional public smoke URL

## Service env (`/etc/factra/env/ms-vehitrack.env`)

Managed manually on the VPS. Deploy reads it for preflight and does **not** overwrite it.

Minimum expected keys:

```env
APP_ENV=production
HTTP_PORT=19560
API_KEY=
RATE_LIMIT_RPS=20
RATE_LIMIT_BURST=40
TELEMETRY_MAX_AGE_SECONDS=86400
TELEMETRY_MAX_SKEW_SECONDS=300
POSTGRES_ENABLED=false
GCP_PROJECT_ID=
GCP_PUBSUB_TOPIC=
GCP_CLIENT_TIMEOUT_SECONDS=10
GCP_PUBSUB_PUBLISH_RETRIES=3
GCP_PUBSUB_RETRY_BACKOFF_MS=200
GCP_BIGQUERY_ENABLED=false
GCP_STORAGE_ENABLED=false
GOOGLE_APPLICATION_CREDENTIALS=
```

Shared database URLs and global secrets belong in `global.env` (never modified by CI).

## Install systemd (once, on VPS)

```bash
sudo mkdir -p /srv/ms-vehitrack/releases /var/log/factra /etc/factra/env
sudo cp deploy/systemd/ms-vehitrack.service /etc/systemd/system/ms-vehitrack.service
sudo systemctl daemon-reload
sudo systemctl enable ms-vehitrack
```

Do not commit real `.env` files, service-account JSON, API keys, tokens, or passwords.
