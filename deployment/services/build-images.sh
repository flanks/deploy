#!/bin/bash

# EURION Backend Services - Build Script
# Builds Docker images for all 14 services (13 microservices + gateway)

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║       EURION Backend Services - Docker Image Builder       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if source code exists
SOURCE_DIR="/opt/eurion/source"

if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}❌ Source code not found at $SOURCE_DIR${NC}"
    echo ""
    echo "Please clone the repository first:"
    echo "  cd /opt/eurion"
    echo "  git clone https://github.com/your-org/eurion.git source"
    exit 1
fi

cd "$SOURCE_DIR"

echo -e "${BLUE}📦 Installing dependencies...${NC}"
npm install

echo ""
echo -e "${BLUE}🏗️  Building TypeScript code...${NC}"
npm run build

echo ""
echo -e "${BLUE}🐳 Building Docker images...${NC}"
echo ""

# Array of services to build
services=(
    "gateway"
    "identity-service"
    "org-service"
    "audit-service"
    "messaging-service"
    "file-service"
    "video-service"
    "notification-service"
    "admin-service"
    "search-service"
    "ai-service"
    "workflow-service"
    "preview-service"
    "transcription-service"
    "bridge-service"
)

# Build each service
for service in "${services[@]}"; do
    echo -e "${BLUE}Building $service...${NC}"
    
    if [ "$service" == "gateway" ]; then
        SERVICE_DIR="backend/gateway"
    else
        SERVICE_DIR="backend/services/$service"
    fi
    
    if [ -f "$SERVICE_DIR/Dockerfile" ]; then
        docker build -t eurion/$service:latest -f $SERVICE_DIR/Dockerfile .
        echo -e "${GREEN}✓ Built eurion/$service:latest${NC}"
    else
        echo -e "${YELLOW}⚠️  No Dockerfile found for $service${NC}"
    fi
    echo ""
done

# Build frontend web app
echo -e "${BLUE}Building frontend web app...${NC}"
FRONTEND_DIR="frontend/web"
if [ -f "$FRONTEND_DIR/Dockerfile" ]; then
    docker build -t eurion/frontend:latest -f $FRONTEND_DIR/Dockerfile $FRONTEND_DIR
    echo -e "${GREEN}✓ Built eurion/frontend:latest${NC}"
else
    echo -e "${YELLOW}⚠️  No Dockerfile found for frontend web${NC}"
fi
echo ""

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            ✓ All Docker Images Built Successfully          ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}📊 Built Images:${NC}"
docker images | grep "eurion/" | head -20

echo ""
echo -e "${GREEN}Next step: Deploy services${NC}"
echo "  cd /opt/eurion/services"
echo "  docker compose up -d"
