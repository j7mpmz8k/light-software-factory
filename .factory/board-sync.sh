#!/usr/bin/env bash
# Usage:
#   .factory/board-sync.sh <issue_number> <field_name> <value>
#   .factory/board-sync.sh pr:<pr_number> <field_name> <value>
set -uo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <issue_number|pr:pr_number> <field_name> <value>" >&2
  exit 0
fi

if [ "${FACTORY_ROLE:-}" = "worker" ]; then
  echo "[board-sync] Skipping: worker role does not modify project board." >&2
  exit 0
fi

ENV_FILE="${BRIDGE_ENV_FILE:-/run/factory-config/bridge.env}"
[ ! -r "$ENV_FILE" ] && ENV_FILE=".factory/.env"
[ -r "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }
[ -z "${PROJECT_NUMBER:-}" ] && exit 0

OWNER="${PROJECT_OWNER:-@me}"
TARGET_REF="$1"
FIELD_NAME="$2"
FIELD_VALUE="$3"
AUTH_ROOT="${FACTORY_AUTH_ROOT:-/run/factory-auth}"

SYNC_TOKEN=""
if [ "$OWNER" = "@me" ] && [ -r "${AUTH_ROOT}/architect/project-token" ]; then
  SYNC_TOKEN="$(cat "${AUTH_ROOT}/architect/project-token")"
fi
if [ -z "$SYNC_TOKEN" ] && [ -r "${AUTH_ROOT}/architect/token" ]; then
  SYNC_TOKEN="$(cat "${AUTH_ROOT}/architect/token")"
fi

if [ -z "$SYNC_TOKEN" ]; then
  echo "[board-sync] WARNING: No token available for board sync; skipping safely." >&2
  exit 0
fi

export GH_CONFIG_DIR="/tmp/factory-gh-config-architect"
mkdir -p "$GH_CONFIG_DIR"

REPO_URL="$(GH_TOKEN="$SYNC_TOKEN" gh repo view --json url -q .url 2>/dev/null || true)"
[ -z "$REPO_URL" ] && exit 0

if [[ "$TARGET_REF" == pr:* ]]; then
  ITEM_LABEL="PR #${TARGET_REF#pr:}"
  ITEM_URL="${REPO_URL}/pull/${TARGET_REF#pr:}"
elif [[ "$TARGET_REF" == https://* ]]; then
  ITEM_LABEL="$TARGET_REF"
  ITEM_URL="$TARGET_REF"
else
  ITEM_LABEL="Issue #${TARGET_REF}"
  ITEM_URL="${REPO_URL}/issues/${TARGET_REF}"
fi

GH_TOKEN="$SYNC_TOKEN" gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$ITEM_URL" >/dev/null 2>&1 || true

if GH_TOKEN="$SYNC_TOKEN" gh project item-edit "$PROJECT_NUMBER" --owner "$OWNER" --url "$ITEM_URL" --field "$FIELD_NAME" --value "$FIELD_VALUE" >/dev/null 2>&1; then
  echo "[board-sync] ${ITEM_LABEL} -> ${FIELD_NAME}: ${FIELD_VALUE}"
else
  echo "[board-sync] WARNING: Could not sync ${ITEM_LABEL} (${FIELD_NAME}=${FIELD_VALUE}); continuing safely." >&2
fi
exit 0
