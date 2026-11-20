#!/usr/bin/env bash
set -euo pipefail

ROLE="${FACTORY_ROLE:?FACTORY_ROLE is required}"
REPO_FULL="${FACTORY_REPO:?FACTORY_REPO is required (owner/repo)}"
AUTH_ROOT="${FACTORY_AUTH_ROOT:-/run/factory-auth}"
TOKEN_FILE="${AUTH_ROOT}/${ROLE}/token"

echo "[bootstrap] Waiting for 1h token at ${TOKEN_FILE}..."
for _ in $(seq 1 60); do
  [ -s "$TOKEN_FILE" ] && break
  sleep 1
done

if [ ! -s "$TOKEN_FILE" ]; then
  echo "[bootstrap] ERROR: Timed out waiting for ${TOKEN_FILE}" >&2
  exit 1
fi

if [ ! -d /workspace/.git ]; then
  echo "[bootstrap] Cloning ${REPO_FULL} (staging) into isolated /workspace..."
  TOKEN="$(cat "$TOKEN_FILE")"
  git clone --branch staging "https://x-access-token:${TOKEN}@github.com/${REPO_FULL}.git" /workspace
  git -C /workspace remote set-url origin "https://github.com/${REPO_FULL}.git"
fi

grep -Fq "enter-role.sh" "$HOME/.bashrc" 2>/dev/null || cat <<'EOF' >> "$HOME/.bashrc"
[ -f "$HOME/.worker-env.sh" ] && source "$HOME/.worker-env.sh"
if [ -f /workspace/.factory/enter-role.sh ]; then
  source /workspace/.factory/enter-role.sh "${FACTORY_ROLE}"
fi
cd /workspace 2>/dev/null || true
EOF

echo "[bootstrap] /workspace ready for role=${ROLE}."
