#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${HOME}/.config/light-factory"
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

for cfg in "${CONFIG_DIR}/apps.env" "${CONFIG_DIR}/llm-secrets.env"; do
  if [ -f "$cfg" ] && grep -q '<paste_' "$cfg"; then
    echo "  ❌ Placeholder '<paste_...>' still present in ${cfg}" >&2
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "[preflight] FAILED — fix the items above before running docker compose up." >&2
  exit 1
fi

echo "[preflight] Validating docker-compose.yml syntax..."
docker compose --env-file "${CONFIG_DIR}/compose.env" config -q
echo "[preflight] ✅ All host files, secrets, and Compose configuration verified!"
