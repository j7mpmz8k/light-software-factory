#!/usr/bin/env bash
# Usage: docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh
set -euo pipefail

source /workspace/.factory/enter-role.sh architect
/workspace/.factory/sync-hub.sh || true

for _ in $(seq 1 20); do
  herdr api snapshot >/dev/null 2>&1 && break
  sleep 0.5
done

EXISTING_WS="$(herdr api snapshot 2>/dev/null | jq -r '(.result.snapshot.workspaces[]? // .result.workspaces[]?) | select(.label == "factory") | .workspace_id' | head -n1 || true)"
if [ -n "$EXISTING_WS" ]; then
  echo "[launch-panes] Workspace 'factory' (${EXISTING_WS}) already running — attaching to Herdr UI..."
  exec herdr
fi

echo "[launch-panes] Bootstrapping native Herdr workspace 'factory' with 6 tabs..."

# 1. Create workspace + root tab for bridge
WS_JSON="$(herdr workspace create --cwd /workspace --label factory --focus)"
WS_ID="$(echo "$WS_JSON" | jq -r '.result.workspace.workspace_id')"
BRIDGE_TAB="$(echo "$WS_JSON" | jq -r '.result.tab.tab_id')"
BRIDGE_PANE="$(echo "$WS_JSON" | jq -r '.result.root_pane.pane_id')"
herdr tab rename "$BRIDGE_TAB" bridge >/dev/null
herdr pane rename "$BRIDGE_PANE" bridge >/dev/null
herdr pane run "$BRIDGE_PANE" "node /workspace/.factory/webhook-bridge.mjs" >/dev/null

# 2. Tab: architect (Chief Architect inside herdr-hub)
ARCH_TAB="$(herdr tab create --workspace "$WS_ID" --cwd /workspace --label architect --focus)"
ARCH_PANE="$(echo "$ARCH_TAB" | jq -r '.result.root_pane.pane_id')"
herdr pane rename "$ARCH_PANE" architect >/dev/null
herdr agent start architect --kind hermes --pane "$ARCH_PANE" -- --profile architect >/dev/null

# 3. Tab: orchestrator (Factory Orchestrator inside herdr-hub)
ORCH_TAB="$(herdr tab create --workspace "$WS_ID" --cwd /workspace --label orchestrator --no-focus)"
ORCH_PANE="$(echo "$ORCH_TAB" | jq -r '.result.root_pane.pane_id')"
herdr pane rename "$ORCH_PANE" orchestrator >/dev/null
herdr agent start orchestrator --kind hermes --pane "$ORCH_PANE" -- --profile orchestrator >/dev/null

# Helper: launch SSH agent tab with bash -lic (Fix A3) and unattended execution (Fix A4)
launch_ssh_agent_tab() {
  local name="$1"
  local kind="$2"
  local remote_cmd="$3"

  local tab_json pane_id
  tab_json="$(herdr tab create --workspace "$WS_ID" --cwd /workspace --label "$name" --no-focus)"
  pane_id="$(echo "$tab_json" | jq -r '.result.root_pane.pane_id')"
  herdr pane rename "$pane_id" "$name" >/dev/null
  # Wrap with bash -lic so .worker-env.sh and .bashrc are sourced cleanly on remote side (Fix A3)
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

# 3. Tab: worker-gemini (unattended mode Fix A4, kind=agy for native Herdr manifest)
launch_ssh_agent_tab "worker-gemini" "agy" "agy --mode=accept-edits"

# 4. Tab: worker-qwen (unattended --yolo Fix A4)
launch_ssh_agent_tab "worker-qwen" "hermes" "hermes --profile qwen --yolo"

# 5. Tab: senior-worker (unattended Hermes API relief worker)
launch_ssh_agent_tab "senior-worker" "hermes" "hermes --profile senior --yolo"

# 6. Tab: specialist-fable (unattended --dangerously-skip-permissions Fix A4)
FABLE_CMD="claude --dangerously-skip-permissions"
[ -n "${FABLE_MODEL:-}" ] && FABLE_CMD="claude --dangerously-skip-permissions --model \"${FABLE_MODEL}\""
launch_ssh_agent_tab "specialist-fable" "claude" "$FABLE_CMD"

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
