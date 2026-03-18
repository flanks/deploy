#!/bin/bash
# EURION — Graceful Shutdown
# Run this BEFORE server maintenance, VM reboot, or Proxmox operations.
# Stops all Docker stacks in reverse dependency order to ensure clean WAL/data flushes.
set -e

echo '============================================'
echo ' EURION — Graceful Shutdown'
echo ' Stopping all stacks in safe order...'
echo '============================================'

# 1. Frontend apps (no state, safe to stop anytime)
echo '[1/8] Stopping frontend apps...'
if [ -f /opt/eurion/frontend/docker-compose.yml ]; then
    cd /opt/eurion/frontend && docker compose down 2>/dev/null || true
fi
if [ -f /opt/eurion/admin-frontend/docker-compose.yml ]; then
    cd /opt/eurion/admin-frontend && docker compose down 2>/dev/null || true
fi
echo '       ✅ Frontends stopped'

# 2. Backend services (depend on infra)
echo '[2/8] Stopping backend services...'
cd /opt/eurion/services && docker compose down --timeout 30
echo '       ✅ Backend services stopped'

# 3. Monitoring (Prometheus needs clean TSDB flush!)
echo '[3/8] Stopping monitoring (Prometheus, Grafana, Loki)...'
cd /opt/eurion/monitoring && docker compose down --timeout 30
echo '       ✅ Monitoring stopped'

# 4. Mail server
echo '[4/8] Stopping mail server...'
if [ -f /opt/eurion/mail/mail-compose.yml ]; then
    cd /opt/eurion/mail && docker compose -f mail-compose.yml down --timeout 15 2>/dev/null || true
elif [ -f /opt/eurion/mail/docker-compose.yml ]; then
    cd /opt/eurion/mail && docker compose down --timeout 15 2>/dev/null || true
fi
echo '       ✅ Mail stopped'

# 5. TURN server
echo '[5/8] Stopping TURN server...'
cd /opt/eurion/coturn && docker compose down 2>/dev/null || true
echo '       ✅ TURN stopped'

# 6. Reverse proxy
echo '[6/8] Stopping Traefik gateway...'
cd /opt/eurion/gateway && docker compose down 2>/dev/null || true
echo '       ✅ Gateway stopped'

# 7. Storage (MinIO)
echo '[7/8] Stopping object storage...'
cd /opt/eurion/storage && docker compose down --timeout 15 2>/dev/null || true
echo '       ✅ Storage stopped'

# 8. Core infrastructure LAST (Postgres, Redis, Kafka)
echo '[8/8] Stopping infrastructure (Postgres, Redis, Kafka, Meilisearch)...'
cd /opt/eurion/infrastructure && docker compose down --timeout 60
echo '       ✅ Infrastructure stopped'

echo ''
echo '============================================'
echo ' ✅ All EURION stacks stopped cleanly.'
echo ' Safe to reboot or perform maintenance.'
echo '============================================'
