# EURION — Customer Deployment Guide

## Table of Contents

1. [Overview](#overview)
2. [System Requirements](#system-requirements)
3. [Deployment Modes](#deployment-modes)
4. [Quick Start](#quick-start)
5. [Pre-Deployment Checklist](#pre-deployment-checklist)
6. [Interactive Installer](#interactive-installer)
7. [Manual Configuration](#manual-configuration)
8. [Post-Deployment](#post-deployment)
9. [Day-2 Operations](#day-2-operations)
10. [Troubleshooting](#troubleshooting)
11. [Security Hardening](#security-hardening)
12. [Architecture Reference](#architecture-reference)

---

## Overview

This guide covers deploying the **Eurion** EU-sovereign communication platform to your organization's infrastructure. Eurion replaces Microsoft Teams with GDPR/NIS2/ISO 27001 compliant messaging, video conferencing, file sharing, and workflow automation — all with guaranteed EU data residency.

### What's Included

| Component | Description |
|-----------|-------------|
| 15 Microservices | Gateway, Identity, Org, Audit, Messaging, File, Video, Notification, Admin, Search, AI, Workflow, Preview, Transcription, Bridge |
| Web Frontend | React SPA served via Nginx |
| Infrastructure | PostgreSQL 16, Redis 7, Kafka 3.7, MinIO (S3), Meilisearch |
| Reverse Proxy | Traefik v2.11 with automatic TLS |
| Monitoring | Prometheus, Grafana, Loki, cAdvisor |
| Video (TURN/STUN) | Coturn for NAT traversal |

---

## System Requirements

### Docker Compose (Single Server)

| Size | Users | CPU | RAM | Disk | Network |
|------|-------|-----|-----|------|---------|
| **Small** | ≤100 | 4 cores | 8 GB | 100 GB SSD | 100 Mbps |
| **Medium** | ≤500 | 8 cores | 16 GB | 250 GB SSD | 1 Gbps |
| **Large** | ≤2,000 | 16 cores | 32 GB | 500 GB NVMe | 1 Gbps |

### Kubernetes (Multi-Node)

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Worker nodes | 3 | 5+ |
| CPU per node | 4 cores | 8 cores |
| RAM per node | 16 GB | 32 GB |
| Storage | 200 GB per node | 500 GB NVMe |
| K8s version | 1.28+ | 1.30+ |

### Supported Operating Systems

- Ubuntu 22.04 / 24.04 LTS ✓
- Debian 12 (Bookworm) ✓
- RHEL 9 / Rocky Linux 9 / AlmaLinux 9 ✓

### Network Requirements

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 22 | TCP | Inbound | SSH (admin only) |
| 80 | TCP | Inbound | HTTP → HTTPS redirect |
| 443 | TCP | Inbound | HTTPS (all traffic) |
| 3478 | TCP+UDP | Inbound | TURN/STUN signaling |
| 5349 | TCP | Inbound | TURN over TLS |
| 49152–65535 | UDP | Inbound | WebRTC media relay |

---

## Deployment Modes

### A) Docker Compose — Single Server

Best for small-to-medium organizations (≤500 users). All services run on a single Linux server using Docker Compose. Simple to manage, easy to backup, cost-effective.

### B) Kubernetes — Multi-Node HA

Best for large organizations (500–50,000 users). Services run across multiple nodes with autoscaling, pod disruption budgets, and rolling updates. Requires existing K8s cluster.

### C) Air-Gapped — Offline Install

For classified or restricted networks with no internet access. Uses a pre-built image bundle. All features from Docker Compose mode, zero external connections.

---

## Quick Start

### 1. Clone the deployment repository

```bash
git clone https://deploy.eurion.eu/customer/<your-org>.git eurion-deploy
cd eurion-deploy
```

### 2. Run the interactive installer

```bash
chmod +x install.sh
./install.sh
```

### 3. Follow the prompts

The installer will:
- Ask you to select a deployment mode (Docker/K8s/Air-Gapped)
- Verify your Eurion license key
- Collect organization details and domain configuration
- Configure target server or cluster connection
- Set up TLS (Let's Encrypt, custom cert, or self-signed)
- Enable/disable optional features
- Generate secure credentials
- Create Ansible inventory and variables
- Optionally encrypt secrets with ansible-vault
- Optionally run the deployment immediately

### 4. Deploy

If you didn't deploy during installation:

```bash
ansible-playbook -i generated/<org>/inventory/hosts.yml \
    ansible/site.yml \
    -e @generated/<org>/group_vars/all.yml \
    -e @generated/<org>/group_vars/secrets.yml \
    --ask-vault-pass
```

---

## Pre-Deployment Checklist

- [ ] **License key** — Obtained from Eurion sales team
- [ ] **DNS records** — All subdomains pointing to server IP:
  - `app.<domain>` → Server IP
  - `api.<domain>` → Server IP
  - `meet.<domain>` → Server IP
  - `admin.<domain>` → Server IP
  - `turn.<domain>` → Server IP (optional, for video)
- [ ] **Firewall** — Ports 80, 443, 3478 (TCP+UDP), 5349, 49152-65535/UDP open
- [ ] **Server access** — SSH access with sudo privileges
- [ ] **TLS certificates** — If not using Let's Encrypt
- [ ] **SMTP** — If using M365 Bridge feature (host, port, credentials)

---

## Interactive Installer

The `install.sh` script walks through 9 configuration steps:

| Step | Description |
|------|-------------|
| 1 | Select deployment mode (A/B/C) |
| 2 | License key verification |
| 3 | Organization details & domain setup |
| 4 | Target infrastructure (server SSH / K8s cluster) |
| 5 | TLS certificate configuration |
| 6 | Optional feature toggles |
| 7 | Security credentials (auto-generated or manual) |
| 8 | Air-gapped bundle path (mode C only) |
| 9 | Deployment sizing (S/M/L/Custom) |

Output: `generated/<org-name>/` directory containing:
- `inventory/hosts.yml` — Ansible inventory
- `group_vars/all.yml` — Configuration variables
- `group_vars/secrets.yml` — Encrypted credentials
- `DEPLOY_SUMMARY.md` — Human-readable deployment summary

---

## Manual Configuration

If you prefer to configure without the interactive installer:

### 1. Create inventory

```yaml
# inventory/hosts.yml
all:
  children:
    eurion_servers:
      hosts:
        eurion-prod:
          ansible_host: 10.0.1.50
          ansible_user: eurion
          ansible_ssh_private_key_file: ~/.ssh/eurion_deploy
          ansible_become: true
```

### 2. Create variables

Copy and edit the template:

```bash
cp ansible/roles/configure/templates/vars-example.yml my-vars.yml
# Edit my-vars.yml with your settings
```

### 3. Create secrets

```bash
cat > my-secrets.yml << EOF
postgres_password: "$(openssl rand -base64 32)"
redis_password: "$(openssl rand -base64 32)"
jwt_secret: "$(openssl rand -base64 48)"
# ... (see install.sh for full list)
EOF

ansible-vault encrypt my-secrets.yml
```

### 4. Deploy

```bash
ansible-playbook ansible/site.yml \
    -i inventory/hosts.yml \
    -e @my-vars.yml \
    -e @my-secrets.yml \
    --ask-vault-pass
```

---

## Post-Deployment

### First Login

1. Navigate to `https://app.<your-domain>`
2. Log in with admin credentials from `DEPLOY_SUMMARY.md`
3. **Change the admin password immediately**

### Create Organization

1. Go to Admin Panel → Organizations
2. Create your organization
3. Configure SSO (SAML/OIDC) if needed
4. Invite users

### Configure SSO

Eurion supports:
- SAML 2.0 (ADFS, Okta, Auth0, Keycloak)
- OIDC (Azure AD, Google Workspace, custom)
- eIDAS 2.0 (EU identity)
- FIDO2/WebAuthn (hardware keys)

### Verify Video Calls

1. Start a test call between two users
2. Verify TURN connectivity: `https://api.<domain>/health`
3. Check Coturn logs: `docker logs eurion-coturn`

---

## Day-2 Operations

### Health Check

```bash
ansible-playbook ansible/healthcheck.yml \
    -e @vars.yml -e @secrets.yml --ask-vault-pass
```

### Upgrade

```bash
ansible-playbook ansible/upgrade.yml \
    -e @vars.yml -e @secrets.yml \
    -e eurion_version=1.2.0 \
    --ask-vault-pass
```

### Rollback

```bash
# List available backups
ls /opt/eurion/backups/postgres/

# Rollback to a specific backup
ansible-playbook ansible/rollback.yml \
    -e @vars.yml -e @secrets.yml \
    -e backup_archive=/opt/eurion/backups/postgres/eurion-backup-20240101_020000.tar.gz \
    --ask-vault-pass
```

### Manual Backup

```bash
# SSH to server
/opt/eurion/config/backup.sh
```

### View Logs

```bash
# Service logs
docker logs eurion-gateway --tail 100 -f
docker logs eurion-identity-service --tail 100 -f

# All services
docker compose -f /opt/eurion/compose/services.yml logs --tail 50

# Centralized (if monitoring enabled)
# Grafana → Explore → Loki → {container_name=~"eurion-.*"}
```

### Restart a Service

```bash
docker restart eurion-messaging-service
```

### Scale (Kubernetes only)

```bash
kubectl scale deployment eurion-gateway --replicas=5 -n eurion-gateway
```

---

## Troubleshooting

### Service won't start

```bash
# Check container status
docker ps -a --filter "name=eurion-"

# Check logs
docker logs eurion-<service-name>

# Check database connectivity
docker exec eurion-<service-name> node -e "
  const { Pool } = require('pg');
  const p = new Pool({ connectionString: process.env.DATABASE_URL });
  p.query('SELECT 1').then(() => console.log('DB OK')).catch(e => console.error(e));
"
```

### TLS certificate issues

```bash
# Check Traefik logs
docker logs eurion-traefik --tail 50

# Verify certificate
openssl s_client -connect api.<domain>:443 -servername api.<domain> < /dev/null 2>/dev/null | openssl x509 -noout -dates

# Force Let's Encrypt renewal
docker restart eurion-traefik
```

### Video calls not working

1. Check TURN server: `docker logs eurion-coturn`
2. Verify port 3478 is open: `nc -zvu <server-ip> 3478`
3. Check video service: `curl http://localhost:3006/health`
4. Verify `ANNOUNCED_IP` matches public IP

### Database issues

```bash
# Connect to a specific database
docker exec -it eurion-postgres psql -U eurion -d eurion_identity

# Check connections
docker exec eurion-postgres psql -U eurion -c "SELECT count(*) FROM pg_stat_activity;"

# Vacuum (maintenance)
docker exec eurion-postgres psql -U eurion -d eurion_messaging -c "VACUUM ANALYZE;"
```

### Redis issues

```bash
# Check Redis
docker exec eurion-redis redis-cli -a <password> INFO memory

# Flush cache (non-destructive, sessions will regenerate)
docker exec eurion-redis redis-cli -a <password> FLUSHALL
```

### Kafka issues

```bash
# List topics
docker exec eurion-kafka kafka-topics.sh --bootstrap-server localhost:9092 --list

# Check consumer lag
docker exec eurion-kafka kafka-consumer-groups.sh --bootstrap-server localhost:9092 --all-groups --describe
```

---

## Security Hardening

### Recommended Post-Deployment Steps

1. **Change all default passwords** — Even auto-generated ones should be rotated
2. **Restrict SSH** — Limit to specific IP ranges via UFW/firewalld
3. **Enable 2FA** — Require FIDO2/WebAuthn for admin accounts
4. **Review audit logs** — `https://api.<domain>/v1/audit/events`
5. **Configure retention policies** — Admin Panel → Data Retention
6. **Set up alerting** — Grafana → Alerts for service downtime
7. **Regular updates** — Subscribe to security advisories at security@eurion.eu

### Network Isolation

All internal services (PostgreSQL, Redis, Kafka, etc.) bind to `127.0.0.1` only. They are **never** exposed to the public internet. Only ports 80, 443, 3478, 5349, and 49152-65535/UDP are publicly accessible.

### Encryption

- **In Transit**: TLS 1.2+ on all external connections
- **At Rest**: PostgreSQL encryption, MinIO server-side encryption
- **End-to-End**: Signal protocol (X3DH + Double Ratchet) for messaging
- **Secrets**: ansible-vault encrypted, never stored in plaintext

---

## Architecture Reference

```
┌──────────────────────────────────────────────────────────────┐
│                         Internet                              │
└─────────────────────────┬────────────────────────────────────┘
                          │ HTTPS (443)
                          ▼
              ┌───────────────────────┐
              │    Traefik (Gateway)   │
              │    TLS termination     │
              │    Rate limiting        │
              └──────┬────────┬────────┘
                     │        │
          ┌──────────┘        └──────────┐
          ▼                              ▼
┌─────────────────┐          ┌─────────────────┐
│  Frontend (SPA)  │          │   API Gateway    │
│  React + Nginx   │          │   :3000          │
└─────────────────┘          └────────┬─────────┘
                                      │
           ┌──────────────────────────┼──────────────────┐
           │              │           │          │        │
           ▼              ▼           ▼          ▼        ▼
     ┌──────────┐  ┌──────────┐ ┌─────────┐ ┌──────┐ ┌──────┐
     │ Identity  │  │Messaging │ │  File   │ │Video │ │ ...  │
     │ :3001     │  │ :3004    │ │ :3005   │ │:3006 │ │      │
     └────┬──────┘  └────┬─────┘ └────┬────┘ └──┬───┘ └──┬───┘
          │              │            │          │        │
     ┌────┴──────────────┴────────────┴──────────┴────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Infrastructure Layer                       │
│  ┌──────────┐  ┌───────┐  ┌───────┐  ┌───────┐  ┌────────┐│
│  │PostgreSQL│  │ Redis │  │ Kafka │  │ MinIO │  │Meili-  ││
│  │ :5432    │  │ :6379 │  │ :9092 │  │ :9000 │  │search  ││
│  └──────────┘  └───────┘  └───────┘  └───────┘  │ :7700  ││
│                                                   └────────┘│
└─────────────────────────────────────────────────────────────┘
```

### Service Map

| Service | Port | Database | Description |
|---------|------|----------|-------------|
| gateway | 3000 | — | API routing, JWT verification, rate limiting |
| identity-service | 3001 | eurion_identity | Auth, SSO, FIDO2, user management |
| org-service | 3002 | eurion_org | Organizations, teams, federation |
| audit-service | 3003 | eurion_audit | Immutable compliance audit logs |
| messaging-service | 3004 | eurion_messaging | E2E encrypted chat, rooms, threads |
| file-service | 3005 | eurion_file | File upload/download, virus scan |
| video-service | 3006 | eurion_video | WebRTC video/audio calls |
| notification-service | 3007 | eurion_notification | Push, email, desktop alerts |
| admin-service | 3008 | eurion_admin | Platform administration |
| search-service | 3009 | eurion_search | Full-text search |
| ai-service | 3010 | eurion_ai | Meeting summaries (Ollama) |
| workflow-service | 3011 | eurion_workflow | Approval workflows |
| preview-service | 3012 | eurion_preview | Document previews |
| transcription-service | 3013 | eurion_transcription | Call transcription |
| bridge-service | 3014 | eurion_bridge | M365/Teams interop |

---

## Support

- **Documentation**: https://docs.eurion.eu
- **Security Issues**: security@eurion.eu
- **Support Portal**: https://support.eurion.eu
- **Emergency**: +46-XXX-XXXXXX (24/7 for critical issues)

---

*Eurion — EU-sovereign. Privacy-first. Built for Europe.*
