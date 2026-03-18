# EURION Services Deployment Guide

## Prerequisites

1. Infrastructure must be deployed (`/opt/eurion/infrastructure`) — includes PostgreSQL, PgBouncer, Redis, Kafka
2. Storage must be deployed (`/opt/eurion/storage`)
3. Gateway must be deployed (`/opt/eurion/gateway`)
4. Source code available at `/opt/eurion/source/eu-teams`

## Architecture

All 14 backend services connect to PostgreSQL through **PgBouncer** (transaction pooling mode) rather than directly. PgBouncer uses wildcard database routing (`DB_NAME: "*"`) to auto-register databases as services connect.

```
Services → PgBouncer (:5432, transaction pooling) → PostgreSQL (:5432)
```

The only exception is the API Gateway, which connects directly to PostgreSQL for the `postgres` admin database.

## Quick Deployment

```bash
cd /opt/eurion/services

# 1. Configure environment
chmod +x configure-env.sh
./configure-env.sh

# 2. Build images (if source code available)
chmod +x build-images.sh
./build-images.sh

# 3. Deploy services
docker compose up -d

# 4. Check status
docker compose ps
```

## Deployed Services

| Service | Port | Container Name |
|---------|------|----------------|
| API Gateway | 3000 | eurion-gateway |
| Identity | 3001 | eurion-identity-service |
| Organization | 3002 | eurion-org-service |
| Audit | 3003 | eurion-audit-service |
| Messaging | 3004 | eurion-messaging-service |
| File | 3005 | eurion-file-service |
| Video | 3006 | eurion-video-service |
| Notification | 3007 | eurion-notification-service |
| Admin | 3008 | eurion-admin-service |
| Search | 3009 | eurion-search-service |
| AI | 3010 | eurion-ai-service |
| Workflow | 3011 | eurion-workflow-service |
| Preview | 3012 | eurion-preview-service |
| Transcription | 3013 | eurion-transcription-service |
| Bridge | 3014 | eurion-bridge-service |

## Resource Limits

Every container has explicit memory and CPU limits:

| Service | Memory | CPUs | DB Pool (max/min) |
|---------|--------|------|--------------------|
| Gateway | 512m | 1 | N/A |
| Identity | 512m | 1 | 15/3 |
| Messaging | 768m | 1.5 | 20/4 |
| File | 1g | 1 | 10/2 |
| Video | 1g | 2 | 8/2 |
| Org/Audit/Notification/Admin | 384m | 0.5 | 8/2 |
| Search/AI/Workflow | 384-512m | 0.5 | 5/1 |
| Preview/Transcription/Bridge | 384-512m | 0.5 | 5/1 |

## Database Migrations

After deployment, run migrations for each service:

```bash
# Identity Service
docker compose exec identity-service npm run migrate

# Organization Service
docker compose exec org-service npm run migrate

# Audit Service
docker compose exec audit-service npm run migrate

# Messaging Service
docker compose exec messaging-service npm run migrate

# File Service
docker compose exec file-service npm run migrate

# Video Service
docker compose exec video-service npm run migrate

# Notification Service
docker compose exec notification-service npm run migrate

# Admin Service
docker compose exec admin-service npm run migrate
```

## Health Checks

All services expose a `/health` endpoint. Docker healthchecks use `127.0.0.1` (not `localhost`) to avoid IPv6 resolution issues:

```yaml
healthcheck:
  test: ["CMD", "wget", "-qO-", "http://127.0.0.1:PORT/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

```bash
# Check all service health
for port in {3000..3013}; do
  curl -f http://localhost:$port/health && echo " - Port $port: OK" || echo " - Port $port: FAIL"
done

# View service logs
docker compose logs -f [service-name]

# Check service metrics (if exposed)
curl http://localhost:3001/metrics
```

## Configuration

### Environment Variables

All services use these common variables:
- `NODE_ENV`: production
- `JWT_SECRET`: Shared across all services (from `.env`)
- `KAFKA_BROKERS`: kafka:9092
- `REDIS_URL`: redis://:password@redis:6379

Service-specific database connections:
- Each service connects through PgBouncer: `DATABASE_URL=postgresql://eurion:password@eurion-pgbouncer:5432/eurion_<service>`
- Gateway connects directly to Postgres: `DATABASE_URL=postgresql://eurion:password@eurion-postgres:5432/postgres`
- Pool sizes configured per service via `DB_POOL_MAX` and `DB_POOL_MIN` env vars

### External Access

Services are accessed via API Gateway:
```
https://domain.com/api/v1/identity/...
https://domain.com/api/v1/org/...
https://domain.com/api/v1/messaging/...
```

Traefik routes requests based on path prefix.

## Troubleshooting

### Service won't start

```bash
# Check logs
docker compose logs [service-name]

# Check database connection
docker compose exec identity-service sh
# Inside container:
psql $DATABASE_URL -c "SELECT 1"
```

### Database connection issues

Verify passwords in `.env` match infrastructure passwords:
```bash
grep PG_IDENTITY_PASSWORD /opt/eurion/infrastructure/.env
grep PG_IDENTITY_PASSWORD /opt/eurion/services/.env
```

### Kafka connection issues

```bash
# Test Kafka from service
docker compose exec identity-service sh
# Inside container:
npm run kafka-test
```

### Cannot access via Gateway

1. Check Gateway is running: `docker ps | grep gateway`
2. Check Traefik routes: `docker logs eurion-traefik`
3. Verify service health: `curl http://localhost:3001/health`

## Maintenance

### Update Service

```bash
# Pull new image
docker pull eurion/identity-service:latest

# Recreate container
docker compose up -d --force-recreate identity-service
```

### View Resource Usage

```bash
docker stats --filter "name=eurion-"
```

### Backup Data

Databases are backed up as part of infrastructure backups.

Application data in MinIO:
```bash
docker exec eurion-minio mc mirror myminio/eurion-files /backup/files
```

## Scaling

### Current Scalability Features
- **PgBouncer**: Transaction pooling with 500 max client connections, 50 max DB connections
- **Redis Pub/Sub**: WebSocket broadcasts go through Redis, allowing multiple service instances
- **Kafka**: 6 partitions per topic with gzip compression and dead-letter queues
- **Streaming uploads**: File service uses multipart streaming (no memory buffering)
- **Connection pool tuning**: Per-service DB pool sizes matched to workload
- **Resource limits**: All containers have explicit memory and CPU constraints

### Horizontal Scaling

To run multiple instances of a service:

```yaml
# In docker-compose.yml
identity-service:
  deploy:
    replicas: 3
```

Or manually:
```bash
docker compose up -d --scale identity-service=3
```

## Development vs Production

Current configuration is production-ready:
- All services use `NODE_ENV=production`
- JWT secrets are secure
- Connections use internal Docker network
- Health checks enabled
- Logging configured

For development, see `/opt/eurion/source/eu-teams/README.md`
