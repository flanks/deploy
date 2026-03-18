#!/bin/bash
# EURION — Graceful Startup
# Starts all Docker stacks in correct dependency order.
# Use after maintenance if you don't want to rely on restart: always.
set -e

echo '============================================'
echo ' EURION — Graceful Startup'
echo ' Starting all stacks in dependency order...'
echo '============================================'

# 1. Core infrastructure FIRST (Postgres, Redis, Kafka)
echo '[1/8] Starting infrastructure (Postgres, Redis, Kafka, Meilisearch)...'
cd /opt/eurion/infrastructure && docker compose up -d
echo '       Waiting 15s for databases to initialize...'
sleep 15
echo '       ✅ Infrastructure started'

# 2. Storage (MinIO)
echo '[2/8] Starting object storage...'
cd /opt/eurion/storage && docker compose up -d 2>/dev/null || true
echo '       ✅ Storage started'

# 3. Reverse proxy
echo '[3/8] Starting Traefik gateway...'
cd /opt/eurion/gateway && docker compose up -d
echo '       ✅ Gateway started'

# 4. Mail server
echo '[4/8] Starting mail server...'
if [ -f /opt/eurion/mail/mail-compose.yml ]; then
    cd /opt/eurion/mail && docker compose -f mail-compose.yml up -d 2>/dev/null || true
elif [ -f /opt/eurion/mail/docker-compose.yml ]; then
    cd /opt/eurion/mail && docker compose up -d 2>/dev/null || true
fi
echo '       ✅ Mail started'

# 5. TURN server
echo '[5/8] Starting TURN server...'
cd /opt/eurion/coturn && docker compose up -d 2>/dev/null || true
echo '       ✅ TURN started'

# 6. Backend services
echo '[6/8] Starting backend services...'
cd /opt/eurion/services && docker compose up -d
echo '       Waiting 10s for services to become healthy...'
sleep 10
echo '       ✅ Backend services started'

# 7. Monitoring
echo '[7/8] Starting monitoring (Prometheus, Grafana, Loki)...'
cd /opt/eurion/monitoring && docker compose up -d
echo '       ✅ Monitoring started'

# 8. Frontend apps
echo '[8/8] Starting frontend apps...'
if [ -f /opt/eurion/frontend/docker-compose.yml ]; then
    cd /opt/eurion/frontend && docker compose up -d
fi
if [ -f /opt/eurion/admin-frontend/docker-compose.yml ]; then
    cd /opt/eurion/admin-frontend && docker compose up -d
fi
echo '       ✅ Frontends started'

echo ''
echo '============================================'
echo ' ✅ All EURION stacks started.'
echo ' Run: docker ps --format "table {{.Names}}\t{{.Status}}" | sort'
echo ' to verify all containers are healthy.'
echo '============================================'
