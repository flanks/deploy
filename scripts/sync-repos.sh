#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# EURION — Sync monorepo to split GitHub repositories
#
# Monorepo (flanks/eurion)  →  origin
# Source code (flanks/source) → source  (eu-teams/ subtree)
# Deploy configs (flanks/deploy) → deploy (ansible/ + deployment/ + customer-deploy/ + stalwart-deploy/)
#
# Usage:
#   ./scripts/sync-repos.sh              # Push to all remotes
#   ./scripts/sync-repos.sh source       # Push only to flanks/source
#   ./scripts/sync-repos.sh deploy       # Push only to flanks/deploy
#   ./scripts/sync-repos.sh origin       # Push only to flanks/eurion
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TARGET="${1:-all}"

# ── 1. Push to origin (full monorepo) ─────────────────────────────────────────
if [ "$TARGET" = "all" ] || [ "$TARGET" = "origin" ]; then
  echo "🔄 Pushing to origin (flanks/eurion)..."
  git push origin main
  echo "✅ origin pushed"
  echo ""
fi

# ── 2. Push eu-teams/ subtree to flanks/source ───────────────────────────────
if [ "$TARGET" = "all" ] || [ "$TARGET" = "source" ]; then
  echo "🔄 Pushing eu-teams/ subtree to source (flanks/source)..."
  # git subtree push splits the history of the eu-teams/ subdirectory
  # and pushes only those commits to the source remote
  git subtree push --prefix=eu-teams source main
  echo "✅ source pushed"
  echo ""
fi

# ── 3. Push deploy content to flanks/deploy ──────────────────────────────────
# The deploy repo has a FLAT structure (ansible/ and deployment/ at root).
# We can't use a single subtree push because the content spans multiple
# top-level directories. Instead, we use a temporary branch + filter approach.
if [ "$TARGET" = "all" ] || [ "$TARGET" = "deploy" ]; then
  echo "🔄 Preparing deploy content for flanks/deploy..."

  # Create a temporary branch with only deploy-related content
  TEMP_BRANCH="deploy-sync-$(date +%s)"

  # Use git subtree split to create a synthetic branch with combined content
  # Since we have multiple directories, we need to use a different approach:
  # We'll create a temporary orphan branch, copy the files, and force-push.

  git checkout --orphan "$TEMP_BRANCH" 2>/dev/null || git checkout -B "$TEMP_BRANCH"

  # Clean the index
  git rm -rf --cached . > /dev/null 2>&1 || true

  # Add only deploy-related directories
  git add ansible/ deployment/ customer-deploy/ stalwart-deploy/ \
          INSTALLATION-GUIDE.md .gitignore 2>/dev/null || true

  # Check if there are changes to commit
  if git diff --cached --quiet 2>/dev/null; then
    echo "   No changes to push to deploy"
  else
    git commit -m "Sync deploy configs from monorepo $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --allow-empty > /dev/null 2>&1

    git push deploy "$TEMP_BRANCH:main" --force
    echo "✅ deploy pushed"
  fi

  # Switch back to main and clean up
  git checkout main
  git branch -D "$TEMP_BRANCH" 2>/dev/null || true
  echo ""
fi

echo "🎉 Sync complete!"
