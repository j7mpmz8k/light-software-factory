#!/usr/bin/env bash
# Usage: .factory/sync-hub.sh (runs strictly inside herdr-hub / architect role)
set -euo pipefail

if [ "${FACTORY_ROLE:-}" != "architect" ]; then
  echo "[sync-hub] Skipping: intended only for herdr-hub (architect role)." >&2
  exit 0
fi

cd /workspace
if [ -n "$(git status --porcelain)" ]; then
  echo "[sync-hub] WARNING: /workspace has uncommitted edits; skipping pull to avoid clobbering." >&2
  exit 1
fi

git fetch origin staging --quiet
git checkout staging --quiet
if ! git pull --ff-only origin staging --quiet; then
  echo "[sync-hub] WARNING: Non-fast-forward divergence on staging; manual check needed." >&2
  exit 1
fi

if [ -x /workspace/.factory/sync-skills.sh ]; then
  /workspace/.factory/sync-skills.sh architect
  /workspace/.factory/sync-skills.sh orchestrator
fi

echo "[sync-hub] herdr-hub /workspace synced to origin/staging ($(git rev-parse --short HEAD))."
