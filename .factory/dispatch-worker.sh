#!/usr/bin/env bash
# Usage: .factory/dispatch-worker.sh <worker_name> <sub_issue_prompt> [--model <model_id>] [--dry-run]
#
# Dynamically switches Antigravity CLI models when dispatching to worker-agy:
#   - Wave 0 Golden E2E:      --model gemini-4-carbon-high
#   - Wave 1-2 Routine:       --model gemini-4-hydrogen-high (default)
#   - Wave 1-2 Complex:       --model gemini-4-neon-high
#   - 3-Strike Rescue/Merge:  --model claude-opus-5-5-high (or gemini-4-carbon-high)
set -euo pipefail

usage() {
  echo "Usage: $0 <worker_name> <sub_issue_prompt> [--model <model_id>] [--dry-run]" >&2
  exit 1
}

WORKER_NAME=""
PROMPT=""
REQUESTED_MODEL=""
DRY_RUN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --model)
      [ "$#" -ge 2 ] || { echo "Error: --model requires a model ID." >&2; usage; }
      REQUESTED_MODEL="$2"
      shift 2
      ;;
    --model=*)
      REQUESTED_MODEL="${1#--model=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      if [ -z "$WORKER_NAME" ]; then
        WORKER_NAME="$1"
      elif [ -z "$PROMPT" ]; then
        PROMPT="$1"
      else
        echo "Error: Unexpected argument '$1'." >&2
        usage
      fi
      shift
      ;;
  esac
done

if [ -z "$WORKER_NAME" ] || [ -z "$PROMPT" ]; then
  usage
fi

# Validate allowed worker names
case "$WORKER_NAME" in
  worker-agy|worker-qwen|worker-glm)
    ;;
  *)
    echo "Error: Unknown worker '${WORKER_NAME}'. Expected one of: worker-agy, worker-qwen, worker-glm." >&2
    exit 1
    ;;
esac

# Validate model ID format (prevent shell injection)
if [ -n "$REQUESTED_MODEL" ]; then
  if ! [[ "$REQUESTED_MODEL" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Error: Invalid model ID '${REQUESTED_MODEL}'. Only alphanumeric, '.', '_', '-' allowed." >&2
    exit 1
  fi
fi

HERDR_STATE_DIR="${HERDR_STATE_DIR:-$HOME/.config/herdr}"
AGY_DEFAULT_MODEL="${AGY_DEFAULT_MODEL:-gemini-4-hydrogen-high}"

resolve_pane_id() {
  local target="$1"
  local state_file="${HERDR_STATE_DIR}/${target}.pane_id"
  if [ -s "$state_file" ]; then
    cat "$state_file"
    return 0
  fi
  herdr api snapshot 2>/dev/null | jq -r --arg name "$target" '
    (.result.snapshot.workspaces[]? // .result.workspaces[]?)
    | .tabs[]?
    | .panes[]?
    | select(.label == $name or .title == $name)
    | .pane_id
  ' | head -n1
}

if [ "$WORKER_NAME" = "worker-agy" ]; then
  TARGET_MODEL="${REQUESTED_MODEL:-$AGY_DEFAULT_MODEL}"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dispatch-worker:dry-run] worker=worker-agy model=${TARGET_MODEL}"
    exit 0
  fi

  mkdir -p "$HERDR_STATE_DIR"
  # Serialize concurrent model swaps on worker-agy to prevent /exit + pane run races
  if command -v flock >/dev/null 2>&1; then
    exec 9>"${HERDR_STATE_DIR}/worker-agy.lock"
    flock -w 90 9 || { echo "Error: Timed out waiting for worker-agy dispatch lock." >&2; exit 1; }
  fi
  MODEL_FILE="${HERDR_STATE_DIR}/worker-agy.model"
  CURRENT_MODEL=""
  [ -f "$MODEL_FILE" ] && CURRENT_MODEL="$(tr -d '[:space:]' < "$MODEL_FILE" || true)"

  AGENT_ALIVE=0
  if herdr agent get worker-agy >/dev/null 2>&1; then
    AGENT_ALIVE=1
  fi

  if [ "$AGENT_ALIVE" -eq 1 ] && [ "$CURRENT_MODEL" = "$TARGET_MODEL" ]; then
    echo "[dispatch-worker] worker-agy already running '${TARGET_MODEL}'; waiting for idle and wiping context..."
    herdr agent wait worker-agy --until idle --until done --timeout 30000 2>/dev/null || true
    herdr agent send-keys worker-agy "/clear" "Enter" 2>/dev/null || true
    sleep 1
    herdr agent wait worker-agy --until idle --until done --timeout 5000 2>/dev/null || true
  else
    echo "[dispatch-worker] Switching worker-agy model (${CURRENT_MODEL:-none} -> ${TARGET_MODEL})..."
    if [ "$AGENT_ALIVE" -eq 1 ]; then
      # Wait for current atomic task to reach idle so we never interrupt an active git commit
      herdr agent wait worker-agy --until idle --until done --timeout 60000 2>/dev/null || true
      herdr agent send-keys worker-agy "/exit" "Enter" 2>/dev/null || true
      for _ in $(seq 1 10); do
        herdr agent get worker-agy >/dev/null 2>&1 || break
        sleep 0.5
      done
      if herdr agent get worker-agy >/dev/null 2>&1; then
        herdr agent send-keys worker-agy "C-d" 2>/dev/null || true
        sleep 1
      fi
    fi

    PANE_ID="$(resolve_pane_id worker-agy || true)"
    if [ -z "$PANE_ID" ]; then
      echo "Error: Could not resolve Herdr pane_id for worker-agy. Is launch-panes.sh running?" >&2
      exit 1
    fi

    herdr pane run "$PANE_ID" "HERDR_AGENT=agy ssh -t worker-agy \"bash -lic 'agy --model ${TARGET_MODEL} --mode=accept-edits'\"" >/dev/null

    REGISTERED=0
    for _ in $(seq 1 25); do
      if herdr agent rename "$PANE_ID" worker-agy >/dev/null 2>&1; then
        REGISTERED=1
        break
      fi
      sleep 1
    done
    if [ "$REGISTERED" -ne 1 ]; then
      echo "[dispatch-worker] Warning: worker-agy agent registration timed out; waiting for idle..." >&2
    fi

    printf '%s\n' "$TARGET_MODEL" > "$MODEL_FILE"
    herdr agent wait worker-agy --until idle --until done --timeout 30000 2>/dev/null || true
  fi

  echo "[dispatch-worker] Dispatching Sub-Issue prompt to worker-agy (model=${TARGET_MODEL})..."
  herdr agent prompt worker-agy "$PROMPT"
  exit 0
fi

# Hermes workers (worker-qwen, worker-glm)
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dispatch-worker:dry-run] worker=${WORKER_NAME} model=hermes-profile"
  exit 0
fi

echo "[dispatch-worker] Waiting for ${WORKER_NAME} to reach idle state..."
herdr agent wait "$WORKER_NAME" --until idle --until done --timeout 30000 2>/dev/null || true

echo "[dispatch-worker] Wiping LLM context memory for ${WORKER_NAME}..."
herdr agent send-keys "$WORKER_NAME" "/clear" "Enter" 2>/dev/null || true
sleep 1
herdr agent wait "$WORKER_NAME" --until idle --until done --timeout 5000 2>/dev/null || true

echo "[dispatch-worker] Dispatching fresh Sub-Issue prompt to ${WORKER_NAME}..."
herdr agent prompt "$WORKER_NAME" "$PROMPT"
