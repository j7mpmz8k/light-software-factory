#!/usr/bin/env bash
# Usage: .factory/prep-branch.sh <issue_number_or_branch> [short_slug] [--keep-db]
set -euo pipefail

KEEP_DB=false
ARGS=()
for arg in "$@"; do
  if [ "$arg" = "--keep-db" ]; then
    KEEP_DB=true
  else
    ARGS+=("$arg")
  fi
done

if [ ${#ARGS[@]} -lt 1 ]; then
  echo "Usage: $0 <issue_number_or_branch> [short_slug] [--keep-db]"
  exit 1
fi

TARGET="${ARGS[0]}"
SLUG="${ARGS[1]:-task}"

if [[ "$TARGET" == feature/* ]]; then
  BRANCH_NAME="$TARGET"
else
  BRANCH_NAME="feature/issue-${TARGET}-${SLUG}"
fi

cd /workspace

# 1. Reset isolated worker Postgres public schema cleanly BEFORE merging (Fix prep-branch conflict state)
if [ "$KEEP_DB" = false ] && [ -n "${DATABASE_URL:-}" ] && command -v psql >/dev/null 2>&1; then
  echo "[prep-branch] Resetting isolated Postgres public schema for ${WORKER_NAME:-worker}..."
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO CURRENT_USER;" >/dev/null || true
  # Also clean any Drizzle or custom migration schema if present
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS drizzle CASCADE;" >/dev/null 2>&1 || true
fi

# 2. Abort any lingering conflict / rebase / cherry-pick states
git merge --abort 2>/dev/null || true
git rebase --abort 2>/dev/null || true
git cherry-pick --abort 2>/dev/null || true
git reset --hard HEAD
git clean -fd

git fetch origin staging

# 3. Checkout branch cleanly
if git ls-remote --exit-code --heads origin "$BRANCH_NAME" >/dev/null 2>&1; then
  git fetch origin "$BRANCH_NAME"
  git checkout -B "$BRANCH_NAME" "origin/$BRANCH_NAME"
  if ! git merge --no-edit origin/staging; then
    echo "MERGE_CONFLICT detected on $BRANCH_NAME against origin/staging."
    exit 2
  fi
else
  git checkout -B "$BRANCH_NAME" origin/staging
fi

# 4. Refresh Node dependencies
if [ -f package-lock.json ]; then
  npm ci --no-audit --no-fund
elif [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
  pnpm install --frozen-lockfile
elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
  yarn install --frozen-lockfile
fi

# 5. Refresh progressive-disclosure skill links
if [ -x /workspace/.factory/sync-skills.sh ] && [ -n "${WORKER_NAME:-}" ]; then
  /workspace/.factory/sync-skills.sh "$WORKER_NAME"
fi

echo "Container /workspace ready on branch $BRANCH_NAME (clean DB + synced deps/skills for ${WORKER_NAME:-worker})"
