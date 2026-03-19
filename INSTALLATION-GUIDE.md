# EURION — Complete Installation Guide

> **Audience**: IT administrator with basic Linux experience deploying EURION at a small-to-medium office.
> **Time**: ~2 hours for hardware/OS setup + ~5 minutes automated deployment.
> **Result**: A fully working, EU-sovereign communication platform accessible at `https://your-domain.example`.

---

## Table of Contents

1. [What You're Installing](#1-what-youre-installing)
2. [Hardware Requirements](#2-hardware-requirements)
3. [Network & Domain Prerequisites](#3-network--domain-prerequisites)
4. [Server OS Installation (Ubuntu)](#4-server-os-installation-ubuntu)
5. [Quick Deployment (Recommended)](#5-quick-deployment-recommended)
6. [Deployment Modules](#6-deployment-modules)
7. [Manual Deployment](#7-manual-deployment)
8. [Verify Everything Works](#8-verify-everything-works)
9. [Create the First Admin User](#9-create-the-first-admin-user)
10. [Connect Users (Clients)](#10-connect-users-clients)
11. [Firewall & Port Reference](#11-firewall--port-reference)
12. [Backup & Maintenance](#12-backup--maintenance)
13. [Troubleshooting](#13-troubleshooting)
14. [Updating EURION](#14-updating-eurion)
15. [Security Hardening Checklist](#15-security-hardening-checklist)

---

## 1. What You're Installing

EURION is a self-hosted communication platform (like Microsoft Teams) that keeps all data inside your own infrastructure. It includes 14 microservices, a full infrastructure stack, and optional modules you can enable or disable per customer.

### Core (always deployed)

| Component | What It Does |
|-----------|-------------|
| **API Gateway** | Single entry point, HTTPS via Traefik |
| **10 Microservices** | Identity, org, audit, messaging, file, notification, admin, search, workflow, preview |
| **PostgreSQL** | One database per service (10 total) |
| **PgBouncer** | Connection pooling |
| **Redis** | Cache and pub/sub |
| **Kafka** | Event bus (KRaft mode) |
| **MinIO** | S3-compatible object storage |
| **Meilisearch** | Full-text search |
| **Traefik** | Reverse proxy + automatic HTTPS |
| **Gotenberg** | Document preview engine |
| **Frontend** | React web app + admin panel |

### Optional Modules (selected at install time)

| Module | Includes | Default |
|--------|----------|---------|
| `monitoring` | Prometheus, Grafana, Loki, cAdvisor, node-exporter | **on** |
| `video` | Video service + CoTURN (TURN/STUN server) | **on** |
| `mail` | Stalwart SMTP/IMAP mail server | off |
| `ai` | ai-service + Ollama (local LLM for meeting summaries) | off |
| `bridge` | bridge-service (Microsoft Teams interop) | off |

See [Section 6](#6-deployment-modules) for details.

---

## 2. Hardware Requirements

### Minimum (up to ~50 users)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **CPU** | 4 cores | 8 cores |
| **RAM** | 16 GB | 32 GB |
| **Disk** | 100 GB SSD | 500 GB SSD |
| **Network** | 100 Mbps | 1 Gbps |
| **OS** | Ubuntu 22.04 LTS | Ubuntu 22.04/24.04 LTS |

### For larger offices (50–500 users)
- 16+ CPU cores, 64 GB RAM, 1 TB NVMe SSD
- Consider separating PostgreSQL onto its own server

### Virtualization
EURION runs fine inside a VM (VMware, Hyper-V, Proxmox, etc.). The VM just needs to meet the specs above and have a network connection that can be port-forwarded from the internet.

---

## 3. Network & Domain Prerequisites

Before touching the server, you need these ready:

### 3.1 — Buy a Domain Name

You need a domain (e.g. `eurion-office.eu`). Any registrar works (Namecheap, Cloudflare, GoDaddy, etc.).

### 3.2 — Get a Public/Static IP

Your office internet connection needs a **static public IP address**. Call your ISP and ask for one if you don't already have it. Write it down — you'll need it several times.

> **Example**: `203.0.113.50` — replace this with YOUR real public IP everywhere below.

### 3.3 — Create DNS Records

Go to your domain registrar's DNS settings and create these records:

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | `@` (root) | `203.0.113.50` | 300 |
| A | `api` | `203.0.113.50` | 300 |
| A | `app` | `203.0.113.50` | 300 |
| A | `turn` | `203.0.113.50` | 300 |
| A | `admin` | `203.0.113.50` | 300 |

Replace `203.0.113.50` with your actual public IP.

### 3.4 — Port Forwarding on Your Office Router/Firewall

Log into your office router/firewall and forward these ports from the public IP to the server's internal IP (e.g. `192.168.1.100`):

| Port | Protocol | Purpose |
|------|----------|---------|
| **80** | TCP | HTTP (redirects to HTTPS, needed for Let's Encrypt) |
| **443** | TCP | HTTPS (all web traffic) |
| **3478** | TCP + UDP | TURN server (video calls) — only if `video` module is enabled |
| **49152–65535** | UDP | Media relay range (video/audio streams) — only if `video` module is enabled |

> ⚠️ **Do NOT skip port 80** — Let's Encrypt needs it to issue your HTTPS certificate (unless using self-signed certs for LAN testing).

### 3.5 — Test Domain (nip.io for LAN testing)

For internal testing without a real domain or public IP, EURION supports [nip.io](https://nip.io) auto-DNS:
- `192.168.1.14.nip.io` → resolves to `192.168.1.14`
- No DNS setup needed — just use the IP as the domain

---

## 4. Server OS Installation (Ubuntu)

### 4.1 — Install Ubuntu Server 22.04 LTS

1. Download the ISO from https://ubuntu.com/download/server
2. Create a bootable USB (use Rufus or Balena Etcher)
3. Boot the server/VM from the USB
4. During installation:
   - Choose **Ubuntu Server (minimized)** — no desktop needed
   - Set a hostname like `eurion-server`
   - Create a user (e.g. `deploy`) with a strong password
   - Enable **OpenSSH server** when prompted
   - Use the full disk for the filesystem (LVM is fine)
5. After install, note the server's IP address:

```bash
ip addr show
```

### 4.2 — Update the System

SSH into the server from your workstation:

```bash
ssh deploy@192.168.1.100
```

Then run:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git python3 python3-pip nano net-tools
sudo reboot
```

Wait 30 seconds, then SSH back in.

### 4.3 — Enable Password Authentication

Many Ubuntu servers disable SSH password login by default. EURION's deployment needs it (or use SSH keys).

```bash
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/*.conf 2>/dev/null
sudo systemctl restart ssh
```

---

## 5. Quick Deployment (Recommended)

The fastest way to deploy EURION uses the automated `test-deploy.sh` script from the build machine. It handles everything: image building, bundle creation, VM preparation, image loading, and Ansible deployment.

### 5.1 — From the Build Machine

The build machine (your workstation or a dedicated server) runs the deployment. It needs:
- SSH access to the target server
- Docker installed (for building images)
- Ansible installed (`pip3 install ansible-core`)
- The EURION source repos cloned (`flanks/eurion` and `flanks/deploy`)

### 5.2 — Full Install (All Modules)

```bash
cd /opt/eurion/customer-deploy/scripts

# First deployment — builds images and creates bundle
bash test-deploy.sh \
  --target 192.168.1.100 \
  --user deploy \
  --domain client-office.eu \
  --profile medium
```

### 5.3 — Customize Modules

Use `--disable` to exclude modules the customer doesn't need:

```bash
# Customer has Datadog — skip monitoring
bash test-deploy.sh --target 192.168.1.100 --domain client.eu \
  --disable monitoring

# Customer uses Exchange — skip mail
bash test-deploy.sh --target 192.168.1.100 --domain client.eu \
  --disable mail

# Core only — no monitoring, no video, no AI, no bridge
bash test-deploy.sh --target 192.168.1.100 --domain client.eu \
  --disable monitoring,video,ai,bridge

# Enable AI summaries
bash test-deploy.sh --target 192.168.1.100 --domain client.eu \
  --profile medium  # ai is opt-in, will need to enable via config
```

### 5.4 — Re-deploy (Skip Build)

After the first deployment, images are cached. Use `--skip-build` for faster re-deploys:

```bash
bash test-deploy.sh --target 192.168.1.100 --user deploy --domain client.eu \
  --skip-build
```

### 5.5 — All Options

```
Usage: ./test-deploy.sh [OPTIONS]

Options:
  --target, -t <ip>        Target VM IP (required)
  --user, -u <user>        SSH user on target (default: claude)
  --port, -P <port>        SSH port (default: 22)
  --key, -k <path>         SSH private key path
  --profile, -p <name>     Deployment profile: small, medium, large (default: medium)
  --domain, -d <domain>    Domain for the deployment (default: <ip>.nip.io)
  --org <name>             Organization name (default: EurionTest)
  --disable <modules>      Disable modules: monitoring,mail,video,ai,bridge
  --skip-build             Skip Docker image build (re-use existing)
  --skip-transfer          Skip file transfer (already on target)
  --build-only             Only build images, don't deploy
  --prep-only              Only prep the VM (install Docker, etc.)
  --help, -h               Show this help
```

### 5.6 — What the Script Does

| Step | What |
|------|------|
| **Step 1** | Builds Docker images from source (skip with `--skip-build`) |
| **Step 2** | Creates air-gap bundle with only images for enabled modules |
| **Step 3** | Prepares target VM (installs Docker, Docker Compose, Ansible) |
| **Step 4** | Transfers deploy kit + bundle to target |
| **Step 5** | Loads images, generates config, runs Ansible playbook |
| **Step 6** | Verifies all services are healthy |

**Time**: ~5 min on LAN with `--skip-build`, ~20 min first build.

---

## 6. Deployment Modules

EURION is modular. Each optional module can be enabled or disabled at install time.

### Module Reference

#### Monitoring (`monitoring`)
- **Includes**: Prometheus (metrics), Grafana (dashboards), Loki (log aggregation), cAdvisor (container metrics), node-exporter (host metrics)
- **Default**: Enabled
- **Disable when**: Customer uses Datadog, Zabbix, Grafana Cloud, or has their own monitoring
- **Savings**: ~350 MB bundle size, 5 fewer containers

#### Video (`video`)
- **Includes**: video-service (WebRTC media), CoTURN (TURN/STUN for NAT traversal)
- **Default**: Enabled
- **Disable when**: Customer doesn't need in-app video calls (can still use external tools)
- **Savings**: ~120 MB bundle size, 2 fewer containers

#### Mail (`mail`)
- **Includes**: Stalwart SMTP/IMAP mail server
- **Default**: Disabled (opt-in)
- **Enable when**: Customer needs a self-hosted mail server alongside EURION
- **Note**: Stalwart provides SMTP (port 25/465/587) and IMAP (port 143/993)

#### AI (`ai`)
- **Includes**: ai-service + Ollama (local LLM)
- **Default**: Disabled (opt-in)
- **Enable when**: Customer wants AI-powered meeting summaries
- **Note**: Ollama runs entirely on-premise — no data leaves the server

#### Bridge (`bridge`)
- **Includes**: bridge-service (Microsoft Teams/365 interop via Graph API)
- **Default**: Disabled (opt-in)
- **Enable when**: Customer needs to interoperate with Microsoft Teams users

### How Modules Affect the Deployment

| Modules Enabled | Containers | Bundle Size | Deploy Time (LAN) |
|----------------|-----------|-------------|-------------------|
| All | ~26 | ~1.8 GB | ~3.5 min |
| Core + video (no monitoring) | ~19 | ~1.45 GB | ~3 min |
| Core only | ~17 | ~1.3 GB | ~2.5 min |

### Feature Flags in Configuration

The deployment generates a configuration file with feature flags. These are set automatically based on `--disable`:

```yaml
features:
  video: true          # false if --disable video
  ai: false            # true if opted in
  transcription: false
  bridge: false        # true if opted in
  search: true
  monitoring: true     # false if --disable monitoring
  mail: false          # true if opted in
  coturn: true         # tied to video module
```

---

## 7. Manual Deployment

If you prefer to deploy manually (without `test-deploy.sh`), follow these steps.

### 7.1 — Prerequisites on Target

Docker, Docker Compose, and Ansible must be installed. The `--prep-only` flag handles this:

```bash
bash test-deploy.sh --target 192.168.1.100 --user deploy --prep-only
```

### 7.2 — Generate Configuration

```bash
# On the build machine
cd /opt/eurion/customer-deploy
python3 scripts/gen-config.py
# This reads test-config.yml and generates Ansible vars + secrets
```

### 7.3 — Run Ansible Manually

```bash
cd /opt/eurion/deploy
ansible-playbook -i generated/inventory/hosts.yml ansible/site.yml \
  -e "@generated/group_vars/all.yml" \
  -e "@generated/group_vars/secrets.yml"
```

### 7.4 — Ansible Playbook Phases

| Phase | Duration | What It Does |
|-------|----------|-------------|
| **Prerequisites** | ~30s | Creates directories, sets permissions |
| **Configure** | ~10s | Templates Docker Compose files + configs |
| **Deploy Docker** | ~3 min | Starts all containers in dependency order |
| **Verify** | ~30s | Health checks on all services |

The playbook is **idempotent** — safe to re-run.

---

## 8. Verify Everything Works

### 8.1 — Check All Containers

SSH into the server:

```bash
ssh deploy@192.168.1.100
docker ps --format "table {{.Names}}\t{{.Status}}" | sort
```

You should see all containers `Up` and `(healthy)`. The number depends on enabled modules.

### 8.2 — Test Health Endpoints

```bash
# Gateway
curl -s http://127.0.0.1:3000/health
# Expected: {"status":"ok","service":"eurion-gateway"}

# All services
for port in 3000 3001 3002 3003 3004 3005 3007 3008 3009 3011 3012; do
  echo -n "Port $port: "
  curl -s http://127.0.0.1:$port/health | head -c 60
  echo
done
```

### 8.3 — Test HTTPS

From any computer:

```bash
curl https://api.your-domain.eu/health
```

### 8.4 — Check Monitoring (if enabled)

Open in browser: `https://app.your-domain.eu/grafana`
- Username: `admin`
- Password: See `DEPLOY_SUMMARY.md` on the server or the secrets generated during deployment

---

## 9. Create the First Admin User

EURION doesn't have public registration. Create the first user via API:

```bash
ssh deploy@192.168.1.100

curl -X POST http://127.0.0.1:3001/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@your-domain.eu",
    "password": "YourSecurePassword123!",
    "displayName": "System Administrator"
  }'
```

Promote to super-admin:

```bash
docker exec -it eurion-postgres psql -U eurion -d eurion_identity -c \
  "UPDATE users SET role = 'super-admin' WHERE email = 'admin@your-domain.eu';"
```

Log in at `https://app.your-domain.eu`.

---

## 10. Connect Users (Clients)

### Web App
Open `https://app.your-domain.eu` in any browser.

### Desktop App
Distribute the Tauri-based installer (Windows, macOS, Linux).

### Mobile App
Build from `frontend/mobile/` and distribute via MDM or side-loading.

### Admin Panel
`https://admin.your-domain.eu` — manage users, organizations, and settings.

---

## 11. Firewall & Port Reference

### External Ports (open on office firewall)

| Port | Protocol | Service | Required? |
|------|----------|---------|-----------|
| 80 | TCP | HTTP → HTTPS + Let's Encrypt | **Yes** |
| 443 | TCP | HTTPS (all web traffic) | **Yes** |
| 3478 | TCP+UDP | TURN server (video) | If `video` enabled |
| 49152–65535 | UDP | Media relay (video/audio) | If `video` enabled |
| 25, 465, 587 | TCP | SMTP (mail) | If `mail` enabled |
| 143, 993 | TCP | IMAP (mail) | If `mail` enabled |

### Internal Ports (127.0.0.1 only — not exposed)

| Port | Service |
|------|---------|
| 3000 | API Gateway |
| 3001–3014 | Microservices (identity through bridge) |
| 5432 | PostgreSQL |
| 6432 | PgBouncer |
| 6379 | Redis |
| 9000/9001 | MinIO |
| 9090 | Prometheus |
| 9092 | Kafka |
| 7700 | Meilisearch |
| 3100 | Loki |
| 11434 | Ollama |

### UFW Firewall (on the server)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Only if video module is enabled:
sudo ufw allow 3478/tcp
sudo ufw allow 3478/udp
sudo ufw allow 49152:65535/udp

# Only if mail module is enabled:
sudo ufw allow 25/tcp
sudo ufw allow 465/tcp
sudo ufw allow 587/tcp
sudo ufw allow 143/tcp
sudo ufw allow 993/tcp

sudo ufw enable
```

---

## 12. Backup & Maintenance

### 12.1 — Database Backups

Create a daily backup cron job:

```bash
ssh deploy@192.168.1.100
sudo mkdir -p /opt/eurion/backups

cat > /opt/eurion/backups/backup-databases.sh << 'SCRIPT'
#!/bin/bash
set -e
BACKUP_DIR="/opt/eurion/backups/$(date +%Y-%m-%d)"
mkdir -p "$BACKUP_DIR"

for db in $(docker exec eurion-postgres psql -U eurion -t -c "SELECT datname FROM pg_database WHERE datname LIKE 'eurion_%';" | tr -d ' '); do
  echo "Backing up $db..."
  docker exec eurion-postgres pg_dump -U eurion -Fc "$db" > "$BACKUP_DIR/${db}.dump"
done

find /opt/eurion/backups -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true
echo "Backup complete: $BACKUP_DIR"
SCRIPT

chmod +x /opt/eurion/backups/backup-databases.sh

(crontab -l 2>/dev/null; echo "0 2 * * * /opt/eurion/backups/backup-databases.sh >> /var/log/eurion-backup.log 2>&1") | crontab -
```

### 12.2 — Restore a Database

```bash
docker exec -i eurion-postgres pg_restore -U eurion -d eurion_identity --clean \
  < /opt/eurion/backups/2025-01-15/eurion_identity.dump
```

### 12.3 — View Logs

```bash
docker logs eurion-messaging-service --tail 100 -f
```

Or use Grafana → Loki (if monitoring module is enabled).

### 12.4 — Graceful Shutdown/Startup

**Always use graceful shutdown** before VM reboots or hypervisor maintenance. Unclean shutdown can corrupt Prometheus TSDB, Kafka offsets, and PostgreSQL WAL.

```bash
# Shutdown (stops in reverse dependency order)
/opt/eurion/scripts/graceful-shutdown.sh

# After reboot, containers auto-start. Or use:
/opt/eurion/scripts/graceful-startup.sh
```

### 12.5 — Disk Space

```bash
df -h /
docker system df
docker system prune -f  # safe cleanup
```

---

## 13. Troubleshooting

### A service won't start

```bash
docker logs eurion-<service> --tail 50
```

**Common causes**: database not ready (wait 30s), wrong password in `.env`, port conflict.

### Connection refused on health check

```bash
docker ps -a | grep eurion-<service>
docker logs eurion-<service> --tail 100
```

### Let's Encrypt certificate not working

```bash
docker logs eurion-traefik --tail 50 | grep -i "acme\|cert\|error"
```

**Check**: port 80 forwarded? DNS correct? Not rate-limited?

### Video calls don't connect

```bash
docker logs eurion-coturn --tail 20
# Check UDP port range 49152-65535 is forwarded
cat /opt/eurion/compose/coturn.yml | grep external-ip
```

### Kafka unhealthy

Kafka is slow to start. Give it 2 minutes. If stuck:

```bash
cd /opt/eurion/compose
docker compose -f infrastructure.yml restart kafka
sleep 60
docker compose -f services.yml restart
```

### Prometheus "No Data" after unclean reboot

```bash
docker stop eurion-prometheus
VOL=$(docker inspect eurion-prometheus --format '{{range .Mounts}}{{if eq .Destination "/prometheus"}}{{.Source}}{{end}}{{end}}')
sudo rm -rf "$VOL/wal" "$VOL/chunks_head"
docker start eurion-prometheus
```

---

## 14. Updating EURION

### From the Build Machine

```bash
# Pull latest source
cd ~/eurion && git pull origin main

# Wipe + redeploy
ssh claude@SERVER_IP 'docker ps -aq | xargs -r docker stop; docker ps -aq | xargs -r docker rm -f; sudo rm -rf /opt/eurion/data /opt/eurion/compose'

bash test-deploy.sh --target SERVER_IP --user deploy --domain client.eu --skip-build
```

### Rolling Update (Minimal Downtime)

```bash
# On the server
cd /opt/eurion/compose
docker compose -f services.yml pull  # if using pre-built images
docker compose -f services.yml up -d --force-recreate
```

---

## 15. Security Hardening Checklist

- [ ] **Change ALL default passwords** (generated by deployment script — see `DEPLOY_SUMMARY.md`)
- [ ] **Enable UFW firewall** (see Section 11)
- [ ] **Switch to SSH keys**:
  ```bash
  ssh-keygen -t ed25519
  ssh-copy-id deploy@SERVER_IP
  # Then disable password auth on server:
  sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sudo systemctl restart ssh
  ```
- [ ] **Install fail2ban**: `sudo apt install fail2ban`
- [ ] **Enable unattended-upgrades**: `sudo apt install unattended-upgrades`
- [ ] **Set up off-site backups** — copy `/opt/eurion/backups/` to remote storage daily
- [ ] **Review Traefik dashboard** — change basic auth in `gateway/docker-compose.yml`
- [ ] **Test video calls** from outside office network (verify TURN works)
- [ ] **Store passwords in a vault** (Bitwarden, KeePass, etc.)

---

## Quick Reference

| What | Command / URL |
|------|-------------|
| Web App | `https://app.your-domain.eu` |
| API | `https://api.your-domain.eu` |
| Admin | `https://admin.your-domain.eu` |
| Grafana | `https://app.your-domain.eu/grafana` |
| SSH | `ssh deploy@SERVER_IP` |
| Containers | `docker ps --format "table {{.Names}}\t{{.Status}}"` |
| Logs | `docker logs eurion-<service> -f` |
| Health | `curl http://127.0.0.1:3000/health` |
| Deploy | `bash test-deploy.sh --target SERVER_IP --domain client.eu` |
| Re-deploy | `bash test-deploy.sh --target SERVER_IP --domain client.eu --skip-build` |
| DB shell | `docker exec -it eurion-postgres psql -U eurion -d eurion_identity` |
| Backup | `/opt/eurion/backups/backup-databases.sh` |
| Graceful shutdown | `/opt/eurion/scripts/graceful-shutdown.sh` |

---

*EURION — EU-Sovereign Communication Platform*
*Document version: 4.1 | Last updated: March 2026*
