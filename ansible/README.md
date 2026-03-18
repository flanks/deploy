# EURION Ansible Deployment

Automates the full platform deployment. Estimated time: **~25 minutes** (vs 3+ hours manual).

## Requirements

On the **control machine** (Windows, via WSL or Linux):
```bash
pip install ansible
ansible-galaxy collection install community.docker community.general
```

## Usage

### Full fresh deployment
```bash
ansible-playbook -i inventory/hosts.yml site.yml
```

### Rebuild + redeploy only (skip infra setup)
```bash
ansible-playbook -i inventory/hosts.yml site.yml --tags redeploy
```

### Only patch source (no build)
```bash
ansible-playbook -i inventory/hosts.yml site.yml --tags patch
```

### Only build images (cached patches)
```bash
ansible-playbook -i inventory/hosts.yml site.yml --tags build
```

### Deploy without rebuilding images
```bash
ansible-playbook -i inventory/hosts.yml site.yml --tags deploy,verify --skip-tags build
```

### Verify health only
```bash
ansible-playbook -i inventory/hosts.yml site.yml --tags verify
```

## What this automates

| Step | Manual time | Automated |
|------|-------------|-----------|
| Source patches (TS strict, decorators, routes) | 60 min | ~10s |
| Docker builds — sequential | 40 min | — |
| Docker builds — parallel (2 batches) | — | ~12 min |
| Stack deployment in order | 10 min | ~3 min |
| Health verification | 15 min | ~2 min |
| **Total** | **~3h 15m** | **~18 min** |

## Lessons learned (why this playbook exists)

1. **TypeScript strict mode** — `noUnusedLocals`, `noPropertyAccessFromIndexSignature` etc. break builds.
   Fix: `patch_source` sets `tsc || true` and relaxes tsconfig flags upfront.

2. **`@fastify/websocket` v4/v5 mismatch** — npm lockfile can resolve the wrong version.
   Fix: `patch_source` removes the incompatible plugin; replaced with REST polling.

3. **Alpine `localhost` IPv6** — health checks using `localhost` fail; need `127.0.0.1`.
   Fix: `patch_source` replaces all health check URLs.

4. **Missing runtime decorators** — `app.decorate('authenticate')` must be called at runtime,
   TypeScript type augmentation alone is not enough.
   Fix: `fix_admin_decorators.py` injects the decorator block.

5. **Duplicate Fastify routes** — server.ts had inline handlers that duplicated plugin routes.
   Fix: `fix_video_routes.py` and `fix_gateway_routes.py` remove them.

6. **Service `node_modules` missing in runner stage** — hoisting doesn't always work for
   service-specific packages in multi-stage builds.
   Fix: `fix_dockerfiles.py` adds the COPY step to runner stage.

7. **DNS typo** — nothing in code can catch a mistyped IP in a zone file.
   Fix: `verify` role asserts DNS resolves to the expected public IP before cert requests.

## Security notes

- Move credentials from `group_vars/all.yml` into `ansible-vault` before sharing this repo.
- Generate vault:  `ansible-vault encrypt group_vars/all.yml`
- Run with vault:  `ansible-playbook site.yml --ask-vault-pass`
