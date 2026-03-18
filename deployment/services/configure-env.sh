#!/bin/bash

# EURION Services - Environment Configuration Helper
# Copies passwords from infrastructure/storage/coturn .env files

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🔧 Configuring services/.env from infrastructure...${NC}"

# Check if infrastructure is deployed
if [ ! -f "/opt/eurion/infrastructure/.env" ]; then
    echo -e "${YELLOW}⚠️  Infrastructure .env not found. Run infrastructure deployment first.${NC}"
    exit 1
fi

# Create .env from template
if [ -f ".env.template" ]; then
    cp .env.template .env
else
    echo -e "${YELLOW}⚠️  .env.template not found${NC}"
    exit 1
fi

# Extract values from infrastructure
echo -e "${BLUE}Copying database passwords...${NC}"
for var in PG_IDENTITY_PASSWORD PG_ORG_PASSWORD PG_AUDIT_PASSWORD PG_MESSAGING_PASSWORD \
           PG_FILE_PASSWORD PG_VIDEO_PASSWORD PG_NOTIFICATION_PASSWORD PG_ADMIN_PASSWORD \
           REDIS_PASSWORD; do
    value=$(grep "^${var}=" /opt/eurion/infrastructure/.env | cut -d'=' -f2)
    if [ -n "$value" ]; then
        sed -i "s|^${var}=.*|${var}=${value}|" .env
        echo -e "${GREEN}  ✓ ${var}${NC}"
    fi
done

# Extract from storage
echo -e "${BLUE}Copying storage credentials...${NC}"
for var in MINIO_ROOT_USER MINIO_ROOT_PASSWORD MEILISEARCH_MASTER_KEY; do
    value=$(grep "^${var}=" /opt/eurion/storage/.env | cut -d'=' -f2)
    if [ -n "$value" ]; then
        sed -i "s|^${var}=.*|${var}=${value}|" .env
        echo -e "${GREEN}  ✓ ${var}${NC}"
    fi
done

# Extract from coturn
echo -e "${BLUE}Copying TURN credentials...${NC}"
for var in TURN_USERNAME TURN_PASSWORD; do
    value=$(grep "^${var}=" /opt/eurion/coturn/.env | cut -d'=' -f2)
    if [ -n "$value" ]; then
        sed -i "s|^${var}=.*|${var}=${value}|" .env
        echo -e "${GREEN}  ✓ ${var}${NC}"
    fi
done

# Copy domain
PUBLIC_DOMAIN=$(grep "^PUBLIC_DOMAIN=" /opt/eurion/infrastructure/.env | cut -d'=' -f2)
sed -i "s|^PUBLIC_DOMAIN=.*|PUBLIC_DOMAIN=${PUBLIC_DOMAIN}|" .env
echo -e "${GREEN}  ✓ PUBLIC_DOMAIN${NC}"

# Generate JWT secret
echo -e "${BLUE}Generating JWT secret...${NC}"
JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|" .env
echo -e "${GREEN}  ✓ JWT_SECRET${NC}"

chmod 600 .env

echo ""
echo -e "${GREEN}✓ Services .env configured${NC}"
echo -e "${YELLOW}⚠️  Save JWT_SECRET securely: ${JWT_SECRET}${NC}"
