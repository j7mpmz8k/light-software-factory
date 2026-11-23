#!/usr/bin/env bash
# Usage: docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh
set -euo pipefail

source /workspace/.factory/enter-role.sh architect
/workspace/.factory/sync-hub.sh || true

HERDR_STATE_DIR="${HERDR_STATE_DIR:-$HOME/.config/herdr}"
AGY_DEFAULT_MODEL="${AGY_DEFAULT_MODEL:-gemini-4-hydrogen-high}"
mkdir -p "$HERDR_STATE_DIR"

for _ in $(seq 1 20); do
  herdr api snapshot >/dev/null 2>&1 && break
  sleep 0.5
done

EXISTING_WS="$(herdr api snapshot 2>/dev/null | jq -r '(.result.snapshot.workspaces[]? // .result.workspaces[]?) | select(.label == "factory") | .workspace_id' | head -n1 || true)"
if [ -n "$EXISTING_WS" ]; then
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

# 2. Tab: architect (Chief Architect inside herdr-hub — GLM-5.3)
ARCH_TAB="$(herdr tab create --workspace "$WS_ID" --cwd /workspace --label architect --focus)"
ARCH_PANE="$(echo "$ARCH_TAB" | jq -r '.result.root_pane.pane_id')"
herdr pane rename "$ARCH_PANE" architect >/dev/null
herdr agent start architect --kind hermes --pane "$ARCH_PANE" -- --profile architect >/dev/null

# 3. Tab: orchestrator (Factory Orchestrator inside herdr-hub — GLM-5.3 + Vision)
ORCH_TAB="$(herdr tab create --workspace "$WS_ID" --cwd /workspace --label orchestrator --no-focus)"
ORCH_PANE="$(echo "$ORCH_TAB" | jq -r '.result.root_pane.pane_id')"
herdr pane rename "$ORCH_PANE" orchestrator >/dev/null
herdr agent start orchestrator --kind hermes --pane "$ORCH_PANE" -- --profile orchestrator >/dev/null

# Helper: launch SSH agent tab with bash -lic and unattended execution
launch_ssh_agent_tab() {
  local name="$1"
  local kind="$2"
  local remote_cmd="$3"

  local tab_json pane_id
  tab_json="$(herdr tab create --workspace "$WS_ID" --cwd /workspace --label "$name" --no-focus)"
  pane_id="$(echo "$tab_json" | jq -r '.result.root_pane.pane_id')"
  herdr pane rename "$pane_id" "$name" >/dev/null
  printf '%s\n' "$pane_id" > "${HERDR_STATE_DIR}/${name}.pane_id"

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
launch_ssh_agent_tab "worker-agy" "agy" "agy --model ${AGY_DEFAULT_MODEL} --mode=accept-edits"

# 5. Tab: worker-qwen (Free Local GPU builder)
launch_ssh_agent_tab "worker-qwen" "hermes" "hermes --profile qwen --yolo"

# 6. Tab: worker-glm (Cheap GLM-5.3 API backup & overflow builder)
launch_ssh_agent_tab "worker-glm" "hermes" "hermes --profile glm --yolo"

echo "[launch-panes] Waiting for 'architect' and 'orchestrator' to reach idle and seeding..."
if herdr agent wait architect --until idle --until done --timeout 30000 >/dev/null 2>&1; then
  herdr agent prompt architect "$(cat /workspace/.factory/architect-seed.md)" >/dev/null || true
fi
if herdr agent wait orchestrator --until idle --until done --timeout 30000 >/dev/null 2>&1; then
  herdr agent prompt orchestrator "$(cat /workspace/.factory/orchestrator-seed.md)" >/dev/null || true
fi

echo "[launch-panes] Native Herdr agents active:"
herdr agent list || true
exec herdr
