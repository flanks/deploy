#!/usr/bin/env bash
# EURION — Quick Operations CLI
# Wrapper for common day-2 operations
set -euo pipefail

EURION_ROOT="${EURION_ROOT:-/opt/eurion}"
COMPOSE_DIR="$EURION_ROOT/compose"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
    echo -e "${BOLD}EURION Operations CLI${NC}"
    echo ""
    echo "Usage: eurion-ctl <command>"
    echo ""
    echo "Commands:"
    echo "  status          Show all service health"
    echo "  logs <service>  Tail service logs"
    echo "  restart <svc>   Restart a specific service"
    echo "  restart-all     Restart all application services"
    echo "  backup          Run immediate database backup"
    echo "  restore <file>  Restore from backup archive"
    echo "  update          Pull latest images and restart"
    echo "  ps              List all containers"
    echo "  db <database>   Connect to a database via psql"
    echo "  redis           Connect to Redis CLI"
    echo "  disk            Show disk usage"
    echo "  version         Show running service versions"
    echo ""
}

cmd_status() {
    echo -e "${BOLD}Service Health Status${NC}"
    echo "─────────────────────────────────────────"
    
    local services=(
        "gateway:3000"
        "identity-service:3001"
        "org-service:3002"
        "audit-service:3003"
        "messaging-service:3004"
        "file-service:3005"
        "video-service:3006"
        "notification-service:3007"
        "admin-service:3008"
        "search-service:3009"
        "ai-service:3010"
        "workflow-service:3011"
        "preview-service:3012"
        "transcription-service:3013"
        "bridge-service:3014"
    )

    for entry in "${services[@]}"; do
        local name="${entry%%:*}"
        local port="${entry##*:}"
        
        if curl -sf "http://127.0.0.1:${port}/health" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC}  eurion-${name}  :${port}"
        else
            echo -e "  ${RED}✗${NC}  eurion-${name}  :${port}"
        fi
    done

    echo ""
    echo "Infrastructure:"
    
    docker exec eurion-postgres pg_isready -U eurion &>/dev/null && \
        echo -e "  ${GREEN}✓${NC}  PostgreSQL  :5432" || echo -e "  ${RED}✗${NC}  PostgreSQL  :5432"
    
    docker exec eurion-redis redis-cli ping &>/dev/null && \
        echo -e "  ${GREEN}✓${NC}  Redis       :6379" || echo -e "  ${RED}✗${NC}  Redis       :6379"
    
    docker exec eurion-kafka kafka-topics.sh --bootstrap-server localhost:9092 --list &>/dev/null && \
        echo -e "  ${GREEN}✓${NC}  Kafka       :9092" || echo -e "  ${RED}✗${NC}  Kafka       :9092"
    
    curl -sf "http://127.0.0.1:9000/minio/health/live" &>/dev/null && \
        echo -e "  ${GREEN}✓${NC}  MinIO       :9000" || echo -e "  ${RED}✗${NC}  MinIO       :9000"
}

cmd_logs() {
    local service="${1:-}"
    if [ -z "$service" ]; then
        echo "Usage: eurion-ctl logs <service-name>"
        echo "Example: eurion-ctl logs messaging-service"
        return 1
    fi
    docker logs "eurion-${service}" --tail 100 -f
}

cmd_restart() {
    local service="${1:-}"
    if [ -z "$service" ]; then
        echo "Usage: eurion-ctl restart <service-name>"
        return 1
    fi
    echo "Restarting eurion-${service}..."
    docker restart "eurion-${service}"
    echo "Done."
}

cmd_restart_all() {
    echo "Restarting all application services..."
    docker compose -f "$COMPOSE_DIR/services.yml" --env-file "$COMPOSE_DIR/.env" restart
    echo "Done."
}

cmd_backup() {
    "$EURION_ROOT/config/backup.sh"
}

cmd_restore() {
    local archive="${1:-}"
    if [ -z "$archive" ]; then
        echo "Usage: eurion-ctl restore <backup-file.tar.gz>"
        echo ""
        echo "Available backups:"
        ls -lh "$EURION_ROOT/../backups/postgres"/eurion-backup-*.tar.gz 2>/dev/null || echo "  None found"
        return 1
    fi
    "$EURION_ROOT/config/restore.sh" "$archive"
}

cmd_ps() {
    docker ps --filter "name=eurion-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

cmd_db() {
    local db="${1:-eurion_identity}"
    docker exec -it eurion-postgres psql -U eurion -d "$db"
}

cmd_redis() {
    docker exec -it eurion-redis redis-cli
}

cmd_disk() {
    echo -e "${BOLD}Disk Usage${NC}"
    echo ""
    du -sh "$EURION_ROOT"/* 2>/dev/null | sort -rh
    echo ""
    echo "Docker:"
    docker system df
}

cmd_version() {
    echo -e "${BOLD}Service Versions${NC}"
    docker ps --filter "name=eurion-" --format "{{.Names}}: {{.Image}}" | sort
}

# ── Main ─────────────────────────────────────────────────────────────────────
case "${1:-}" in
    status)     cmd_status ;;
    logs)       cmd_logs "${2:-}" ;;
    restart)    cmd_restart "${2:-}" ;;
    restart-all) cmd_restart_all ;;
    backup)     cmd_backup ;;
    restore)    cmd_restore "${2:-}" ;;
    update)     echo "Use: ansible-playbook upgrade.yml ..." ;;
    ps)         cmd_ps ;;
    db)         cmd_db "${2:-}" ;;
    redis)      cmd_redis ;;
    disk)       cmd_disk ;;
    version)    cmd_version ;;
    *)          usage ;;
esac
