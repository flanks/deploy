#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                    EURION — Customer Deployment Installer                   ║
# ║                                                                            ║
# ║  Interactive installer that prepares Ansible configuration for deploying   ║
# ║  the Eurion platform on customer infrastructure.                           ║
# ║                                                                            ║
# ║  Deployment Modes:                                                         ║
# ║    A) Docker Compose  — Single server, ideal for ≤500 users               ║
# ║    B) Kubernetes      — Multi-node HA, production scale                    ║
# ║    C) Air-Gapped      — Offline install from pre-built bundle              ║
# ║                                                                            ║
# ║  Prerequisites: bash ≥4, ssh access to target, Ansible on control node     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

readonly VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ANSIBLE_DIR="$SCRIPT_DIR/ansible"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
banner() {
    echo ""
    echo -e "${BLUE}${BOLD}"
    cat << 'EOF'
    ███████╗██╗   ██╗██████╗ ██╗ ██████╗ ███╗   ██╗
    ██╔════╝██║   ██║██╔══██╗██║██╔═══██╗████╗  ██║
    █████╗  ██║   ██║██████╔╝██║██║   ██║██╔██╗ ██║
    ██╔══╝  ██║   ██║██╔══██╗██║██║   ██║██║╚██╗██║
    ███████╗╚██████╔╝██║  ██║██║╚██████╔╝██║ ╚████║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝
EOF
    echo -e "${NC}"
    echo -e "${DIM}    EU-Sovereign Communication Platform — Installer v${VERSION}${NC}"
    echo ""
}

info()    { echo -e "${BLUE}ℹ${NC}  $*"; }
success() { echo -e "${GREEN}✓${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}✗${NC}  $*" >&2; }
fatal()   { error "$*"; exit 1; }

ask() {
    local prompt="$1" default="${2:-}" var_name="$3"
    if [ -n "$default" ]; then
        read -rp "$(echo -e "${CYAN}?${NC}  ${prompt} [${default}]: ")" input
        eval "$var_name='${input:-$default}'"
    else
        read -rp "$(echo -e "${CYAN}?${NC}  ${prompt}: ")" input
        eval "$var_name='$input'"
    fi
}

ask_password() {
    local prompt="$1" var_name="$2"
    read -srp "$(echo -e "${CYAN}🔒${NC} ${prompt}: ")" input
    echo ""
    eval "$var_name='$input'"
}

ask_yn() {
    local prompt="$1" default="${2:-y}"
    local yn
    read -rp "$(echo -e "${CYAN}?${NC}  ${prompt} [${default}]: ")" yn
    yn="${yn:-$default}"
    [[ "$yn" =~ ^[Yy] ]]
}

generate_password() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

separator() {
    echo ""
    echo -e "${DIM}──────────────────────────────────────────────────────────────${NC}"
    echo ""
}

# ── Prerequisites Check ──────────────────────────────────────────────────────
check_prerequisites() {
    info "Checking prerequisites..."
    local missing=0

    for cmd in ansible-playbook ansible-vault ssh-keygen openssl; do
        if command -v "$cmd" &>/dev/null; then
            success "$cmd found"
        else
            error "$cmd not found"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        echo ""
        warn "Missing prerequisites. Install them with:"
        echo "  Ubuntu/Debian: sudo apt install ansible openssh-client openssl"
        echo "  RHEL/Fedora:   sudo dnf install ansible openssh-clients openssl"
        echo "  macOS:         brew install ansible openssl"
        echo ""
        fatal "Please install missing tools and retry."
    fi

    success "All prerequisites satisfied"
}

# ── Step 1: Deployment Mode ──────────────────────────────────────────────────
select_deployment_mode() {
    echo -e "${BOLD}Step 1: Select Deployment Mode${NC}"
    echo ""
    echo "  ${BOLD}A)${NC} Docker Compose — Single-Server Deployment"
    echo "     Best for: Small to medium orgs (≤500 users)"
    echo "     Requires: 1 Linux server, 8+ GB RAM, 4+ CPU cores"
    echo "     Includes: All 15 microservices, monitoring, TLS, backups"
    echo ""
    echo "  ${BOLD}B)${NC} Kubernetes — Multi-Node High-Availability"
    echo "     Best for: Large orgs (500–50,000 users)"
    echo "     Requires: K8s cluster (3+ nodes), kubectl, Helm v3"
    echo "     Includes: Horizontal autoscaling, pod disruption budgets, Vault"
    echo ""
    echo "  ${BOLD}C)${NC} Air-Gapped — Offline Deployment"
    echo "     Best for: Classified / restricted networks"
    echo "     Requires: Pre-built image bundle (provided separately)"
    echo "     Includes: Everything from option A, no internet needed"
    echo ""

    local mode
    while true; do
        read -rp "$(echo -e "${CYAN}?${NC}  Select mode [A/B/C]: ")" mode
        mode="${mode^^}"
        case "$mode" in
            A) DEPLOY_MODE="docker"; break ;;
            B) DEPLOY_MODE="kubernetes"; break ;;
            C) DEPLOY_MODE="airgapped"; break ;;
            *) warn "Please enter A, B, or C" ;;
        esac
    done

    success "Selected: $DEPLOY_MODE"
}

# ── Step 2: License Verification ─────────────────────────────────────────────
verify_license() {
    separator
    echo -e "${BOLD}Step 2: License Verification${NC}"
    echo ""

    ask "Eurion license key" "" LICENSE_KEY

    if [ -z "$LICENSE_KEY" ]; then
        fatal "A valid license key is required. Contact sales@eurion.eu"
    fi

    # Format: EURION-XXXX-XXXX-XXXX-XXXX
    if [[ ! "$LICENSE_KEY" =~ ^EURION-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$ ]]; then
        warn "License key format not recognized. Expected: EURION-XXXX-XXXX-XXXX-XXXX"
        if ! ask_yn "Continue anyway?"; then
            fatal "Deployment cancelled"
        fi
    fi

    success "License key recorded"
}

# ── Step 3: Organization Details ─────────────────────────────────────────────
collect_org_details() {
    separator
    echo -e "${BOLD}Step 3: Organization Details${NC}"
    echo ""

    ask "Organization name" "" ORG_NAME
    ask "Primary domain (e.g., agency.gov.eu)" "" DOMAIN
    ask "Admin email" "admin@${DOMAIN}" ADMIN_EMAIL
    ask "Country code (ISO 3166-1 alpha-2)" "SE" COUNTRY_CODE

    # Subdomains
    ask "App subdomain (web frontend)" "app.${DOMAIN}" APP_DOMAIN
    ask "API subdomain (backend gateway)" "api.${DOMAIN}" API_DOMAIN
    ask "Meet subdomain (video calls)" "meet.${DOMAIN}" MEET_DOMAIN
    ask "Admin portal subdomain" "admin.${DOMAIN}" ADMIN_DOMAIN

    success "Organization: ${ORG_NAME} (${DOMAIN})"
}

# ── Step 4: Target Infrastructure ────────────────────────────────────────────
collect_target_info() {
    separator
    echo -e "${BOLD}Step 4: Target Infrastructure${NC}"
    echo ""

    if [ "$DEPLOY_MODE" = "kubernetes" ]; then
        collect_k8s_info
    else
        collect_server_info
    fi
}

collect_server_info() {
    echo "Configure the target Linux server:"
    echo ""

    ask "Server IP / hostname" "" SERVER_HOST
    ask "SSH user" "eurion" SSH_USER
    ask "SSH port" "22" SSH_PORT

    echo ""
    echo "  ${BOLD}1)${NC} SSH key (recommended)"
    echo "  ${BOLD}2)${NC} SSH password"
    local auth_mode
    read -rp "$(echo -e "${CYAN}?${NC}  Authentication method [1]: ")" auth_mode
    auth_mode="${auth_mode:-1}"

    if [ "$auth_mode" = "1" ]; then
        SSH_AUTH="key"
        ask "Path to SSH private key" "~/.ssh/id_ed25519" SSH_KEY_PATH
        SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

        if [ ! -f "$SSH_KEY_PATH" ]; then
            warn "Key not found at $SSH_KEY_PATH"
            if ask_yn "Generate a new ED25519 key pair?"; then
                ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "eurion-deploy@$(hostname)"
                success "Key generated: $SSH_KEY_PATH"
                echo ""
                warn "You must copy the public key to the server:"
                echo "  ssh-copy-id -i ${SSH_KEY_PATH}.pub ${SSH_USER}@${SERVER_HOST}"
                echo ""
                read -rp "Press Enter once the key is deployed..."
            fi
        fi
    else
        SSH_AUTH="password"
        ask_password "SSH password for ${SSH_USER}@${SERVER_HOST}" SSH_PASSWORD
    fi

    # Does the user have sudo?
    if ask_yn "Does ${SSH_USER} have passwordless sudo?" "n"; then
        SUDO_METHOD="passwordless"
    else
        SUDO_METHOD="password"
        if [ "$SSH_AUTH" = "password" ]; then
            if ask_yn "Is the sudo password the same as SSH password?" "y"; then
                SUDO_PASSWORD="$SSH_PASSWORD"
            else
                ask_password "Sudo password" SUDO_PASSWORD
            fi
        else
            ask_password "Sudo password for ${SSH_USER}" SUDO_PASSWORD
        fi
    fi

    # Public IP (for TURN/STUN and Let's Encrypt)
    echo ""
    ask "Public IP of the server (for TURN/STUN and DNS)" "" PUBLIC_IP

    # Optional: is there a NAT gateway?
    if ask_yn "Is the server behind NAT (private IP differs from public IP)?" "n"; then
        ask "Private/internal IP of the server" "$SERVER_HOST" PRIVATE_IP
    else
        PRIVATE_IP="$PUBLIC_IP"
    fi

    success "Target: ${SSH_USER}@${SERVER_HOST}:${SSH_PORT}"
}

collect_k8s_info() {
    echo "Configure the Kubernetes cluster:"
    echo ""

    ask "Kubeconfig path" "~/.kube/config" KUBECONFIG_PATH
    KUBECONFIG_PATH="${KUBECONFIG_PATH/#\~/$HOME}"
    ask "Kubernetes context" "" K8S_CONTEXT
    ask "Target namespace prefix (e.g., eurion)" "eurion" K8S_NAMESPACE_PREFIX

    # External dependencies
    echo ""
    echo "Does the cluster already have these operators/services?"
    ask_yn "Ingress controller (NGINX/Traefik)?" "y" && HAS_INGRESS=true || HAS_INGRESS=false
    ask_yn "cert-manager for TLS?" "y" && HAS_CERT_MANAGER=true || HAS_CERT_MANAGER=false
    ask_yn "External PostgreSQL (managed)?" "n" && HAS_EXTERNAL_PG=true || HAS_EXTERNAL_PG=false
    ask_yn "External Redis (managed)?" "n" && HAS_EXTERNAL_REDIS=true || HAS_EXTERNAL_REDIS=false

    if [ "$HAS_EXTERNAL_PG" = true ]; then
        ask "PostgreSQL host" "" PG_EXTERNAL_HOST
        ask "PostgreSQL port" "5432" PG_EXTERNAL_PORT
        ask "PostgreSQL admin user" "eurion" PG_EXTERNAL_USER
        ask_password "PostgreSQL admin password" PG_EXTERNAL_PASSWORD
    fi

    if [ "$HAS_EXTERNAL_REDIS" = true ]; then
        ask "Redis host" "" REDIS_EXTERNAL_HOST
        ask "Redis port" "6379" REDIS_EXTERNAL_PORT
        ask_password "Redis password" REDIS_EXTERNAL_PASSWORD
    fi

    # TURN/STUN
    echo ""
    ask "Public IP for TURN/STUN server" "" PUBLIC_IP
    PRIVATE_IP="$PUBLIC_IP"

    success "Cluster: ${K8S_CONTEXT} (ns: ${K8S_NAMESPACE_PREFIX})"
}

# ── Step 5: TLS Configuration ────────────────────────────────────────────────
collect_tls_info() {
    separator
    echo -e "${BOLD}Step 5: TLS Certificate Configuration${NC}"
    echo ""

    echo "  ${BOLD}1)${NC} Let's Encrypt (automatic, requires ports 80/443 open)"
    echo "  ${BOLD}2)${NC} Bring your own certificate (PEM files)"
    echo "  ${BOLD}3)${NC} Self-signed (dev/testing only)"
    echo ""

    local tls_mode
    read -rp "$(echo -e "${CYAN}?${NC}  TLS method [1]: ")" tls_mode
    tls_mode="${tls_mode:-1}"

    case "$tls_mode" in
        1)
            TLS_METHOD="letsencrypt"
            ask "ACME email for Let's Encrypt" "$ADMIN_EMAIL" ACME_EMAIL
            success "TLS: Let's Encrypt (ACME email: $ACME_EMAIL)"
            ;;
        2)
            TLS_METHOD="custom"
            ask "Path to TLS certificate (PEM)" "" TLS_CERT_PATH
            ask "Path to TLS private key (PEM)" "" TLS_KEY_PATH
            if [ ! -f "$TLS_CERT_PATH" ] || [ ! -f "$TLS_KEY_PATH" ]; then
                warn "Certificate files not found. They must exist before deployment."
            fi
            success "TLS: Custom certificate"
            ;;
        3)
            TLS_METHOD="selfsigned"
            warn "Self-signed certificates are NOT suitable for production!"
            success "TLS: Self-signed (generated during deploy)"
            ;;
    esac
}

# ── Step 6: Optional Features ────────────────────────────────────────────────
collect_features() {
    separator
    echo -e "${BOLD}Step 6: Optional Features${NC}"
    echo ""
    echo "Enable or disable optional platform features:"
    echo ""

    ask_yn "AI Service (meeting summaries via Ollama — requires 8GB+ RAM)" "y" && FEATURE_AI=true || FEATURE_AI=false
    ask_yn "Video calls & screen sharing (WebRTC via mediasoup)" "y" && FEATURE_VIDEO=true || FEATURE_VIDEO=false
    ask_yn "Transcription Service (call transcriptions via Whisper)" "n" && FEATURE_TRANSCRIPTION=true || FEATURE_TRANSCRIPTION=false
    ask_yn "M365/Teams Bridge (interop with Microsoft Teams)" "n" && FEATURE_BRIDGE=true || FEATURE_BRIDGE=false
    ask_yn "Full-text search (Meilisearch)" "y" && FEATURE_SEARCH=true || FEATURE_SEARCH=false
    ask_yn "Monitoring stack (Prometheus + Grafana + Loki)" "y" && FEATURE_MONITORING=true || FEATURE_MONITORING=false

    if [ "$FEATURE_BRIDGE" = true ]; then
        separator
        echo -e "${BOLD}M365 Bridge Configuration${NC}"
        ask "SMTP host" "smtp.eu.mailgun.org" SMTP_HOST
        ask "SMTP port" "587" SMTP_PORT
        ask "SMTP username" "" SMTP_USER
        ask_password "SMTP password" SMTP_PASS
        ask "SMTP from address" "Eurion <no-reply@mail.${DOMAIN}>" SMTP_FROM
    fi

    echo ""
    success "Features configured"
}

# ── Step 7: Credentials ──────────────────────────────────────────────────────
generate_credentials() {
    separator
    echo -e "${BOLD}Step 7: Security Credentials${NC}"
    echo ""

    if ask_yn "Auto-generate all passwords? (recommended)" "y"; then
        POSTGRES_PASSWORD="$(generate_password)"
        REDIS_PASSWORD="$(generate_password)"
        MINIO_ROOT_USER="eurion-admin"
        MINIO_ROOT_PASSWORD="$(generate_password)"
        MEILI_MASTER_KEY="$(generate_password)"
        JWT_SECRET="$(openssl rand -base64 48)"
        INTERNAL_SECRET="$(generate_password)"
        TURN_PASSWORD="$(generate_password)"
        GRAFANA_PASSWORD="$(generate_password)"
        BRIDGE_TOKEN_ENC_KEY="$(openssl rand -hex 32)"
        BRIDGE_INTERNAL_SECRET="$(generate_password)"
        INITIAL_ADMIN_PASSWORD="$(generate_password)"

        success "All credentials auto-generated"
    else
        ask_password "PostgreSQL password" POSTGRES_PASSWORD
        ask_password "Redis password" REDIS_PASSWORD
        ask "MinIO admin user" "eurion-admin" MINIO_ROOT_USER
        ask_password "MinIO admin password" MINIO_ROOT_PASSWORD
        ask_password "Meilisearch master key" MEILI_MASTER_KEY
        JWT_SECRET="$(openssl rand -base64 48)"
        ask_password "Internal API secret" INTERNAL_SECRET
        ask_password "TURN password" TURN_PASSWORD
        ask_password "Grafana admin password" GRAFANA_PASSWORD
        BRIDGE_TOKEN_ENC_KEY="$(openssl rand -hex 32)"
        BRIDGE_INTERNAL_SECRET="$(generate_password)"
        ask_password "Initial platform admin password" INITIAL_ADMIN_PASSWORD
    fi
}

# ── Step 8: Air-Gapped Bundle ────────────────────────────────────────────────
collect_airgap_info() {
    if [ "$DEPLOY_MODE" != "airgapped" ]; then
        return
    fi

    separator
    echo -e "${BOLD}Step 8: Air-Gapped Image Bundle${NC}"
    echo ""

    ask "Path to Eurion image bundle (.tar.gz)" "" AIRGAP_BUNDLE_PATH
    if [ ! -f "$AIRGAP_BUNDLE_PATH" ]; then
        fatal "Bundle not found at $AIRGAP_BUNDLE_PATH"
    fi

    success "Bundle: $AIRGAP_BUNDLE_PATH"
}

# ── Step 9: Sizing / Resources ───────────────────────────────────────────────
collect_sizing() {
    separator
    echo -e "${BOLD}Step 9: Deployment Sizing${NC}"
    echo ""

    echo "  ${BOLD}S)${NC} Small   — Up to 100 users   (4 CPU / 8GB RAM / 100GB disk)"
    echo "  ${BOLD}M)${NC} Medium  — Up to 500 users   (8 CPU / 16GB RAM / 250GB disk)"
    echo "  ${BOLD}L)${NC} Large   — Up to 2000 users  (16 CPU / 32GB RAM / 500GB disk)"
    echo "  ${BOLD}X)${NC} Custom  — Specify resources manually"
    echo ""

    local size
    read -rp "$(echo -e "${CYAN}?${NC}  Select size [M]: ")" size
    size="${size:-M}"
    size="${size^^}"

    case "$size" in
        S)
            PG_SHARED_BUFFERS="128MB"
            PG_MAX_CONNECTIONS="100"
            REDIS_MAXMEMORY="128mb"
            KAFKA_HEAP="256m"
            ;;
        M)
            PG_SHARED_BUFFERS="256MB"
            PG_MAX_CONNECTIONS="200"
            REDIS_MAXMEMORY="256mb"
            KAFKA_HEAP="512m"
            ;;
        L)
            PG_SHARED_BUFFERS="1GB"
            PG_MAX_CONNECTIONS="500"
            REDIS_MAXMEMORY="512mb"
            KAFKA_HEAP="1g"
            ;;
        X)
            ask "PostgreSQL shared_buffers" "256MB" PG_SHARED_BUFFERS
            ask "PostgreSQL max_connections" "200" PG_MAX_CONNECTIONS
            ask "Redis maxmemory" "256mb" REDIS_MAXMEMORY
            ask "Kafka heap size" "512m" KAFKA_HEAP
            ;;
        *)
            warn "Unknown size, defaulting to Medium"
            PG_SHARED_BUFFERS="256MB"
            PG_MAX_CONNECTIONS="200"
            REDIS_MAXMEMORY="256mb"
            KAFKA_HEAP="512m"
            ;;
    esac

    success "Sizing: $size"
}

# ── Generate Configuration Files ─────────────────────────────────────────────
generate_config() {
    separator
    echo -e "${BOLD}Generating deployment configuration...${NC}"
    echo ""

    local OUT_DIR="$SCRIPT_DIR/generated/${ORG_NAME// /-}"
    mkdir -p "$OUT_DIR"

    # ── Ansible Inventory ─────────────────────────────────────────────────
    generate_inventory "$OUT_DIR"

    # ── Ansible Variables (encrypted) ─────────────────────────────────────
    generate_group_vars "$OUT_DIR"

    # ── Deployment summary ────────────────────────────────────────────────
    generate_summary "$OUT_DIR"

    success "Configuration written to: $OUT_DIR/"
}

generate_inventory() {
    local OUT_DIR="$1"
    mkdir -p "$OUT_DIR/inventory"

    if [ "$DEPLOY_MODE" = "kubernetes" ]; then
        cat > "$OUT_DIR/inventory/hosts.yml" << YAML
---
all:
  children:
    k8s_control:
      hosts:
        localhost:
          ansible_connection: local
          kubeconfig_path: "${KUBECONFIG_PATH}"
          k8s_context: "${K8S_CONTEXT}"
          k8s_namespace_prefix: "${K8S_NAMESPACE_PREFIX}"
YAML
    else
        local ssh_section=""
        if [ "$SSH_AUTH" = "key" ]; then
            ssh_section="          ansible_ssh_private_key_file: ${SSH_KEY_PATH}"
        else
            ssh_section="          ansible_ssh_pass: !vault |
            # Run: ansible-vault encrypt_string '${SSH_PASSWORD}' --name 'ansible_ssh_pass'"
        fi

        local sudo_section=""
        if [ "$SUDO_METHOD" = "password" ]; then
            sudo_section="          ansible_become_pass: !vault |
            # Run: ansible-vault encrypt_string '${SUDO_PASSWORD}' --name 'ansible_become_pass'"
        fi

        cat > "$OUT_DIR/inventory/hosts.yml" << YAML
---
all:
  children:
    eurion_servers:
      hosts:
        eurion-target:
          ansible_host: ${SERVER_HOST}
          ansible_port: ${SSH_PORT}
          ansible_user: ${SSH_USER}
${ssh_section}
${sudo_section}
          ansible_become: true
YAML
    fi

    success "Inventory: $OUT_DIR/inventory/hosts.yml"
}

generate_group_vars() {
    local OUT_DIR="$1"
    mkdir -p "$OUT_DIR/group_vars"

    # Build feature flags for optional services
    local features_yaml=""
    features_yaml+="feature_ai: ${FEATURE_AI}\n"
    features_yaml+="feature_video: ${FEATURE_VIDEO}\n"
    features_yaml+="feature_transcription: ${FEATURE_TRANSCRIPTION}\n"
    features_yaml+="feature_bridge: ${FEATURE_BRIDGE}\n"
    features_yaml+="feature_search: ${FEATURE_SEARCH}\n"
    features_yaml+="feature_monitoring: ${FEATURE_MONITORING}\n"

    # Build SMTP section if bridge enabled
    local smtp_yaml=""
    if [ "$FEATURE_BRIDGE" = true ]; then
        smtp_yaml="smtp_host: \"${SMTP_HOST}\"\nsmtp_port: \"${SMTP_PORT}\"\nsmtp_user: \"${SMTP_USER}\"\nsmtp_pass: \"${SMTP_PASS}\"\nsmtp_from: \"${SMTP_FROM}\""
    fi

    cat > "$OUT_DIR/group_vars/all.yml" << YAML
---
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  EURION Deployment Variables                                             ║
# ║  Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# ║  Organization: ${ORG_NAME}
# ║  Mode: ${DEPLOY_MODE}
# ╚════════════════════════════════════════════════════════════════════════════╝

# ── Deployment Mode ──────────────────────────────────────────────────────────
deploy_mode: "${DEPLOY_MODE}"
eurion_version: "latest"
license_key: "${LICENSE_KEY}"

# ── Organization ─────────────────────────────────────────────────────────────
org_name: "${ORG_NAME}"
domain: "${DOMAIN}"
admin_email: "${ADMIN_EMAIL}"
country_code: "${COUNTRY_CODE}"
app_domain: "${APP_DOMAIN}"
api_domain: "${API_DOMAIN}"
meet_domain: "${MEET_DOMAIN}"
admin_domain: "${ADMIN_DOMAIN}"

# ── Network ──────────────────────────────────────────────────────────────────
public_ip: "${PUBLIC_IP}"
private_ip: "${PRIVATE_IP}"
cors_origins: "https://${APP_DOMAIN},https://${MEET_DOMAIN},https://${ADMIN_DOMAIN}"

# ── TLS ──────────────────────────────────────────────────────────────────────
tls_method: "${TLS_METHOD}"
$([ "$TLS_METHOD" = "letsencrypt" ] && echo "acme_email: \"${ACME_EMAIL}\"")
$([ "$TLS_METHOD" = "custom" ] && echo "tls_cert_path: \"${TLS_CERT_PATH}\"\ntls_key_path: \"${TLS_KEY_PATH}\"")

# ── Feature Flags ────────────────────────────────────────────────────────────
$(echo -e "$features_yaml")

# ── Sizing ───────────────────────────────────────────────────────────────────
pg_shared_buffers: "${PG_SHARED_BUFFERS}"
pg_max_connections: "${PG_MAX_CONNECTIONS}"
redis_maxmemory: "${REDIS_MAXMEMORY}"
kafka_heap_size: "${KAFKA_HEAP}"

# ── Paths ────────────────────────────────────────────────────────────────────
eurion_root: "/opt/eurion"
eurion_data: "/opt/eurion/data"
eurion_logs: "/opt/eurion/logs"
eurion_backups: "/opt/eurion/backups"

# ── Services (all 15) ───────────────────────────────────────────────────────
services:
  - { name: gateway,               port: 3000, db: postgres,             required: true }
  - { name: identity-service,      port: 3001, db: eurion_identity,      required: true }
  - { name: org-service,           port: 3002, db: eurion_org,           required: true }
  - { name: audit-service,         port: 3003, db: eurion_audit,         required: true }
  - { name: messaging-service,     port: 3004, db: eurion_messaging,     required: true }
  - { name: file-service,          port: 3005, db: eurion_file,          required: true }
  - { name: video-service,         port: 3006, db: eurion_video,         required: "{{ feature_video }}" }
  - { name: notification-service,  port: 3007, db: eurion_notification,  required: true }
  - { name: admin-service,         port: 3008, db: eurion_admin,         required: true }
  - { name: search-service,        port: 3009, db: eurion_search,        required: "{{ feature_search }}" }
  - { name: ai-service,            port: 3010, db: eurion_ai,            required: "{{ feature_ai }}" }
  - { name: workflow-service,      port: 3011, db: eurion_workflow,      required: true }
  - { name: preview-service,       port: 3012, db: eurion_preview,       required: true }
  - { name: transcription-service, port: 3013, db: eurion_transcription, required: "{{ feature_transcription }}" }
  - { name: bridge-service,        port: 3014, db: eurion_bridge,        required: "{{ feature_bridge }}" }

$([ -n "$smtp_yaml" ] && echo -e "# ── SMTP (Bridge) ────────────────────────────────────────────────────────\n$smtp_yaml")
YAML

    # ── Secrets file (will be vault-encrypted) ────────────────────────────
    cat > "$OUT_DIR/group_vars/secrets.yml" << YAML
---
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  EURION Secrets — ENCRYPT THIS FILE!                                     ║
# ║  Run: ansible-vault encrypt $OUT_DIR/group_vars/secrets.yml              ║
# ╚════════════════════════════════════════════════════════════════════════════╝

postgres_password: "${POSTGRES_PASSWORD}"
redis_password: "${REDIS_PASSWORD}"
minio_root_user: "${MINIO_ROOT_USER}"
minio_root_password: "${MINIO_ROOT_PASSWORD}"
meili_master_key: "${MEILI_MASTER_KEY}"
jwt_secret: "${JWT_SECRET}"
internal_secret: "${INTERNAL_SECRET}"
turn_password: "${TURN_PASSWORD}"
grafana_password: "${GRAFANA_PASSWORD}"
bridge_token_enc_key: "${BRIDGE_TOKEN_ENC_KEY}"
bridge_internal_secret: "${BRIDGE_INTERNAL_SECRET}"
initial_admin_password: "${INITIAL_ADMIN_PASSWORD}"
YAML

    success "Variables: $OUT_DIR/group_vars/all.yml"
    success "Secrets:   $OUT_DIR/group_vars/secrets.yml"

    echo ""
    warn "CRITICAL: Encrypt secrets before committing!"
    echo "  ansible-vault encrypt $OUT_DIR/group_vars/secrets.yml"
}

generate_summary() {
    local OUT_DIR="$1"

    cat > "$OUT_DIR/DEPLOY_SUMMARY.md" << MD
# Eurion Deployment Summary

| Parameter | Value |
|-----------|-------|
| Organization | ${ORG_NAME} |
| Domain | ${DOMAIN} |
| Mode | ${DEPLOY_MODE} |
| Target | ${SERVER_HOST:-k8s:${K8S_CONTEXT:-}} |
| Public IP | ${PUBLIC_IP} |
| TLS | ${TLS_METHOD} |
| Size | ${PG_MAX_CONNECTIONS} max PG connections |

## Domains

| Service | URL |
|---------|-----|
| Web App | https://${APP_DOMAIN} |
| API Gateway | https://${API_DOMAIN} |
| Video Meet | https://${MEET_DOMAIN} |
| Admin Portal | https://${ADMIN_DOMAIN} |

## Features

| Feature | Enabled |
|---------|---------|
| AI Summaries | ${FEATURE_AI} |
| Video Calls | ${FEATURE_VIDEO} |
| Transcription | ${FEATURE_TRANSCRIPTION} |
| M365 Bridge | ${FEATURE_BRIDGE} |
| Full-Text Search | ${FEATURE_SEARCH} |
| Monitoring | ${FEATURE_MONITORING} |

## Initial Admin Credentials

- **Email**: ${ADMIN_EMAIL}
- **Password**: ${INITIAL_ADMIN_PASSWORD}

> ⚠️ Change this password immediately after first login!

## DNS Records Required

\`\`\`
${APP_DOMAIN}    A    ${PUBLIC_IP}
${API_DOMAIN}    A    ${PUBLIC_IP}
${MEET_DOMAIN}   A    ${PUBLIC_IP}
${ADMIN_DOMAIN}  A    ${PUBLIC_IP}
turn.${DOMAIN}   A    ${PUBLIC_IP}
\`\`\`

## Firewall Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 22 | TCP | SSH (restrict to admin IPs) |
| 80 | TCP | HTTP → HTTPS redirect / ACME |
| 443 | TCP | HTTPS (all web traffic) |
| 3478 | TCP+UDP | TURN/STUN |
| 5349 | TCP | TURN over TLS |
| 49152-65535 | UDP | WebRTC media relay |

## Deploy Command

\`\`\`bash
cd $(realpath "$SCRIPT_DIR")
ansible-playbook -i generated/${ORG_NAME// /-}/inventory/hosts.yml \\
    ansible/site.yml \\
    -e @generated/${ORG_NAME// /-}/group_vars/all.yml \\
    -e @generated/${ORG_NAME// /-}/group_vars/secrets.yml \\
    --ask-vault-pass
\`\`\`
MD

    success "Summary: $OUT_DIR/DEPLOY_SUMMARY.md"
}

# ── Final Confirmation ───────────────────────────────────────────────────────
confirm_and_deploy() {
    separator
    echo -e "${BOLD}Deployment Configuration Complete${NC}"
    echo ""
    echo "  Organization:  ${ORG_NAME}"
    echo "  Domain:        ${DOMAIN}"
    echo "  Mode:          ${DEPLOY_MODE}"
    echo "  Target:        ${SERVER_HOST:-k8s:${K8S_CONTEXT:-}}"
    echo "  TLS:           ${TLS_METHOD}"
    echo "  Features:      AI=${FEATURE_AI} Video=${FEATURE_VIDEO} Bridge=${FEATURE_BRIDGE}"
    echo ""

    local OUT_DIR="$SCRIPT_DIR/generated/${ORG_NAME// /-}"

    if ask_yn "Encrypt secrets with ansible-vault now?" "y"; then
        echo ""
        info "You will be asked to create a vault password."
        info "Store this password securely — you need it for every deploy."
        echo ""
        ansible-vault encrypt "$OUT_DIR/group_vars/secrets.yml"
        success "Secrets encrypted"
    else
        warn "Remember to encrypt secrets before deploying!"
    fi

    separator
    echo -e "${GREEN}${BOLD}Configuration generated successfully!${NC}"
    echo ""
    echo "  Files: $OUT_DIR/"
    echo ""
    echo "  To deploy now:"
    echo ""
    echo -e "    ${CYAN}ansible-playbook -i $OUT_DIR/inventory/hosts.yml \\"
    echo -e "        ansible/site.yml \\"
    echo -e "        -e @$OUT_DIR/group_vars/all.yml \\"
    echo -e "        -e @$OUT_DIR/group_vars/secrets.yml \\"
    echo -e "        --ask-vault-pass${NC}"
    echo ""

    if ask_yn "Run deployment now?"; then
        echo ""
        info "Starting deployment..."
        echo ""
        ansible-playbook \
            -i "$OUT_DIR/inventory/hosts.yml" \
            "$ANSIBLE_DIR/site.yml" \
            -e "@$OUT_DIR/group_vars/all.yml" \
            -e "@$OUT_DIR/group_vars/secrets.yml" \
            --ask-vault-pass \
            -v
    else
        echo ""
        success "Configuration saved. Deploy whenever you're ready."
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    banner
    check_prerequisites

    separator
    select_deployment_mode
    verify_license
    collect_org_details
    collect_target_info
    collect_tls_info
    collect_features
    generate_credentials
    collect_airgap_info
    collect_sizing

    generate_config
    confirm_and_deploy
}

main "$@"
