#!/usr/bin/env python3
"""
Rewrite video-service Dockerfile to use Debian (glibc) base for mediasoup
native worker compilation.

mediasoup's C++ worker uses glibc-specific headers (byteswap.h, arpa/inet.h,
__builtin_strtoull_l) that do not exist on Alpine/musl libc. Using node:22
(Debian Bookworm) for the deps stage ensures the native binary compiles and
links correctly against glibc.

The runner stage uses node:22-slim (Debian) so the glibc binary can execute.
MEDIASOUP_SKIP_WORKER_PREBUILT_DOWNLOAD forces local compilation instead of
attempting to download a pre-built binary (which often fails in CI/offline).

This script is idempotent — it always writes the canonical content.
"""
import os

SOURCE = os.environ.get("EURION_SOURCE", "/opt/eurion/source")

VIDEO_DOCKERFILE = """\
# deps: Debian-based (glibc) for mediasoup C++ worker native compilation.
# Alpine/musl lacks byteswap.h and other glibc headers mediasoup requires.
FROM node:22 AS deps
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \\
    python3 python3-pip build-essential cmake meson ninja-build \\
    && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
COPY backend/shared/package.json ./backend/shared/
COPY backend/services/video-service/package.json ./backend/services/video-service/
# Install production deps from full lock file (no workspace scoping to ensure hoisting)
RUN npm ci --ignore-scripts --omit=dev
# Build mediasoup worker from source (skip prebuilt download — compile for this glibc)
RUN MEDIASOUP_SKIP_WORKER_PREBUILT_DOWNLOAD=true npm rebuild mediasoup && \\
    echo "mediasoup-worker binary:" && \\
    ls -la node_modules/mediasoup/worker/out/Release/mediasoup-worker

FROM node:22-alpine AS builder
WORKDIR /app
RUN apk add --no-cache python3 make g++ linux-headers
COPY package.json package-lock.json tsconfig.base.json ./
COPY backend/shared/ ./backend/shared/
COPY backend/services/video-service/ ./backend/services/video-service/
RUN npm ci --ignore-scripts --workspace=backend/shared --workspace=backend/services/video-service --include-workspace-root
RUN npm run build -w backend/shared
RUN npx tsc -p backend/services/video-service/tsconfig.json || true

# runner: Debian slim so the glibc-linked mediasoup-worker binary can execute
FROM node:22-slim AS runner
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 wget \\
    && rm -rf /var/lib/apt/lists/*
RUN groupadd --system nordlink && useradd --system --gid nordlink nordlink
# Copy compiled node_modules from Debian deps stage (includes mediasoup-worker binary)
COPY --from=deps --chown=nordlink:nordlink /app/node_modules ./node_modules
COPY --from=builder --chown=nordlink:nordlink /app/backend/shared/dist ./backend/shared/dist
COPY --from=builder --chown=nordlink:nordlink /app/backend/shared/package.json ./backend/shared/
COPY --from=builder --chown=nordlink:nordlink /app/backend/services/video-service/dist ./backend/services/video-service/dist
COPY --from=builder --chown=nordlink:nordlink /app/backend/services/video-service/package.json ./backend/services/video-service/
COPY --from=builder --chown=nordlink:nordlink /app/backend/services/video-service/migrations ./backend/services/video-service/migrations
RUN chmod -R a+rX backend/
USER nordlink
ENV NODE_ENV=production
EXPOSE 3006
EXPOSE 10000-10100/udp
CMD ["node", "backend/services/video-service/dist/server.js"]
"""

path = f"{SOURCE}/backend/services/video-service/Dockerfile"
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    f.write(VIDEO_DOCKERFILE)
print(f"Wrote video-service Dockerfile (Debian/glibc base for mediasoup)")
