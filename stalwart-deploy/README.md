# EURION Mail Stack — Stalwart Deployment

Self-hosted EU-sovereign email for EURION using **Stalwart Mail Server** v0.15+ with inbound relay via **Mailgun**.

## Architecture

```
Internet → MX (eurion.se) → Mailgun
                                ↓  webhook POST (multipart/form-data)
                        Traefik (api.eurion.se/v1/mail/inbound)
                                ↓  stripPrefix /v1/mail → /inbound
                        mailgun-inbound (Node.js :8025)
                                ↓  SMTP MAIL FROM:<relay@eurion.se>
                        Stalwart (:25) → user INBOX
```

**Outbound** mail uses Mailgun SMTP relay (`smtp.eu.mailgun.org:587`), configured in Stalwart's `config.toml`.

## Components

| Service | Container | Port | Purpose |
|---------|-----------|------|---------|
| Stalwart | `eurion-stalwart` | 25, 143, 465, 587, 993, 4190, 8080 | IMAP/SMTP/webmail server |
| mailgun-inbound | `eurion-mailgun-inbound` | 8025 | Mailgun webhook → SMTP relay |
| certs-dumper | `eurion-certs-dumper` | — | Extracts TLS certs from Traefik for Stalwart |

## Quick Start

### Prerequisites
- Docker + Docker Compose
- Traefik running on `eurion-net` Docker network
- Mailgun account with verified domain (`eurion.se`)
- DNS: MX record pointing to `mxa.eu.mailgun.org` / `mxb.eu.mailgun.org`

### Deploy

```bash
cd /opt/eurion/mail

# Create .env file
cat > .env <<'EOF'
MAILGUN_SIGNING_KEY=           # Leave empty to skip webhook signature verification
MAILGUN_API_KEY=your-api-key   # For storage API fallback (optional on free plan)
STALWART_ADMIN_PASS=your-pass
MAILGUN_SMTP_PASS=your-smtp-password
EOF

# Build and start
docker compose -f mail-compose.yml up -d --build
```

### Post-Deploy: Configure Spam Filter

After Stalwart is running, apply the relay-friendly spam filter config:

```bash
docker exec eurion-stalwart sh < configure-spam-filter.sh
```

This zeroes scores for rules that always trigger on relayed mail (SPF, DMARC, HELO checks).

## Files

| File | Purpose |
|------|---------|
| `mail-compose.yml` | Docker Compose for the full mail stack |
| `mailgun-inbound/server.js` | Webhook receiver — parses multipart, reconstructs MIME, injects via SMTP |
| `mailgun-inbound/Dockerfile` | Container build (Node.js 22 Alpine + busboy) |
| `mailgun-inbound/package.json` | Dependencies (busboy for multipart parsing) |
| `configure-spam-filter.sh` | stalwart-cli commands to tune spam filter for relay traffic |
| `patch_config.py` | Patches Stalwart config.toml (legacy) |
| `patch_stalwart_internal.py` | Patches internal SMTP listener (legacy) |
| `patch_stalwart_relay.py` | Patches outbound relay config (legacy) |

## DNS Records (eurion.se)

| Type | Name | Value |
|------|------|-------|
| MX | `eurion.se` | `mxa.eu.mailgun.org` (priority 10) |
| MX | `eurion.se` | `mxb.eu.mailgun.org` (priority 10) |
| TXT | `eurion.se` | `v=spf1 include:mailgun.org ~all` |
| TXT | `_dmarc.eurion.se` | `v=DMARC1; p=none; rua=mailto:postmaster@eurion.se` |
| CNAME | `email.eurion.se` | `eu.mailgun.org` (Mailgun tracking) |

## Mailgun Configuration

- **Region**: EU (`api.eu.mailgun.org`)
- **Domain**: `eurion.se` (verified, active)
- **Route**: `store(notify="https://api.eurion.se/v1/mail/inbound")`
- **SMTP credentials**: `postmaster@eurion.se` (for outbound relay)

## Stalwart Accounts

Managed via Stalwart admin API at `http://<stalwart-docker-ip>:8080` or webmail at `https://mail.eurion.se`.

> **Note**: Port 8080 on the host may be cAdvisor. Access the Stalwart admin API via Docker internal IP (`docker inspect eurion-stalwart | grep IPAddress`).

## Client Access

| Protocol | Server | Port | Security |
|----------|--------|------|----------|
| IMAP | `mail.eurion.se` | 993 | SSL/TLS |
| SMTP (send) | `mail.eurion.se` | 465 | SSL/TLS |
| SMTP (submit) | `mail.eurion.se` | 587 | STARTTLS |
| Webmail | `https://mail.eurion.se` | 443 | HTTPS |

## Troubleshooting

### Messages going to Junk
Run `configure-spam-filter.sh` — it zeros relay-inherent spam scores.

### Webhook returning 404
Check Traefik routing — the `mailgun-inbound` router needs `priority=100` and `strip-mail-prefix` middleware.

### SMTP injection fails
Verify `STALWART_PORT=25` (not 24 — port 24 requires authentication).

### Check logs
```bash
docker logs eurion-mailgun-inbound --tail 50
docker logs eurion-stalwart --tail 50 | grep -i "message-ingest"
```
