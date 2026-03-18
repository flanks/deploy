# EURION — Complete Installation Guide

> **Audience**: IT administrator with basic Linux experience deploying EURION at a small-to-medium office.
> **Time**: ~2 hours for hardware/OS setup + ~25 minutes automated deployment.
> **Result**: A fully working, EU-sovereign communication platform (chat, video calls, file sharing, search, AI summaries) accessible at `https://your-domain.example`.

---

## Table of Contents

1. [What You're Installing](#1-what-youre-installing)
2. [Hardware Requirements](#2-hardware-requirements)
3. [Network & Domain Prerequisites](#3-network--domain-prerequisites)
4. [Server OS Installation (Ubuntu)](#4-server-os-installation-ubuntu)
5. [Install Docker & Docker Compose](#5-install-docker--docker-compose)
6. [Create the Deploy User](#6-create-the-deploy-user)
7. [Transfer the Source Code to the Server](#7-transfer-the-source-code-to-the-server)
8. [Set Up the Ansible Control Machine](#8-set-up-the-ansible-control-machine)
9. [Configure the Deployment for Your Office](#9-configure-the-deployment-for-your-office)
10. [Run the Automated Deployment](#10-run-the-automated-deployment)
11. [Verify Everything Works](#11-verify-everything-works)
12. [Create the First Admin User](#12-create-the-first-admin-user)
13. [Connect Users (Clients)](#13-connect-users-clients)
14. [Firewall & Port Reference](#14-firewall--port-reference)
15. [Backup & Maintenance](#15-backup--maintenance)
16. [Troubleshooting](#16-troubleshooting)
17. [Updating EURION](#17-updating-eurion)
18. [Security Hardening Checklist](#18-security-hardening-checklist)

---

## 1. What You're Installing

EURION is a self-hosted communication platform (like Microsoft Teams) that keeps all data inside your own infrastructure. It includes:

| Component | What It Does |
|-----------|-------------|
| **API Gateway** | Single entry point for all clients, handles HTTPS |
| **13 Microservices** | Identity/auth, messaging, file sharing, video calls, notifications, admin, search, AI, workflows, previews, transcription |
| **Bridge Service** | Interop with Microsoft 365/Teams |
| **PostgreSQL** | Main database (one database per service, 14 total) |
| **PgBouncer** | Connection pooling for all service database connections |
| **Redis** | Cache and session storage |
| **Kafka + Zookeeper** | Event bus for real-time communication between services |
| **MinIO** | S3-compatible file/object storage (files, avatars, recordings) |
| **Meilisearch** | Fast full-text search engine |
| **Traefik** | Reverse proxy — handles HTTPS certificates automatically |
| **Coturn** | TURN/STUN server for video calls behind firewalls |
| **Prometheus + Grafana + Loki** | Monitoring dashboards and log aggregation |
| **Gotenberg** | PDF/Office document preview engine |
| **Ollama** | Local LLM for AI meeting summaries |

**Total**: ~32 Docker containers, fully automated via Ansible.

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
| A | `traefik` | `203.0.113.50` | 300 |

Replace `203.0.113.50` with your actual public IP.

### 3.4 — Port Forwarding on Your Office Router/Firewall

Log into your office router/firewall and forward these ports from the public IP to the server's internal IP (e.g. `192.168.1.100`):

| Port | Protocol | Purpose |
|------|----------|---------|
| **80** | TCP | HTTP (redirects to HTTPS, needed for Let's Encrypt) |
| **443** | TCP | HTTPS (all web traffic) |
| **3478** | TCP + UDP | TURN server (video calls) |
| **49152–65535** | UDP | Media relay range (video/audio streams) |

> ⚠️ **Do NOT skip port 80** — Let's Encrypt needs it to issue your HTTPS certificate.

### 3.5 — If the Server Is Behind a NAT Gateway (Windows Server, pfSense, etc.)

If your server VM sits behind a Windows Server acting as NAT gateway:
1. Enable RRAS (Routing and Remote Access) on the Windows host
2. Add static port mappings for ports 80, 443, 3478, and the UDP range 49152-65535
3. Point them at the VM's internal IP (e.g. `192.168.1.100`)

---

## 4. Server OS Installation (Ubuntu)

### 4.1 — Install Ubuntu Server 22.04 LTS

1. Download the ISO from https://ubuntu.com/download/server
2. Create a bootable USB (use Rufus or Balena Etcher)
3. Boot the server/VM from the USB
4. During installation:
   - Choose **Ubuntu Server (minimized)** — no desktop needed
   - Set a hostname like `eurion-server`
   - Create a user (e.g. `eurion`) with a strong password
   - Enable **OpenSSH server** when prompted
   - Use the full disk for the filesystem (LVM is fine)
5. After install, note the server's IP address:

```bash
ip addr show
```

Look for the `inet` address on your main network interface (e.g. `192.168.1.100/24`).

### 4.2 — Update the System

SSH into the server from your workstation:

```bash
ssh eurion@192.168.1.100
```

Then run:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git python3 python3-pip nano net-tools
sudo reboot
```

Wait 30 seconds, then SSH back in.

---

## 5. Install Docker & Docker Compose

Run these commands **on the server** (logged in as your `eurion` user):

```bash
# Remove any old Docker versions
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null

# Add Docker's official GPG key and repository
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine + Compose plugin
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Let your user run Docker without sudo
sudo usermod -aG docker $USER

# Apply group change (or log out and back in)
newgrp docker

# Verify
docker --version
docker compose version
```

**Expected output** (versions may be newer):
```
Docker version 27.x.x, build ...
Docker Compose version v2.x.x
```

> ⚠️ If `docker compose version` fails, you have the old v1 — the Ansible playbook requires **Compose v2** (the plugin version).

---

## 6. Create the Deploy User

The Ansible playbook connects to the server via SSH. You can use the user you created during Ubuntu install, or create a dedicated one:

```bash
# On the server
sudo adduser deploy
sudo usermod -aG docker deploy
sudo usermod -aG sudo deploy
```

Make sure this user can run `sudo` without being prompted (optional but recommended for Ansible):

```bash
echo "deploy ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/deploy
```

### 6.1 — Enable Password Authentication (if needed)

Many Ubuntu servers (especially cloud or corporate images) **disable SSH password login** by default. Ansible needs it unless you set up SSH keys.

Still on the server, run:

```bash
# Check current setting
sudo grep -E '^#?PasswordAuthentication' /etc/ssh/sshd_config
```

If it shows `PasswordAuthentication no` (or is commented out and your distro defaults to no), enable it:

```bash
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Ubuntu 22.04+ also has a drop-in override that can block passwords:
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/*.conf 2>/dev/null

# Restart SSH
sudo systemctl restart ssh
```

> 💡 **Planning to use SSH keys instead?** Skip this — go straight to Section 18 (Security Hardening) which covers SSH key setup. You can always disable password auth later after deploying.

### 6.2 — Test from Your Workstation

```bash
ssh deploy@192.168.1.100 "docker --version"
```

If prompted for a password, enter the one you set with `adduser`. If it connects and prints the Docker version, you're good.

---

## 7. Transfer the Source Code and Deployment Configs to the Server

Two things need to be on the server: the **source code** (for building Docker images) and the **deployment configs** (Docker Compose files, scripts).

### 7.1 — Create the Directory Structure

```bash
ssh deploy@192.168.1.100

sudo mkdir -p /opt/eurion/source
sudo chown -R deploy:deploy /opt/eurion
```

### 7.2 — Clone the Deployment Configs

The deployment configs are in a dedicated Git repository. Clone it on the server:

```bash
ssh deploy@192.168.1.100
cd /opt/eurion

git clone https://github.com/flanks/deploy.git _deploy

# Move contents into the right locations
cp -r _deploy/deployment/* /opt/eurion/
cp -r _deploy/ansible /opt/eurion/ansible
cp _deploy/INSTALLATION-GUIDE.md /opt/eurion/
cp _deploy/setup.sh /opt/eurion/
rm -rf _deploy
```

Then initialize the `.env` files from templates:

```bash
cd /opt/eurion
bash setup.sh
```

This creates `.env` files in each stack folder. **You'll fill in real passwords in Step 9.**

> **Alternative** — If git isn't installed on the server, SCP from your workstation:
> ```bash
> scp -r ./deployment/* deploy@192.168.1.100:/opt/eurion/
> ```

### 7.3 — Transfer the Source Code

The EURION application source code (`eu-teams/` monorepo) needs to be at `/opt/eurion/source/` on the server. Choose one method:

**Option A — SCP from your workstation** (recommended):

```bash
# From your workstation (Linux/Mac/WSL)
scp -r ./eu-teams deploy@192.168.1.100:/opt/eurion/source/
```

> **Windows (PowerShell)**:
> ```powershell
> scp -r C:\Users\Administrator\Desktop\Eurion\eu-teams deploy@192.168.1.100:/opt/eurion/source/
> ```

**Option B — Git clone** (recommended if you have the source repo):

```bash
ssh deploy@192.168.1.100
cd /opt/eurion
git clone https://github.com/flanks/source.git source
```

> **Note**: The source repo is private. You may need to configure a GitHub personal access token or SSH key on the server:
> ```bash
> # Using HTTPS with token:
> git clone https://<TOKEN>@github.com/flanks/source.git source
>
> # Or using SSH (after adding key to GitHub):
> git clone git@github.com:flanks/source.git source
> ```

### 7.4 — Verify the File Structure

SSH into the server and check:

```bash
ssh deploy@192.168.1.100

ls /opt/eurion/
# Should show: ansible  coturn  gateway  infrastructure  monitoring  scripts  services  source  storage

ls /opt/eurion/source/package.json
# Should exist — this is the monorepo root

ls /opt/eurion/services/docker-compose.yml
# Should exist — this is the services stack
```

---

## 8. Set Up the Ansible Control Machine

Ansible runs from a "control machine" — this can be your **workstation** (Windows with WSL, macOS, or Linux). It does NOT run on the server.

### 8.1 — Install Ansible

**On Linux / macOS / WSL**:

```bash
pip3 install ansible
```

**On Windows (native PowerShell)**:
Ansible doesn't run natively on Windows. Use one of:
- **WSL** (Windows Subsystem for Linux) — recommended
- A separate Linux VM on your workstation
- Run Ansible directly from the EURION server itself

To install WSL:
```powershell
wsl --install -d Ubuntu-22.04
```
Then open the Ubuntu terminal and run `pip3 install ansible`.

### 8.2 — Install Required Ansible Collections

```bash
ansible-galaxy collection install community.docker community.general
```

### 8.3 — Get the Ansible Playbook

Clone the deployment repo on your control machine:

```bash
git clone https://github.com/flanks/deploy.git ~/eurion-deploy
cd ~/eurion-deploy/ansible
```

If you're running Ansible from **WSL on Windows** and the repo is already cloned on the Windows side:

```bash
# In WSL, the Windows desktop is at:
cd /mnt/c/Users/Administrator/Desktop/eurion-deploy/ansible
```

### 8.4 — Install sshpass (required for password-based SSH)

Ansible needs `sshpass` to send SSH passwords. Install it on your **control machine** (not the server):

```bash
# On Ubuntu / WSL / Debian:
sudo apt install -y sshpass

# On macOS (Homebrew):
brew install hudochenkov/sshpass/sshpass
```

### 8.5 — Test Connectivity

```bash
cd ~/eurion-deploy/ansible

ansible -i inventory/hosts.yml eurion-vm -m ping
```

**Expected output**:
```
eurion-vm | SUCCESS => {
    "ping": "pong"
}
```

If it fails, check:
- Can you SSH manually? `ssh deploy@192.168.1.100`
- Is the IP correct in `inventory/hosts.yml`?
- Is password auth enabled on the server? (see Step 6.1)
- Did `sshpass` install correctly? Run `sshpass -V` to verify

---

## 9. Configure the Deployment for Your Office

You need to edit **two files** before running the playbook. These files tell Ansible where your server is and what credentials to use.

### 9.1 — Edit the Inventory File

Open `ansible/inventory/hosts.yml`:

```yaml
all:
  vars:
    ansible_user: deploy              # ← The SSH username you created in Step 6
    ansible_ssh_pass: YOUR_PASSWORD   # ← That user's password
    ansible_become: true
    ansible_become_method: sudo
    ansible_become_pass: YOUR_PASSWORD  # ← Same password (for sudo)
    ansible_python_interpreter: /usr/bin/python3

  hosts:
    eurion-vm:
      ansible_host: 192.168.1.100    # ← Your server's LAN IP address
```

**Change these values**:
| Field | Change To |
|-------|-----------|
| `ansible_user` | Your SSH username (from Step 6) |
| `ansible_ssh_pass` | That user's password |
| `ansible_become_pass` | Same password |
| `ansible_host` | Your server's actual LAN IP (from `ip addr show`) |

### 9.2 — Edit the Variables File (the important one!)

Open `ansible/group_vars/all.yml`. This file contains **all configuration** for the entire platform.

Here's what you **MUST** change:

```yaml
# ── VM / networking ──────────────────────────────────────────────────────
eurion_source_local: "C:/Users/Administrator/Desktop/Eurion/eu-teams"   # ← Path on YOUR workstation
eurion_source_remote: /opt/eurion/source      # ← Leave as-is (path on server)
eurion_deploy_root: /opt/eurion               # ← Leave as-is
public_ip: "203.0.113.50"                     # ← YOUR office public IP
domain: eurion-office.eu                      # ← YOUR domain name
```

And change **ALL passwords** to unique, strong values:

```yaml
# ── Credentials ──────────────────────────────────────────────────────────
postgres_password: "ChangeMe_Pg_2025!"          # ← Generate a strong password
redis_password: "ChangeMe_Redis_2025!"          # ← Generate a strong password
minio_password: "ChangeMe_Minio_2025!"          # ← Generate a strong password
meilisearch_key: "ChangeMe_Meili_2025!"         # ← Generate a strong password
jwt_secret: "ChangeMe_JWT_2025!LongRandomString" # ← MUST be long (48+ chars)
internal_api_key: "ChangeMe_Internal_2025!"     # ← Generate a strong password
turn_secret: "ChangeMe_Turn_2025!"              # ← Generate a strong password
```

> 💡 **Quick way to generate passwords** (run on Linux/Mac/WSL):
> ```bash
> # Generate a 32-character random password
> openssl rand -base64 32
>
> # Generate a 48-character JWT secret
> openssl rand -base64 48
> ```

> ⚠️ **Write these passwords down** in a secure location (password manager). You'll need the JWT secret if you ever need to debug authentication issues.

### 9.3 — Create the .env File for Services

The services Docker Compose reads passwords from a `.env` file. SSH into the server and create it:

```bash
ssh deploy@192.168.1.100

cat > /opt/eurion/services/.env << 'EOF'
POSTGRES_PASSWORD=ChangeMe_Pg_2025!
REDIS_PASSWORD=ChangeMe_Redis_2025!
JWT_SECRET=ChangeMe_JWT_2025!LongRandomString
MINIO_ROOT_USER=eurion
MINIO_ROOT_PASSWORD=ChangeMe_Minio_2025!
MEILI_MASTER_KEY=ChangeMe_Meili_2025!
TURN_PASSWORD=ChangeMe_Turn_2025!
INTERNAL_SECRET=ChangeMe_Internal_2025!
GRAFANA_PASSWORD=ChangeMe_Grafana_2025!
BRIDGE_TOKEN_ENC_KEY=ChangeMe_Bridge_2025!
BRIDGE_INTERNAL_SECRET=ChangeMe_BridgeInt_2025!
MAILGUN_SMTP_PASS=
SMTP_HOST=smtp.eu.mailgun.org
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_FROM=Eurion <no-reply@mail.eurion-office.eu>
WEB_APP_URL=https://app.eurion-office.eu
API_BASE_URL=https://app.eurion-office.eu/api
EOF

chmod 600 /opt/eurion/services/.env
```

> **Use the exact same passwords** you put in `group_vars/all.yml`.

Create `.env` files for the other stacks too:

```bash
# Infrastructure
cat > /opt/eurion/infrastructure/.env << 'EOF'
POSTGRES_PASSWORD=ChangeMe_Pg_2025!
REDIS_PASSWORD=ChangeMe_Redis_2025!
EOF

# Storage
cat > /opt/eurion/storage/.env << 'EOF'
MINIO_ROOT_USER=eurion
MINIO_ROOT_PASSWORD=ChangeMe_Minio_2025!
MEILI_MASTER_KEY=ChangeMe_Meili_2025!
EOF

# Monitoring
cat > /opt/eurion/monitoring/.env << 'EOF'
GRAFANA_PASSWORD=ChangeMe_Grafana_2025!
EOF

# Set permissions
chmod 600 /opt/eurion/infrastructure/.env
chmod 600 /opt/eurion/storage/.env
chmod 600 /opt/eurion/monitoring/.env
```

### 9.4 — Update the Coturn Configuration

Edit the TURN server config for your network:

```bash
nano /opt/eurion/coturn/turnserver.conf
```

Change these lines to match your setup:

```properties
listening-ip=192.168.1.100              # ← Your server's LAN IP
external-ip=203.0.113.50/192.168.1.100  # ← Public IP / LAN IP
relay-ip=192.168.1.100                  # ← Your server's LAN IP
realm=eurion-office.eu                  # ← Your domain
server-name=turn.eurion-office.eu       # ← turn.YOUR-DOMAIN
user=eurion:ChangeMe_Turn_2025!         # ← Same TURN password as above
# Also update the allowed-peer-ip:
allowed-peer-ip=192.168.1.100           # ← Your server's LAN IP
```

### 9.5 — Update Traefik (Gateway) for Your Domain

The Traefik gateway config references the domain in Docker labels. Edit:

```bash
nano /opt/eurion/gateway/docker-compose.yml
```

Find the line with `admin@eurion.se` and change it:
```yaml
- "--certificatesresolvers.le.acme.email=admin@eurion-office.eu"
```

The service-level Traefik labels in `deployment/services/docker-compose.yml` also reference `eurion.se`. Update these:

```bash
# Quick search-and-replace on the server
cd /opt/eurion/services
sed -i 's/eurion\.se/eurion-office.eu/g' docker-compose.yml

cd /opt/eurion/gateway
sed -i 's/eurion\.se/eurion-office.eu/g' docker-compose.yml
```

Also update the `CORS_ORIGINS` in the services compose file:

```bash
cd /opt/eurion/services
sed -i 's|https://eurion.se|https://eurion-office.eu|g' docker-compose.yml
sed -i 's|https://app.eurion.se|https://app.eurion-office.eu|g' docker-compose.yml
sed -i 's|https://api.eurion.se|https://api.eurion-office.eu|g' docker-compose.yml
```

Update the **identity-service** URLs (calendar invite links, etc.):

```bash
cd /opt/eurion/services
sed -i 's|WEB_APP_URL: https://app.eurion.se|WEB_APP_URL: https://app.eurion-office.eu|g' docker-compose.yml
sed -i 's|API_BASE_URL: https://app.eurion.se/api|API_BASE_URL: https://app.eurion-office.eu/api|g' docker-compose.yml
```

Update the **bridge-service** URLs:

```bash
sed -i 's|WEB_APP_URL: https://eurion.se|WEB_APP_URL: https://eurion-office.eu|g' docker-compose.yml
sed -i 's|WEBHOOK_BASE_URL: https://api.eurion.se|WEBHOOK_BASE_URL: https://api.eurion-office.eu|g' docker-compose.yml
sed -i 's|INTERNAL_DOMAINS: eurion.se,eurion.eu|INTERNAL_DOMAINS: eurion-office.eu|g' docker-compose.yml
```

Update the **monitoring** compose file (Grafana domain):

```bash
cd /opt/eurion/monitoring
sed -i 's/eurion\.se/eurion-office.eu/g' docker-compose.yml
```

Update the **TURN server** URLs in the services compose:

```bash
cd /opt/eurion/services
sed -i 's|turn.eurion.se|turn.eurion-office.eu|g' docker-compose.yml
```

---

## 10. Run the Automated Deployment

Now for the exciting part. Go to your **control machine** (where Ansible is installed):

```bash
cd ~/eurion-deploy/ansible
```

### 10.1 — Run the Full Playbook

```bash
ansible-playbook -i inventory/hosts.yml site.yml
```

**What happens** (in order):

| Phase | Duration | What It Does |
|-------|----------|-------------|
| **Pre-tasks** | ~10s | Checks Ubuntu, Docker, Compose installed; source code exists |
| **1. patch_source** | ~30s | Applies 9 automatic source code fixes for build compatibility |
| **2. build_images** | ~12 min | Builds 15 Docker images in 2 parallel batches |
| **3. deploy_stacks** | ~5 min | Starts all containers in dependency order (7 layers) |
| **4. verify** | ~2 min | Checks DNS, ports, health endpoints, HTTPS |
| **Post-task** | instant | Prints success banner with URLs |

**Total: ~18–25 minutes** depending on internet speed (Docker image pulls) and server CPU.

### 10.2 — Watch the Output

The playbook prints progress for each step. A successful run ends with:

```
╔══════════════════════════════════════════╗
║  EURION is deployed and verified         ║
║  API:   https://api.eurion-office.eu     ║
║  App:   https://app.eurion-office.eu     ║
║  Admin: https://traefik.eurion-office.eu ║
╚══════════════════════════════════════════╝
```

### 10.3 — If Something Fails

Don't panic. The playbook is **idempotent** — you can safely re-run it:

```bash
# Re-run everything
cd ~/eurion-deploy/ansible
ansible-playbook -i inventory/hosts.yml site.yml

# Or just re-run specific parts:
ansible-playbook -i inventory/hosts.yml site.yml --tags build      # rebuild images only
ansible-playbook -i inventory/hosts.yml site.yml --tags deploy     # redeploy only
ansible-playbook -i inventory/hosts.yml site.yml --tags verify     # check health only
```

---

## 11. Verify Everything Works

### 11.1 — Check All Containers Are Running

SSH into the server:

```bash
ssh deploy@192.168.1.100

docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | sort
```

You should see **~32 containers** all showing `Up` and `(healthy)`:

```
NAMES                          STATUS                    PORTS
eurion-admin-service           Up 5 minutes (healthy)
eurion-ai-service              Up 5 minutes (healthy)
eurion-audit-service           Up 5 minutes (healthy)
eurion-bridge-service          Up 5 minutes (healthy)
eurion-cadvisor                Up 8 minutes (healthy)
eurion-coturn                  Up 7 minutes (healthy)
eurion-file-service            Up 5 minutes (healthy)
eurion-gateway                 Up 5 minutes (healthy)    127.0.0.1:3000->3000/tcp
eurion-gotenberg               Up 5 minutes (healthy)
eurion-grafana                 Up 8 minutes (healthy)
eurion-identity-service        Up 5 minutes (healthy)
eurion-kafka                   Up 10 minutes (healthy)
eurion-loki                    Up 8 minutes (healthy)
eurion-meilisearch             Up 9 minutes (healthy)
eurion-messaging-service       Up 5 minutes (healthy)
eurion-minio                   Up 9 minutes (healthy)
eurion-node-exporter           Up 8 minutes (healthy)
eurion-notification-service    Up 5 minutes (healthy)
eurion-ollama                  Up 5 minutes (healthy)
eurion-org-service             Up 5 minutes (healthy)
eurion-pgbouncer               Up 10 minutes (healthy)   127.0.0.1:6432->5432/tcp
eurion-postgres                Up 10 minutes (healthy)
eurion-preview-service         Up 5 minutes (healthy)
eurion-prometheus              Up 8 minutes (healthy)
eurion-redis                   Up 10 minutes (healthy)
eurion-search-service          Up 5 minutes (healthy)
eurion-traefik                 Up 8 minutes             0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
eurion-transcription-service   Up 5 minutes (healthy)
eurion-video-service           Up 5 minutes (healthy)
eurion-workflow-service        Up 5 minutes (healthy)
eurion-zookeeper               Up 10 minutes (healthy)
```

### 11.2 — Test Health Endpoints

From the server:

```bash
# Test the API gateway
curl http://127.0.0.1:3000/health
# Expected: {"status":"ok","service":"eurion-gateway"}

# Test identity service
curl http://127.0.0.1:3001/health
# Expected: {"status":"ok","service":"eurion-identity-service"}

# Quick loop to test ALL services
for port in 3000 3001 3002 3003 3004 3005 3006 3007 3008 3009 3010 3011 3012 3013 3014; do
  echo -n "Port $port: "
  curl -s http://127.0.0.1:$port/health | head -c 80
  echo
done
```

### 11.3 — Test HTTPS From Outside

From any computer on the internet (or your workstation):

```bash
curl https://api.eurion-office.eu/health
# Expected: {"status":"ok","service":"eurion-gateway"}
```

If this works, your DNS + port forwarding + Traefik + Let's Encrypt are all working correctly. 🎉

### 11.4 — Check Monitoring

Open in a browser: `https://app.eurion-office.eu/grafana`
- Username: `admin`
- Password: whatever you set as `GRAFANA_PASSWORD`

You should see Prometheus as a data source. Pre-built dashboards show container metrics, service health, and system resources.

---

## 12. Create the First Admin User

EURION doesn't have a public registration page (for security). Create the first user via the API.

SSH into the server:

```bash
ssh deploy@192.168.1.100
```

Register through the identity service API (bypasses the gateway to avoid any registration restrictions):

```bash
curl -X POST http://127.0.0.1:3001/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@eurion-office.eu",
    "password": "YourSecurePassword123!",
    "displayName": "System Administrator"
  }'
```

> **Expected response**: `{"success":true,"data":{"user":{"id":"...","email":"admin@eurion-office.eu",...},"tokens":{...}}}`

Then promote this user to super-admin in the database:

```bash
docker exec -it eurion-postgres psql -U eurion -d eurion_identity -c \
  "UPDATE users SET role = 'super-admin' WHERE email = 'admin@eurion-office.eu';"
```

Verify:

```bash
docker exec -it eurion-postgres psql -U eurion -d eurion_identity -c \
  "SELECT id, email, display_name, role FROM users;"
```

You can now log in at `https://app.eurion-office.eu` with these credentials.

---

## 13. Deploy the Web Frontend & Connect Users

### 13.1 — Build and Deploy the Web App

The web frontend is a React + Vite SPA served by nginx. Build and deploy it on the server:

```bash
ssh deploy@192.168.1.100
```

First, create the Vite environment config for your domain:

```bash
cat > /opt/eurion/source/frontend/web/.env.production << EOF
VITE_API_URL=/api
VITE_WS_URL=wss://app.eurion-office.eu/api/v1/ws
VITE_APP_NAME=EURION
EOF
```

Build the Docker image:

```bash
cd /opt/eurion/source/frontend/web
docker build -t eurion-frontend:latest .
```

Run the frontend container with Traefik labels:

```bash
docker rm -f eurion-frontend 2>/dev/null

docker run -d \
  --name eurion-frontend \
  --network eurion-net \
  --restart always \
  --label "traefik.enable=true" \
  --label "traefik.http.routers.frontend.rule=Host(\`app.eurion-office.eu\`)" \
  --label "traefik.http.routers.frontend.entrypoints=websecure" \
  --label "traefik.http.routers.frontend.tls.certresolver=le" \
  --label "traefik.http.services.frontend.loadbalancer.server.port=80" \
  eurion-frontend:latest
```

Verify:

```bash
# Check container is running
docker ps | grep eurion-frontend

# Test internally
curl -s http://eurion-frontend:80/ | head -5
```

Then open `https://app.eurion-office.eu` in a browser — you should see the EURION login page.

### 13.2 — Web App

Open a browser and go to:
```
https://app.eurion-office.eu
```

Log in with the admin account you created in Step 12.

### 13.3 — Desktop App (Windows/Mac/Linux)

The Tauri-based desktop app can be built from `frontend/desktop/`. Distribute the installer to users.

### 13.4 — Mobile App (iOS/Android)

The React Native app is in `frontend/mobile/`. Build and distribute via your organization's MDM or side-loading.

---

## 14. Firewall & Port Reference

### External Ports (must be open on the office firewall/router)

| Port | Protocol | Service | Required? |
|------|----------|---------|-----------|
| 80 | TCP | HTTP → HTTPS redirect + Let's Encrypt | **Yes** |
| 443 | TCP | HTTPS — all web traffic | **Yes** |
| 3478 | TCP+UDP | TURN server (video calls) | **Yes** for video |
| 49152–65535 | UDP | Media relay (video/audio streams) | **Yes** for video |

### Internal Ports (only on 127.0.0.1 — NOT exposed to internet)

| Port | Service |
|------|---------|
| 3000 | API Gateway |
| 3001 | Identity Service |
| 3002 | Org Service |
| 3003 | Audit Service |
| 3004 | Messaging Service |
| 3005 | File Service |
| 3006 | Video Service |
| 3007 | Notification Service |
| 3008 | Admin Service |
| 3009 | Search Service |
| 3010 | AI Service |
| 3011 | Workflow Service |
| 3012 | Preview Service |
| 3013 | Transcription Service |
| 3014 | Bridge Service |
| 5432 | PostgreSQL (direct) |
| 6432 | PgBouncer (connection pooling — used by services) |
| 6379 | Redis |
| 9000 | MinIO API |
| 9001 | MinIO Console |
| 9090 | Prometheus |
| 9094 | Kafka (external) |
| 7700 | Meilisearch |
| 3100 | Loki |
| 11434 | Ollama (local LLM) |

> All internal ports bind to `127.0.0.1` only — they are **not** accessible from the network. Only Traefik (ports 80/443) and Coturn (3478 + UDP range) are internet-facing.

### UFW Firewall (on the server)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3478/tcp
sudo ufw allow 3478/udp
sudo ufw allow 49152:65535/udp
sudo ufw enable
sudo ufw status
```

---

## 15. Backup & Maintenance

### 15.1 — Database Backups

Set up a cron job on the server to back up all databases daily:

```bash
ssh deploy@192.168.1.100
```

Create the backup script:

```bash
sudo mkdir -p /opt/eurion/backups

cat > /opt/eurion/backups/backup-databases.sh << 'SCRIPT'
#!/bin/bash
# EURION Daily Database Backup
set -e
BACKUP_DIR="/opt/eurion/backups/$(date +%Y-%m-%d)"
mkdir -p "$BACKUP_DIR"

DATABASES="eurion_identity eurion_org eurion_audit eurion_messaging eurion_file
eurion_video eurion_notification eurion_admin eurion_search eurion_workflow
eurion_preview eurion_ai eurion_transcription eurion_bridge"

for db in $DATABASES; do
  echo "Backing up $db..."
  docker exec eurion-postgres pg_dump -U eurion -Fc "$db" > "$BACKUP_DIR/${db}.dump"
done

# Also backup MinIO data to a tarball
echo "Backing up MinIO..."
docker exec eurion-minio mc alias set local http://localhost:9000 eurion "$MINIO_ROOT_PASSWORD" 2>/dev/null || true
tar -czf "$BACKUP_DIR/minio-data.tar.gz" -C /var/lib/docker/volumes/ eurion_minio_data 2>/dev/null || echo "MinIO volume backup skipped"

# Delete backups older than 30 days
find /opt/eurion/backups -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true

echo "Backup complete: $BACKUP_DIR"
SCRIPT

chmod +x /opt/eurion/backups/backup-databases.sh
```

Schedule it to run daily at 2:00 AM:

```bash
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/eurion/backups/backup-databases.sh >> /var/log/eurion-backup.log 2>&1") | crontab -
```

### 15.2 — Restore a Database

```bash
# Restore a specific database from backup
docker exec -i eurion-postgres pg_restore -U eurion -d eurion_identity --clean < /opt/eurion/backups/2025-01-15/eurion_identity.dump
```

### 15.3 — View Logs

```bash
# Logs for a specific service
docker logs eurion-messaging-service --tail 100 -f

# Logs for infrastructure
docker logs eurion-postgres --tail 50
docker logs eurion-kafka --tail 50

# All service logs at once
docker logs eurion-gateway --tail 20
```

Or use **Grafana → Loki** for a web-based log viewer.

### 15.4 — Disk Space Monitoring

```bash
# Check disk usage
df -h /

# Check Docker disk usage
docker system df

# Clean up unused Docker resources (safe to run periodically)
docker system prune -f
docker image prune -f
```

### 15.5 — System Health Check (Quick Manual)

```bash
# Quick health loop
for port in 3000 3001 3002 3003 3004 3005 3006 3007 3008 3009 3010 3011 3012 3013 3014; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$port/health)
  if [ "$STATUS" = "200" ]; then
    echo "✅ Port $port OK"
  else
    echo "❌ Port $port FAILED (HTTP $STATUS)"
  fi
done
```

### 15.6 — Graceful Shutdown (Before Maintenance / Reboot)

> ⚠️ **IMPORTANT**: Always perform a graceful shutdown before planned VM reboots, Proxmox maintenance, or hypervisor updates. An unclean shutdown can corrupt Prometheus TSDB write-ahead logs, Kafka commit offsets, and PostgreSQL WAL state — requiring manual recovery.

A convenience script is installed at `/opt/eurion/scripts/graceful-shutdown.sh`. It stops all 8 Docker Compose stacks in **reverse dependency order**:

```
1. Frontends        (stateless — safe to stop anytime)
2. Backend services (flush in-flight requests)
3. Monitoring       (Prometheus TSDB head block flush — critical!)
4. Mail server      (Stalwart queue flush)
5. TURN server      (no persistent state)
6. Traefik gateway  (no persistent state)
7. Object storage   (MinIO data flush)
8. Infrastructure   (Postgres WAL, Redis AOF, Kafka offsets — last!)
```

**Usage**:

```bash
ssh deploy@192.168.1.100
/opt/eurion/scripts/graceful-shutdown.sh
# Wait for "All EURION stacks stopped cleanly" message
# Now safe to reboot VM or perform Proxmox maintenance
```

### 15.7 — Graceful Startup (After Maintenance)

All containers have `restart: always`, so they will auto-start when Docker starts after a reboot. However, if you prefer a **controlled startup** in correct dependency order, use:

```bash
ssh deploy@192.168.1.100
/opt/eurion/scripts/graceful-startup.sh
```

This starts stacks in dependency order (infrastructure → gateway → services → monitoring → frontends) with wait times between layers to ensure databases are ready before services connect.

**Verify after startup**:

```bash
# Check all containers are running and healthy
docker ps --format "table {{.Names}}\t{{.Status}}" | sort

# Check Grafana dashboard is populating
# Visit https://grafana.your-domain.example
```

### 15.8 — Recovery: Prometheus "No Data" After Unclean Reboot

If Grafana shows "No data" for all panels after an unclean shutdown (e.g., power loss, forced Proxmox reboot), Prometheus TSDB may have corrupted timestamp state. Symptoms in Prometheus logs:

```
level=warn msg="Error on ingesting samples that are too old or are too far into the future"
level=warn msg="Append failed" err="out of bounds"
```

**Fix** — clear the WAL and head chunks:

```bash
# 1. Stop Prometheus
docker stop eurion-prometheus

# 2. Find the volume path
docker inspect eurion-prometheus --format '{{range .Mounts}}{{if eq .Destination "/prometheus"}}{{.Source}}{{end}}{{end}}'
# Example output: /var/lib/docker/volumes/monitoring_prometheus_data/_data

# 3. Delete corrupted WAL and head chunks
sudo rm -rf /var/lib/docker/volumes/monitoring_prometheus_data/_data/wal
sudo rm -rf /var/lib/docker/volumes/monitoring_prometheus_data/_data/chunks_head

# 4. Restart Prometheus (will rebuild WAL from scratch)
docker start eurion-prometheus

# 5. Verify — after ~30 seconds, data should flow again
docker logs eurion-prometheus --tail 5
# Should see: "Server is ready to receive web requests."
```

> **Note**: This clears recent in-memory data (last ~2 hours not yet compacted into blocks). Historical data in TSDB blocks is preserved.

---

## 16. Troubleshooting

### Problem: A service won't start / keeps restarting

```bash
# Check what's wrong
docker logs eurion-<service-name> --tail 50

# Common causes:
# 1. Database not ready → wait 30s and it usually self-heals (restart: always)
# 2. Wrong password in .env → compare .env file with group_vars/all.yml
# 3. Port conflict → check with: sudo netstat -tlnp | grep <port>
```

### Problem: "Connection refused" on health check

```bash
# Check if the container is running
docker ps -a | grep eurion-<service>

# If STATUS shows "Exited" or "Restarting":
docker logs eurion-<service> --tail 100

# Manually restart it:
cd /opt/eurion/services
docker compose restart <service-name>
```

### Problem: Let's Encrypt certificate not working

```bash
# Check Traefik logs for ACME errors
docker logs eurion-traefik --tail 50 | grep -i "acme\|cert\|error"

# Common causes:
# 1. Port 80 not forwarded → test: curl http://your-public-ip from outside
# 2. DNS not pointing to your IP → test: dig api.eurion-office.eu
# 3. Rate limited → Let's Encrypt has rate limits. Wait 1 hour.
```

### Problem: Video calls don't connect

```bash
# Check Coturn is running
docker logs eurion-coturn --tail 20

# Test TURN port from outside
# (from another machine):
nc -zuv 203.0.113.50 3478

# Check UDP port range is forwarded
# This is the most common issue — the UDP range 49152-65535 must be forwarded

# Verify Coturn config
cat /opt/eurion/coturn/turnserver.conf | grep external-ip
# Should show: external-ip=YOUR_PUBLIC_IP/YOUR_LAN_IP
```

### Problem: Kafka is unhealthy

```bash
# Kafka can be slow to start — give it 2 minutes
docker logs eurion-kafka --tail 50
docker logs eurion-zookeeper --tail 50

# If it's stuck, restart the infrastructure stack:
cd /opt/eurion/infrastructure
docker compose restart kafka zookeeper
# Wait 60 seconds, then restart services:
cd /opt/eurion/services
docker compose restart
```

### Problem: Database migration failed

```bash
# Run migrations manually for a specific service:
docker run --rm \
  --network eurion-net \
  -e DATABASE_URL="postgresql://eurion:YOUR_PG_PASSWORD@eurion-postgres:5432/eurion_identity" \
  eurion/identity-service:latest \
  node backend/services/identity-service/dist/migrate.js
```

### Problem: Out of disk space

```bash
# Check what's using space
du -sh /var/lib/docker/*
docker system df

# Clean up
docker system prune -af --volumes  # ⚠️ WARNING: removes ALL unused data
# Safer version (keeps volumes):
docker system prune -f
docker image prune -af
```

### Problem: Can't SSH into the server

1. Is the server powered on?
2. Is the SSH service running? (check locally on the server: `sudo systemctl status ssh`)
3. Is port 22 open on the server's firewall? (`sudo ufw status`)
4. Is the IP correct?

---

## 17. Updating EURION

When a new version of EURION is released:

### Step 1 — Update the Source Code

```bash
# On your workstation, get the latest source code
# Then SCP it to the server:
scp -r ./eu-teams deploy@192.168.1.100:/opt/eurion/source/
```

### Step 2 — Re-run the Playbook with Redeploy Tag

```bash
cd ~/eurion-deploy/ansible
ansible-playbook -i inventory/hosts.yml site.yml --tags redeploy
```

This will:
1. **Patch** the new source code (fix any known build issues)
2. **Build** new Docker images
3. **Deploy** the updated containers (rolling restart)
4. **Verify** everything is healthy

**Downtime**: Services restart one by one. Expect ~30 seconds of intermittent unavailability per service. The rolling restart means the platform is never fully down.

### Step 3 — If Only Rebuilding One Service

```bash
# On the server — rebuild just the messaging service
ssh deploy@192.168.1.100
cd /opt/eurion/source
docker build -f backend/services/messaging-service/Dockerfile -t eurion/messaging-service:latest .

# Restart just that service
cd /opt/eurion/services
docker compose up -d messaging-service
```

---

## 18. Security Hardening Checklist

Before going live with real users, complete this checklist:

- [ ] **Change ALL default passwords** in `group_vars/all.yml` and all `.env` files
- [ ] **Encrypt Ansible credentials** with Vault:
  ```bash
  ansible-vault encrypt ansible/group_vars/all.yml
  # Then run playbook with:
  ansible-playbook -i inventory/hosts.yml site.yml --ask-vault-pass
  ```
- [ ] **Enable UFW firewall** (see Section 14)
- [ ] **Disable password SSH**, use SSH keys instead:
  ```bash
  # On your workstation:
  ssh-keygen -t ed25519
  ssh-copy-id deploy@192.168.1.100
  # Then on server, edit /etc/ssh/sshd_config:
  # PasswordAuthentication no
  sudo systemctl restart ssh
  ```
- [ ] **Set up fail2ban** to block brute-force attacks:
  ```bash
  sudo apt install fail2ban
  sudo systemctl enable fail2ban
  ```
- [ ] **Enable automatic security updates**:
  ```bash
  sudo apt install unattended-upgrades
  sudo dpkg-reconfigure -plow unattended-upgrades
  ```
- [ ] **Set up off-site backups** — copy `/opt/eurion/backups/` to a remote location daily
- [ ] **Review Traefik dashboard access** — change the basic auth password in `gateway/docker-compose.yml`
- [ ] **Test video calls** from outside the office network (to verify TURN is working)
- [ ] **Document everything** — keep a copy of your passwords in a secure vault (e.g. Bitwarden)

---

## Quick Reference Card

| What | URL / Command |
|------|-------------|
| **Web App** | `https://app.eurion-office.eu` |
| **API** | `https://api.eurion-office.eu` |
| **Grafana** | `https://app.eurion-office.eu/grafana` |
| **Traefik Dashboard** | `https://traefik.eurion-office.eu` |
| **SSH to server** | `ssh deploy@192.168.1.100` |
| **View all containers** | `docker ps` |
| **View service logs** | `docker logs eurion-<service> -f` |
| **Restart a service** | `cd /opt/eurion/services && docker compose restart <name>` |
| **Restart everything** | `cd /opt/eurion/services && docker compose down && docker compose up -d` |
| **Rebuild frontend** | `cd /opt/eurion/source/frontend/web && docker build -t eurion-frontend:latest .` then restart container |
| **Graceful shutdown** | `/opt/eurion/scripts/graceful-shutdown.sh` |
| **Graceful startup** | `/opt/eurion/scripts/graceful-startup.sh` |
| **Run health check** | `curl http://127.0.0.1:3000/health` |
| **Full re-deploy** | `cd ~/eurion-deploy/ansible && ansible-playbook -i inventory/hosts.yml site.yml` |
| **Quick re-deploy** | `cd ~/eurion-deploy/ansible && ansible-playbook -i inventory/hosts.yml site.yml --tags redeploy` |
| **Database shell** | `docker exec -it eurion-postgres psql -U eurion -d eurion_identity` |
| **Redis shell** | `docker exec -it eurion-redis redis-cli -a YOUR_REDIS_PASSWORD` |
| **Backup now** | `/opt/eurion/backups/backup-databases.sh` |

---

## Architecture Diagram

```
  Internet
     │
     ▼
┌─────────────┐
│ Office Router│  Ports 80, 443, 3478, 49152-65535
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Ubuntu Server (192.168.1.100)                                       │
│                                                                      │
│  ┌─────────────┐   ┌──────────────────────────────────────────────┐  │
│  │   Traefik    │──▶│              eurion-net (Docker network)     │  │
│  │  :80 / :443  │   │                                              │  │
│  └─────────────┘   │  ┌─────────┐  ┌────────┐  ┌──────────────┐  │  │
│                     │  │ Gateway │  │Identity│  │  Messaging   │  │  │
│  ┌─────────────┐   │  │  :3000  │  │ :3001  │  │    :3004     │  │  │
│  │   Coturn     │   │  └─────────┘  └────────┘  └──────────────┘  │  │
│  │   :3478      │   │  ┌─────────┐  ┌────────┐  ┌──────────────┐  │  │
│  │   UDP range  │   │  │  File   │  │ Video  │  │    Search    │  │  │
│  └─────────────┘   │  │  :3005  │  │ :3006  │  │    :3009     │  │  │
│                     │  └─────────┘  └────────┘  └──────────────┘  │  │
│                     │   ... (15 services total) ...                │  │
│                     │                                              │  │
│                     │  ┌──────────┐ ┌───────┐ ┌─────┐ ┌────────┐ │  │
│                     │  │PostgreSQL│ │ Redis │ │Kafka│ │ MinIO  │ │  │
│                     │  │  :5432   │ │ :6379 │ │:9092│ │ :9000  │ │  │
│                     │  └──────────┘ └───────┘ └─────┘ └────────┘ │  │
│                     │                                              │  │
│                     │  ┌───────────┐ ┌────────┐ ┌──────┐          │  │
│                     │  │Prometheus │ │Grafana │ │ Loki │          │  │
│                     │  │   :9090   │ │ :3000  │ │:3100 │          │  │
│                     │  └───────────┘ └────────┘ └──────┘          │  │
│                     └──────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Need Help?

1. **Check logs first**: `docker logs eurion-<service> --tail 100`
2. **Re-run the playbook**: It's safe to run multiple times
3. **Check the Ansible README**: See `ansible/README.md` for known issues and lessons learned
4. **Monitoring**: Grafana dashboards at `https://app.eurion-office.eu/grafana`

---

*EURION — EU-Sovereign Communication Platform*
*Document version: 4.0 | Last updated: June 2025*
