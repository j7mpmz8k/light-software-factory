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

load_kv_file() {
  local file="$1"
  [ -r "$file" ] || return 0
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] || [[ "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    val="${val#"${val%%[![:space:]]*}"}"
    if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\'(.*)\'$ ]]; then
      val="${BASH_REMATCH[1]}"
    else
      val="${val%%[[:space:]]#*}"
      val="${val%"${val##*[![:space:]]}"}"
    fi
    if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [ -z "${!key:-}" ]; then
      printf -v "$key" '%s' "$val"
      export "${key?}"
    fi
  done < "$file"
}

ENV_FILE="${BRIDGE_ENV_FILE:-/run/factory-config/bridge.env}"
[ ! -r "$ENV_FILE" ] && ENV_FILE=".factory/.env"
load_kv_file "$ENV_FILE"
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
export GH_TOKEN="$SYNC_TOKEN"

REPO_URL="$(gh repo view --json url -q .url 2>/dev/null || true)"
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

# 1. Resolve Project ID and Field ID (with 1-hour cache in /tmp to minimize API calls)
SAFE_OWNER="$(echo "$OWNER" | tr -c '[:alnum:]_' '_')"
CACHE_FILE="/tmp/factory-proj-meta-${SAFE_OWNER}-${PROJECT_NUMBER}.json"
NOW=$(date +%s)
CACHE_AGE=999999
if [ -f "$CACHE_FILE" ]; then
  CACHE_MTIME=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  CACHE_AGE=$((NOW - CACHE_MTIME))
fi

if [ "$CACHE_AGE" -gt 3600 ]; then
  PROJ_VIEW="$(gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json 2>/dev/null || true)"
  FIELD_LIST="$(gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json 2>/dev/null || true)"
  if [ -n "$PROJ_VIEW" ] && [ -n "$FIELD_LIST" ]; then
    cat <<EOF > "$CACHE_FILE"
{
  "project": $PROJ_VIEW,
  "fields": $FIELD_LIST
}
EOF
  fi
fi

if [ ! -f "$CACHE_FILE" ]; then
  echo "[board-sync] WARNING: Unable to fetch project #${PROJECT_NUMBER} metadata; continuing safely." >&2
  exit 0
fi

PROJECT_ID="$(jq -r '.project.id // empty' "$CACHE_FILE" 2>/dev/null || true)"
[ -z "$PROJECT_ID" ] && exit 0

FIELD_JSON="$(jq -c --arg fn "$FIELD_NAME" '(.fields.fields[]? // empty) | select(.name == $fn)' "$CACHE_FILE" 2>/dev/null || true)"
if [ -z "$FIELD_JSON" ]; then
  echo "[board-sync] WARNING: Field '${FIELD_NAME}' not found in project #${PROJECT_NUMBER}; skipping." >&2
  exit 0
fi

FIELD_ID="$(echo "$FIELD_JSON" | jq -r '.id')"
DATA_TYPE="$(echo "$FIELD_JSON" | jq -r '.dataType // empty')"

# 2. Add or find Item in Project
ITEM_ID=""
ADD_OUT="$(gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$ITEM_URL" --format json 2>/dev/null || true)"
if [ -n "$ADD_OUT" ]; then
  ITEM_ID="$(echo "$ADD_OUT" | jq -r '.id // empty')"
fi

if [ -z "$ITEM_ID" ]; then
  ITEM_ID="$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 500 --format json 2>/dev/null | jq -r --arg u "$ITEM_URL" '(.items[]? | select(.content.url == $u) | .id) // empty' 2>/dev/null || true)"
fi

if [ -z "$ITEM_ID" ]; then
  echo "[board-sync] WARNING: Could not link ${ITEM_LABEL} to project #${PROJECT_NUMBER}; skipping." >&2
  exit 0
fi

# 3. Edit Field Value (handle SingleSelect vs Text cleanly without word-splitting)
EDIT_ARGS=()
if [ "$DATA_TYPE" = "SINGLE_SELECT" ]; then
  OPT_ID="$(echo "$FIELD_JSON" | jq -r --arg fv "$FIELD_VALUE" '(.options[]? | select(.name == $fv) | .id) // empty')"
  if [ -n "$OPT_ID" ]; then
    EDIT_ARGS=(--single-select-option-id "$OPT_ID")
  fi
fi

if [ "${#EDIT_ARGS[@]}" -eq 0 ]; then
  EDIT_ARGS=(--text "$FIELD_VALUE")
fi

if gh project item-edit --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$FIELD_ID" "${EDIT_ARGS[@]}" >/dev/null 2>&1; then
  echo "[board-sync] ${ITEM_LABEL} -> ${FIELD_NAME}: ${FIELD_VALUE}"
else
  echo "[board-sync] WARNING: Could not update ${ITEM_LABEL} field ${FIELD_NAME}; continuing safely." >&2
fi
exit 0
