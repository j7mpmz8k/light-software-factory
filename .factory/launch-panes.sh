#!/usr/bin/env bash
# Usage: docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh
set -euo pipefail

source /workspace/.factory/enter-role.sh architect
/workspace/.factory/sync-hub.sh || true

for _ in $(seq 1 20); do
  herdr api snapshot >/dev/null 2>&1 && break
  sleep 0.5
done

EXISTING_WS="$(herdr api snapshot | jq -r '.result.workspaces[]? | select(.label == "factory") | .workspace_id' | head -n1 || true)"
if [ -n "$EXISTING_WS" ]; then
  echo "[launch-panes] Workspace 'factory' (${EXISTING_WS}) already running — attaching to Herdr UI..."
  exec herdr
fi

echo "[launch-panes] Bootstrapping native Herdr workspace 'factory' with 5 tabs..."

# 1. Create workspace + root tab for bridge
WS_JSON="$(herdr workspace create --cwd /workspace --label factory --focus)"
WS_ID="$(echo "$WS_JSON" | jq -r '.result.workspace.workspace_id')"
BRIDGE_TAB="$(echo "$WS_JSON" | jq -r '.result.tab.tab_id')"
BRIDGE_PANE="$(echo "$WS_JSON" | jq -r '.result.root_pane.pane_id')"
herdr tab rename "$BRIDGE_TAB" bridge >/dev/null
herdr pane rename "$BRIDGE_PANE" bridge >/dev/null
herdr pane run "$BRIDGE_PANE" "node /workspace/.factory/webhook-bridge.mjs" >/dev/null

# 2. Tab: architect
ARCH_TAB="$(herdr tab create --workspace "$WS_ID" --cwd /workspace --label architect --focus)"
ARCH_PANE="$(echo "$ARCH_TAB" | jq -r '.result.root_pane.pane_id')"
herdr pane rename "$ARCH_PANE" architect >/dev/null
herdr agent start architect --kind hermes --pane "$ARCH_PANE" -- --profile architect >/dev/null

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

# 3. Tab: worker-gemini (unattended mode Fix A4)
launch_ssh_agent_tab "worker-gemini" "antigravity-cli" "agy --mode=accept-edits"

# 4. Tab: worker-qwen (unattended --yolo Fix A4)
launch_ssh_agent_tab "worker-qwen" "hermes" "hermes --profile qwen --yolo"

# 5. Tab: specialist-fable (unattended --dangerously-skip-permissions Fix A4)
FABLE_CMD="claude --dangerously-skip-permissions"
[ -n "${FABLE_MODEL:-}" ] && FABLE_CMD="claude --dangerously-skip-permissions --model \"${FABLE_MODEL}\""
launch_ssh_agent_tab "specialist-fable" "claude" "$FABLE_CMD"

echo "[launch-panes] Waiting for 'architect' to reach idle and seeding..."
if herdr agent wait architect --until idle --until done --timeout 30000 >/dev/null 2>&1; then
  herdr agent prompt architect "$(cat /workspace/.factory/architect-seed.md)" >/dev/null || true
fi

echo "[launch-panes] Native Herdr agents active:"
herdr agent list || true
exec herdr
