#!/usr/bin/env python3
"""
Ensure all backend services are listed in root package.json workspaces.
"""
import json
import os

SOURCE = os.environ.get("EURION_SOURCE", "/opt/eurion/source")
ROOT_PKG = f"{SOURCE}/package.json"

REQUIRED_WORKSPACES = [
    "backend/shared",
    "backend/gateway",
    "backend/services/identity-service",
    "backend/services/org-service",
    "backend/services/audit-service",
    "backend/services/messaging-service",
    "backend/services/file-service",
    "backend/services/video-service",
    "backend/services/notification-service",
    "backend/services/admin-service",
    "backend/services/search-service",
    "backend/services/ai-service",
    "backend/services/workflow-service",
    "backend/services/preview-service",
    "backend/services/transcription-service",
]

with open(ROOT_PKG) as f:
    pkg = json.load(f)

existing = set(pkg.get("workspaces", []))
added = []

for ws in REQUIRED_WORKSPACES:
    if ws not in existing:
        existing.add(ws)
        added.append(ws)

pkg["workspaces"] = sorted(existing)

with open(ROOT_PKG, "w") as f:
    json.dump(pkg, f, indent=2)

if added:
    print(f"Added {len(added)} workspaces: {added}")
else:
    print("All workspaces already present")
