#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${HOME}/.config/light-factory"

# Auto-detect rootless Podman socket if DOCKER_HOST is not explicitly set
USER_ID="$(id -u)"
if [ -z "${DOCKER_HOST:-}" ] && [ -S "/run/user/${USER_ID}/podman/podman.sock" ]; then
  export DOCKER_HOST="unix:///run/user/${USER_ID}/podman/podman.sock"
fi

REQUIRED_FILES=(
  "${CONFIG_DIR}/apps.env"
  "${CONFIG_DIR}/llm-secrets.env"
  "${CONFIG_DIR}/bridge.env"
  "${CONFIG_DIR}/compose.env"
  "${CONFIG_DIR}/keys/architect.pem"
  "${CONFIG_DIR}/keys/worker.pem"
  "${CONFIG_DIR}/internal-ssh/id_ed25519"
  "${CONFIG_DIR}/internal-ssh/authorized_keys"
)

FAIL=0
echo "[preflight] Checking host secret vault in ${CONFIG_DIR}..."

for f in "${REQUIRED_FILES[@]}"; do
  if [ -d "$f" ]; then
    echo "  ❌ ${f} is a DIRECTORY. Remove with 'rm -rf \"${f}\"' and create the file." >&2
    FAIL=1
  elif [ ! -f "$f" ] || [ ! -s "$f" ]; then
    echo "  ❌ Missing or empty required file: ${f}" >&2
    FAIL=1
  else
    echo "  ✅ ${f}"
  fi
done

# Check strict permissions on private keys
for keyfile in "${CONFIG_DIR}/keys/architect.pem" "${CONFIG_DIR}/keys/worker.pem" "${CONFIG_DIR}/internal-ssh/id_ed25519"; do
  if [ -f "$keyfile" ]; then
    PERM="$(stat -c '%a' "$keyfile" 2>/dev/null || stat -f '%Lp' "$keyfile" 2>/dev/null || echo "")"
    if [ -n "$PERM" ] && [ "$PERM" != "600" ] && [ "$PERM" != "400" ]; then
      echo "  ❌ Private key ${keyfile} has insecure permissions (${PERM}). Fix with: chmod 600 \"${keyfile}\"" >&2
      FAIL=1
    fi
  fi
done

# Detect leftover template placeholders in vault files
for cfg in "${CONFIG_DIR}/apps.env" "${CONFIG_DIR}/llm-secrets.env" "${CONFIG_DIR}/bridge.env" "${CONFIG_DIR}/compose.env"; do
  if [ -f "$cfg" ] && grep -qE '<paste_|your_glm_api_key_here|your_github_username|your_repo_name|your_webhook_secret_here|change_this_' "$cfg"; then
    echo "  ❌ Template placeholder still present in ${cfg} — replace with real values." >&2
    FAIL=1
  fi
done

# Check repo CODEOWNERS placeholder
if [ -f "${REPO_DIR}/.github/CODEOWNERS" ] && grep -q '<YOUR_GITHUB_USERNAME>' "${REPO_DIR}/.github/CODEOWNERS"; then
  echo "  ❌ Placeholder '<YOUR_GITHUB_USERNAME>' still present in .github/CODEOWNERS." >&2
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  echo "[preflight] FAILED — fix the items above before running docker compose up." >&2
  exit 1
fi

echo "[preflight] Validating docker-compose.yml syntax..."
(cd "$REPO_DIR" && docker compose --env-file "${CONFIG_DIR}/compose.env" config -q)
echo "[preflight] ✅ All host files, key permissions, secrets, and Compose configuration verified!"
