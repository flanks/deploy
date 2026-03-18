#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  EURION — Air-Gap Image Bundle Builder                                   ║
# ║                                                                          ║
# ║  Creates a self-contained .tar.gz containing all Docker images needed    ║
# ║  for an offline Eurion deployment.                                       ║
# ║                                                                          ║
# ║  Usage: ./build-airgap-bundle.sh [version]                              ║
# ║  Output: eurion-bundle-<version>-<date>.tar.gz                          ║
# ╚════════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

VERSION="${1:-latest}"
DATE="$(date +%Y%m%d)"
BUNDLE_NAME="eurion-bundle-${VERSION}-${DATE}"

echo "╔══════════════════════════════════════════════════╗"
echo "║  Building Eurion Air-Gap Bundle                   ║"
echo "║  Version: ${VERSION}                              ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Application images ───────────────────────────────────────────────────────
APP_IMAGES=(
    "eurion-gateway:${VERSION}"
    "eurion-identity-service:${VERSION}"
    "eurion-org-service:${VERSION}"
    "eurion-audit-service:${VERSION}"
    "eurion-messaging-service:${VERSION}"
    "eurion-file-service:${VERSION}"
    "eurion-video-service:${VERSION}"
    "eurion-notification-service:${VERSION}"
    "eurion-admin-service:${VERSION}"
    "eurion-search-service:${VERSION}"
    "eurion-ai-service:${VERSION}"
    "eurion-workflow-service:${VERSION}"
    "eurion-preview-service:${VERSION}"
    "eurion-transcription-service:${VERSION}"
    "eurion-bridge-service:${VERSION}"
    "eurion-frontend:${VERSION}"
)

# ── Infrastructure images ────────────────────────────────────────────────────
INFRA_IMAGES=(
    "postgres:16-alpine"
    "redis:7-alpine"
    "bitnami/kafka:3.7"
    "minio/minio:latest"
    "minio/mc:latest"
    "traefik:v2.11"
    "gotenberg/gotenberg:8"
    "coturn/coturn:4.6.2-alpine"
    "getmeili/meilisearch:v1.7"
    "prom/prometheus:v2.51.0"
    "grafana/grafana:10.4.1"
    "grafana/loki:2.9.5"
    "prom/node-exporter:latest"
    "gcr.io/cadvisor/cadvisor:latest"
)

ALL_IMAGES=("${APP_IMAGES[@]}" "${INFRA_IMAGES[@]}")

echo "Pulling ${#ALL_IMAGES[@]} images..."
echo ""

for img in "${ALL_IMAGES[@]}"; do
    echo -n "  Pulling ${img}... "
    if docker pull "$img" &>/dev/null; then
        echo "✓"
    else
        echo "⚠ (may need to be built locally)"
    fi
done

echo ""
echo "Saving images to bundle..."
docker save "${ALL_IMAGES[@]}" | gzip > "${BUNDLE_NAME}.tar.gz"

SIZE=$(du -sh "${BUNDLE_NAME}.tar.gz" | cut -f1)
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  ✓ Bundle created: ${BUNDLE_NAME}.tar.gz"
echo "║  Size: ${SIZE}"
echo "║  Images: ${#ALL_IMAGES[@]}"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "Transfer this file to the air-gapped host, then run:"
echo "  ./install.sh"
echo "  Select option C (Air-Gapped)"
echo "  Provide the path to this bundle"
