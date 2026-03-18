#!/usr/bin/env python3
"""
Write complete correct workspace-based multi-stage Dockerfiles for the 5
standalone services that originally had a non-workspace Dockerfile.

The pattern MUST match the working services (e.g. identity-service):
- Runner stage copies backend/shared/dist + package.json (resolves symlink)
- Runner stage copies service files to full path backend/services/<svc>/dist
- CMD uses full path: node backend/services/<svc>/dist/server.js
- Also copies migrations/ so migrate.js can run

KEY FIX: The deps stage copies ALL 14 service package.json files so that
npm ci sees the complete workspace and correctly creates workspace-local
node_modules (e.g. search-service/node_modules/meilisearch@0.40.0).
Without all package.jsons, npm ci silently skips workspace-local package
installations, causing ERR_MODULE_NOT_FOUND at runtime.

PERMISSION FIX (v10.1): NEVER use --chown=nordlink:nordlink on COPY --from
directives. Source files transferred via SCP from Windows retain restrictive
permission bits (e.g. 700 on directories). COPY --chown changes ownership
but preserves permission bits, causing "Permission denied" at runtime.
Instead: COPY without --chown, then RUN chmod -R a+rX && chown -R as a
separate layer. This guarantees correct permissions regardless of source OS.

This script is idempotent: it always writes the canonical content.
"""
import os

SOURCE = os.environ.get("EURION_SOURCE", "/opt/eurion/source")

# All 14 backend service names (needed for full workspace deps stage)
ALL_SERVICES = [
    "admin-service",
    "ai-service",
    "audit-service",
    "bridge-service",
    "file-service",
    "identity-service",
    "messaging-service",
    "notification-service",
    "org-service",
    "preview-service",
    "search-service",
    "transcription-service",
    "video-service",
    "workflow-service",
]

# (service-name, port, has_migrations, extra_apk, has_workspace_local_mods)
# has_workspace_local_mods: True if package-lock.json has
#   backend/services/<svc>/node_modules/* entries (verified from lock file)
SERVICES = [
    ("search-service",        3009, False, "", True),   # meilisearch@0.40.0, cross-fetch
    ("ai-service",            3010, True,  "", False),
    ("workflow-service",      3011, True,  "", False),
    ("preview-service",       3012, True,  "", False),
    ("transcription-service", 3013, True,  "", False),
]


def all_service_package_json_copies() -> str:
    """Generate COPY lines for all 14 service package.json files."""
    lines = []
    for svc in ALL_SERVICES:
        lines.append(
            f"COPY backend/services/{svc}/package.json ./backend/services/{svc}/"
        )
    return "\n".join(lines)


def make_dockerfile(svc: str, port: int, has_migrations: bool,
                    extra_apk: str, has_workspace_local_mods: bool) -> str:
    apk_line = f"\nRUN apk add --no-cache {extra_apk}" if extra_apk else ""
    migrations_copy = (
        f"COPY --from=builder "
        f"/app/backend/services/{svc}/migrations "
        f"./backend/services/{svc}/migrations\n"
    ) if has_migrations else ""

    # If this service has workspace-local node_modules (version-conflict deps),
    # also copy that directory to the runner stage so Node.js can find them.
    workspace_local_mods_copy = (
        f"# Copy workspace-local node_modules (version-pinned deps like meilisearch)\n"
        f"COPY --from=deps "
        f"/app/backend/services/{svc}/node_modules "
        f"./backend/services/{svc}/node_modules\n"
    ) if has_workspace_local_mods else ""

    all_copies = all_service_package_json_copies()

    return (
        "FROM node:22-alpine AS deps\n"
        "WORKDIR /app\n"
        "# Copy ALL service package.json files so npm ci resolves the complete\n"
        "# workspace graph and correctly installs workspace-local packages.\n"
        "COPY package.json package-lock.json ./\n"
        f"COPY backend/shared/package.json ./backend/shared/\n"
        f"{all_copies}\n"
        "RUN npm ci --ignore-scripts --omit=dev\n"
        "\n"
        "FROM node:22-alpine AS builder\n"
        "WORKDIR /app\n"
        "COPY package.json package-lock.json tsconfig.base.json ./\n"
        f"COPY backend/shared/ ./backend/shared/\n"
        f"COPY backend/services/{svc}/ ./backend/services/{svc}/\n"
        f"RUN npm ci --ignore-scripts --workspace=backend/shared "
        f"--workspace=backend/services/{svc} --include-workspace-root\n"
        "RUN npm run build -w backend/shared || true\n"
        f"RUN npx tsc -p backend/services/{svc}/tsconfig.json || true\n"
        "\n"
        "FROM node:22-alpine AS runner\n"
        "WORKDIR /app\n"
        + apk_line + ("\n" if apk_line else "")
        + "RUN addgroup --system nordlink "
        "&& adduser --system --ingroup nordlink nordlink\n"
        # Root node_modules — no --chown, fixed via RUN chmod+chown below
        "COPY --from=deps /app/node_modules ./node_modules\n"
        + workspace_local_mods_copy
        # Shared package dist + package.json
        + "COPY --from=builder /app/backend/shared/dist ./backend/shared/dist\n"
        "COPY --from=builder /app/backend/shared/package.json ./backend/shared/\n"
        # Service dist + package.json + migrations
        f"COPY --from=builder "
        f"/app/backend/services/{svc}/dist ./backend/services/{svc}/dist\n"
        f"COPY --from=builder "
        f"/app/backend/services/{svc}/package.json ./backend/services/{svc}/\n"
        + migrations_copy
        + "# Fix permissions: COPY preserves source bits (may be 700 from Windows/SCP).\n"
        "# chmod a+rX makes everything readable, then chown to nordlink.\n"
        "RUN chmod -R a+rX backend/ && chown -R nordlink:nordlink backend/\n"
        "USER nordlink\n"
        "ENV NODE_ENV=production\n"
        f"EXPOSE {port}\n"
        f'CMD ["node", "backend/services/{svc}/dist/server.js"]\n'
    )


for svc, port, has_migrations, extra_apk, has_ws_mods in SERVICES:
    path = f"{SOURCE}/backend/services/{svc}/Dockerfile"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    content = make_dockerfile(svc, port, has_migrations, extra_apk, has_ws_mods)
    with open(path, "wb") as f:
        f.write(content.encode("utf-8"))
    print(f"  Wrote {svc}/Dockerfile (port {port}, ws_local={has_ws_mods})")

print("fix_dockerfiles done")
