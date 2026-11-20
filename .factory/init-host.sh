#!/usr/bin/env bash
# Initialize the host directory structure and internal SSH keys for Light Software Factory
set -euo pipefail

CONFIG_DIR="${HOME}/.config/light-factory"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

echo "=== Initializing Light Software Factory Host Environment ==="

mkdir -p "${CONFIG_DIR}/keys" "${CONFIG_DIR}/internal-ssh"
chmod 700 "${CONFIG_DIR}" "${CONFIG_DIR}/keys" "${CONFIG_DIR}/internal-ssh"
echo "✅ Created secure directory tree at ${CONFIG_DIR}"

# 1. Generate internal SSH keypair if not present
INTERNAL_KEY="${CONFIG_DIR}/internal-ssh/id_ed25519"
AUTH_KEYS="${CONFIG_DIR}/internal-ssh/authorized_keys"

if [ ! -f "$INTERNAL_KEY" ]; then
  echo "Generating dedicated internal container SSH keypair..."
  ssh-keygen -t ed25519 -N "" -C "herdr-hub-internal" -f "$INTERNAL_KEY" >/dev/null
  cp "${INTERNAL_KEY}.pub" "$AUTH_KEYS"
  chmod 600 "$INTERNAL_KEY"
  chmod 644 "$AUTH_KEYS"
  echo "✅ Internal SSH keypair generated."
else
  echo "ℹ️ Internal SSH keypair already exists."
fi

echo ""
echo "=== Next Steps for Setup ==="
echo "1. Place your GitHub App private keys in:"
echo "   ${CONFIG_DIR}/keys/architect.pem"
echo "   ${CONFIG_DIR}/keys/worker.pem"
echo ""
echo "2. Create your configuration files by referencing templates in .factory/templates/:"
echo "   cp .factory/templates/apps.example        ${CONFIG_DIR}/apps.env"
echo "   cp .factory/templates/llm-secrets.example ${CONFIG_DIR}/llm-secrets.env"
echo "   cp .factory/templates/compose.example    ${CONFIG_DIR}/compose.env"
echo "   cp .factory/templates/bridge.example     ${CONFIG_DIR}/bridge.env"
echo ""
echo "3. Edit those files with your GitHub App IDs, repository name, and API keys."
echo ""
echo "4. Verify everything is green with:"
echo "   ./.factory/preflight.sh"
echo "==========================================================="
