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
  echo "[bootstrap] Cloning ${REPO_FULL} into isolated /workspace..."
  TOKEN="$(cat "$TOKEN_FILE")"
  CLEAN_URL="https://github.com/${REPO_FULL}.git"
  BASIC_B64="$(printf 'x-access-token:%s' "$TOKEN" | base64 | tr -d '\r\n')"
  GIT_AUTH_ENV=(
    GIT_TERMINAL_PROMPT=0
    GIT_CONFIG_COUNT=1
    GIT_CONFIG_KEY_0="http.https://github.com/.extraheader"
    GIT_CONFIG_VALUE_0="AUTHORIZATION: basic ${BASIC_B64}"
  )

  if ! env "${GIT_AUTH_ENV[@]}" git clone --branch staging "$CLEAN_URL" /workspace 2>/dev/null; then
    echo "[bootstrap] Note: 'staging' branch not found on remote; cloning default branch and initializing staging..."
    env "${GIT_AUTH_ENV[@]}" git clone "$CLEAN_URL" /workspace
    git -C /workspace checkout -b staging 2>/dev/null || git -C /workspace checkout staging
    if [ "$ROLE" = "architect" ]; then
      echo "[bootstrap] Pushing initial 'staging' branch to origin..."
      env "${GIT_AUTH_ENV[@]}" git -C /workspace push -u origin staging || echo "[bootstrap] WARNING: Could not auto-push initial staging branch." >&2
    fi
  fi
  git -C /workspace remote set-url origin "$CLEAN_URL"
fi

grep -Fq "enter-role.sh" "$HOME/.bashrc" 2>/dev/null || cat <<'EOF' >> "$HOME/.bashrc"
[ -f "$HOME/.worker-env.sh" ] && source "$HOME/.worker-env.sh"
if [ -f /workspace/.factory/enter-role.sh ]; then
  source /workspace/.factory/enter-role.sh "${FACTORY_ROLE}"
fi
cd /workspace 2>/dev/null || true
EOF

# Ensure login shells (`bash -lic`) also source ~/.bashrc so DATABASE_URL & enter-role.sh always load
grep -Fq ".bashrc" "$HOME/.bash_profile" 2>/dev/null || cat <<'EOF' >> "$HOME/.bash_profile"
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
EOF

echo "[bootstrap] /workspace ready for role=${ROLE}."
