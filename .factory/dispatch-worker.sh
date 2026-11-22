#!/usr/bin/env bash
# Usage: .factory/dispatch-worker.sh <worker_name> <sub_issue_prompt>
set -euo pipefail

WORKER_NAME="${1:-}"
PROMPT="${2:-}"

if [ -z "$WORKER_NAME" ] || [ -z "$PROMPT" ]; then
  echo "Usage: $0 <worker_name> <sub_issue_prompt>" >&2
  exit 1
fi

echo "[dispatch-worker] Wiping LLM context memory for ${WORKER_NAME}..."
# Send /clear to wipe conversational memory while preserving active REPL
herdr agent send-keys "$WORKER_NAME" "/clear" "Enter" 2>/dev/null || true
sleep 1

echo "[dispatch-worker] Dispatching fresh Sub-Issue prompt to ${WORKER_NAME}..."
herdr agent prompt "$WORKER_NAME" "$PROMPT"
