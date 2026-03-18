#!/usr/bin/env python3
"""
Fix video-service/src/server.ts — remove inline duplicate GET/POST handlers
for routes that are also registered via callRoutes plugin.
Removes: app.get('/v1/calls/:id', ...) and app.post('/v1/calls/:id/end', ...)
when they appear WITHOUT preHandler/authenticate (the inline legacy versions).
"""
import os

SOURCE = os.environ.get("EURION_SOURCE", "/opt/eurion/source")
PATH = f"{SOURCE}/backend/services/video-service/src/server.ts"

with open(PATH) as f:
    lines = f.readlines()

new_lines = []
i = 0
removed = []

while i < len(lines):
    line = lines[i]

    is_dup_get  = ("app.get('/v1/calls/:id'" in line and
                   "websocket" not in line and
                   "preHandler" not in line)
    is_dup_post = ("app.post('/v1/calls/:id/end'" in line and
                   "preHandler" not in line)

    if is_dup_get or is_dup_post:
        tag = "GET /v1/calls/:id" if is_dup_get else "POST /v1/calls/:id/end"
        removed.append(tag)
        # Skip until balanced closing '});'
        depth = 0
        started = False
        while i < len(lines):
            depth += lines[i].count("{") - lines[i].count("}")
            if not started and depth > 0:
                started = True
            if started and depth <= 0:
                i += 1
                break
            i += 1
        continue

    new_lines.append(line)
    i += 1

with open(PATH, "w") as f:
    f.writelines(new_lines)

print(f"video-service: removed {len(removed)} duplicate inline routes: {removed}")
