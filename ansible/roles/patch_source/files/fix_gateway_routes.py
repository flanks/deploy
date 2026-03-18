#!/usr/bin/env python3
"""
Fix gateway server.ts — remove any duplicate proxy entries in SERVICE_ROUTES
that map the same prefix to different upstreams.
"""
import os
import re

SOURCE = os.environ.get("EURION_SOURCE", "/opt/eurion/source")
PATH = f"{SOURCE}/backend/gateway/src/server.ts"

with open(PATH) as f:
    content = f.read()

# Find all route entries: { prefix: '/v1/xxx', upstream: '...' }
pattern = r"\{[^}]*prefix:\s*['\"]([^'\"]+)['\"][^}]*\}"
matches = list(re.finditer(pattern, content))

seen_prefixes = {}
to_remove = []

for m in matches:
    prefix = m.group(1)
    if prefix in seen_prefixes:
        to_remove.append(m.group(0))
        print(f"  Duplicate found: {prefix} — removing second entry")
    else:
        seen_prefixes[prefix] = m.start()

for block in to_remove:
    # Remove the block and any trailing comma+whitespace
    content = content.replace(block + ",", "", 1)
    content = content.replace(block, "", 1)

with open(PATH, "w") as f:
    f.write(content)

print(f"Gateway routes: removed {len(to_remove)} duplicates")
