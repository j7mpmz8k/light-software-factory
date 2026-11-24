#!/usr/bin/env bash
# Usage:
#   docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh [--headless]
set -euo pipefail

HEADLESS=0
for arg in "$@"; do
  case "$arg" in
    --headless|--no-attach) HEADLESS=1 ;;
  esac
done

source /workspace/.factory/enter-role.sh architect
/workspace/.factory/sync-hub.sh || true

HERDR_STATE_DIR="${HERDR_STATE_DIR:-$HOME/.config/herdr}"
AGY_DEFAULT_MODEL="${AGY_DEFAULT_MODEL:-gemini-4-hydrogen-high}"
mkdir -p "$HERDR_STATE_DIR"

for _ in $(seq 1 30); do
  herdr api snapshot >/dev/null 2>&1 && break
  sleep 0.5
done

EXISTING_WS="$(herdr api snapshot 2>/dev/null | jq -r '(.result.snapshot.workspaces[]? // .result.workspaces[]?) | select(.label == "factory") | .workspace_id' | head -n1 || true)"
if [ -n "$EXISTING_WS" ]; then
  if [ "$HEADLESS" -eq 1 ]; then
    echo "[launch-panes] Workspace 'factory' (${EXISTING_WS}) already running (headless mode)."
    exit 0
  fi
  echo "[launch-panes] Workspace 'factory' (${EXISTING_WS}) already running — attaching to Herdr UI..."
  exec herdr
fi

echo "[launch-panes] Bootstrapping native Herdr workspace 'factory' with 6 tabs (A1 + B2 architecture)..."

# 1. Tab: bridge (Webhook Bridge + Priority Queue + Strike Circuit Breaker)
WS_JSON="$(herdr workspace create --cwd /workspace --label factory --focus)"
WS_ID="$(echo "$WS_JSON" | jq -r '.result.workspace.workspace_id')"
BRIDGE_TAB="$(echo "$WS_JSON" | jq -r '.result.tab.tab_id')"
BRIDGE_PANE="$(echo "$WS_JSON" | jq -r '.result.root_pane.pane_id')"
herdr tab rename "$BRIDGE_TAB" bridge >/dev/null
herdr pane rename "$BRIDGE_PANE" bridge >/dev/null
herdr pane run "$BRIDGE_PANE" "node /workspace/.factory/webhook-bridge.mjs" >/dev/null

# Ensure persistent Hermes SOUL.md system prompts are synced before starting hub agents (immune to /clear)
mkdir -p "$HOME/.hermes/profiles/architect" "$HOME/.hermes/profiles/orchestrator"
[ -f /workspace/.factory/architect-seed.md ] && cp /workspace/.factory/architect-seed.md "$HOME/.hermes/profiles/architect/SOUL.md"
[ -f /workspace/.factory/orchestrator-seed.md ] && cp /workspace/.factory/orchestrator-seed.md "$HOME/.hermes/profiles/orchestrator/SOUL.md"

# 2. Tab: architect (Chief Architect inside herdr-hub — GLM-5.3, unattended --yolo)
ARCH_TAB="$(herdr tab create --workspace "$WS_ID" --cwd /workspace --label architect --focus)"
ARCH_PANE="$(echo "$ARCH_TAB" | jq -r '.result.root_pane.pane_id')"
herdr pane rename "$ARCH_PANE" architect >/dev/null
herdr agent start architect --kind hermes --pane "$ARCH_PANE" -- --profile architect --yolo >/dev/null

# 3. Tab: orchestrator (Factory Orchestrator inside herdr-hub — GLM-5.3 + Vision, unattended --yolo)
ORCH_TAB="$(herdr tab create --workspace "$WS_ID" --cwd /workspace --label orchestrator --no-focus)"
ORCH_PANE="$(echo "$ORCH_TAB" | jq -r '.result.root_pane.pane_id')"
herdr pane rename "$ORCH_PANE" orchestrator >/dev/null
herdr agent start orchestrator --kind hermes --pane "$ORCH_PANE" -- --profile orchestrator --yolo >/dev/null

# Helper: wait for worker SSH port 2222 readiness, then launch SSH agent tab with bash -lic
launch_ssh_agent_tab() {
  local name="$1"
  local kind="$2"
  local remote_cmd="$3"

  local tab_json pane_id
  tab_json="$(herdr tab create --workspace "$WS_ID" --cwd /workspace --label "$name" --no-focus)"
  pane_id="$(echo "$tab_json" | jq -r '.result.root_pane.pane_id')"
  herdr pane rename "$pane_id" "$name" >/dev/null
  printf '%s\n' "$pane_id" > "${HERDR_STATE_DIR}/${name}.pane_id"

  local ssh_ready=0
  for _ in $(seq 1 30); do
    if ssh -o BatchMode=yes -o ConnectTimeout=2 "$name" true >/dev/null 2>&1; then
      ssh_ready=1
      break
    fi
    sleep 2
  done
  if [ "$ssh_ready" -ne 1 ]; then
    echo "[launch-panes] Warning: SSH port 2222 on '${name}' not yet reachable after 60s; attempting pane launch..." >&2
  fi

  herdr pane run "$pane_id" "HERDR_AGENT=${kind} ssh -t ${name} \"bash -lic '${remote_cmd}'\"" >/dev/null

  for _ in $(seq 1 20); do
    if herdr agent rename "$pane_id" "$name" >/dev/null 2>&1; then
      echo "[launch-panes] Registered native Herdr agent '${name}' (${kind}) on pane ${pane_id}."
      return 0
    fi
    sleep 1
  done
  echo "[launch-panes] Note: '${name}' booting over SSH..."
}

# 4. Tab: worker-agy (Dynamic multi-model Antigravity CLI — Carbon / Neon / Hydrogen / Opus 5.5)
printf '%s\n' "$AGY_DEFAULT_MODEL" > "${HERDR_STATE_DIR}/worker-agy.model"
launch_ssh_agent_tab "worker-agy" "agy" "agy --model ${AGY_DEFAULT_MODEL} --dangerously-skip-permissions"

# 5. Tab: worker-qwen (Free Local GPU builder)
launch_ssh_agent_tab "worker-qwen" "hermes" "hermes --profile qwen --yolo"

# 6. Tab: worker-glm (Cheap GLM-5.3 API backup & overflow builder)
launch_ssh_agent_tab "worker-glm" "hermes" "hermes --profile glm --yolo"

echo "[launch-panes] Waiting for 'architect' and 'orchestrator' (loaded via persistent SOUL.md) to settle..."
herdr agent wait architect --timeout 30000 >/dev/null 2>&1 || true
herdr agent wait orchestrator --timeout 30000 >/dev/null 2>&1 || true

echo "[launch-panes] Native Herdr agents active:"
herdr agent list || true
if [ "$HEADLESS" -eq 1 ]; then
  echo "[launch-panes] Headless bootstrap complete — all 6 tabs running in background."
  exit 0
fi
exec herdr
