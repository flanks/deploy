#!/usr/bin/env python3
"""
Fix admin-service/src/server.ts — add missing Fastify app.decorate()
calls for 'pg' and 'authenticate' before middleware registration.
Idempotent — checks if already present first.
"""
import os

SOURCE = os.environ.get("EURION_SOURCE", "/opt/eurion/source")
PATH = f"{SOURCE}/backend/services/admin-service/src/server.ts"

with open(PATH) as f:
    content = f.read()

if "app.decorate('authenticate'" in content or 'app.decorate("authenticate"' in content:
    print("admin-service: authenticate decorator already present — skipping")
    exit(0)

DECORATOR_BLOCK = """
  // ── Runtime decorators (required before route registration) ──────────────
  app.decorate('pg', pool);
  app.decorate('authenticate', async function (request: any, reply: any) {
    const authHeader = request.headers['authorization'] ?? '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
    if (!token) return reply.status(401).send({ success: false, error: { code: 'AUTH_001', message: 'Missing token' } });
    try {
      const parts = token.split('.');
      if (parts.length !== 3) throw new Error('Invalid JWT');
      const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
      if (payload.iss !== 'EURION') throw new Error('Invalid issuer');
      request.user = { id: payload.sub, role: payload.role, orgId: payload.orgId };
    } catch {
      return reply.status(401).send({ success: false, error: { code: 'AUTH_002', message: 'Invalid token' } });
    }
  });

"""

# Insert after "const app = Fastify({...});" block — find the closing ");" of Fastify()
fastify_end = content.find("});\n", content.find("const app = Fastify("))
if fastify_end == -1:
    fastify_end = content.find(");\n", content.find("const app = Fastify("))

insert_at = content.find("\n", fastify_end) + 1
content = content[:insert_at] + DECORATOR_BLOCK + content[insert_at:]

with open(PATH, "w") as f:
    f.write(content)

print("admin-service: added pg + authenticate decorators")
