#!/usr/bin/env bash
set -euo pipefail

# 1. Configure internal SSH client for reaching worker containers
mkdir -p "$HOME/.ssh" "$HOME/.config/herdr/bridge-state"
chmod 700 "$HOME/.ssh"
cat <<'EOF' > "$HOME/.ssh/config"
Host worker-gemini worker-qwen senior-worker specialist-fable
  User factory
  Port 2222
  IdentityFile /run/factory-ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  ServerAliveInterval 30
  ServerAliveCountMax 3
EOF
chmod 600 "$HOME/.ssh/config"

# 2. Auto-sync Hermes Architect profile (Fix A12: declare api_key explicitly)
ARCH_MODEL="${ARCHITECT_MODEL:-glm-5.3}"
VIS_MODEL="${ARCHITECT_VISION_MODEL:-glm-5.3-flash}"
BACKUP_MODEL="${ARCHITECT_BACKUP_MODEL:-}"
PROXY_TOK="${ARCHITECT_PROXY_TOKEN:-proxy-architect-only}"

mkdir -p "$HOME/.hermes/profiles/architect"
cat <<EOF > "$HOME/.hermes/profiles/architect/config.yaml"
# Auto-generated on boot from compose.env
model:
  default: "${ARCH_MODEL}"
  provider: "custom"
  base_url: "http://llm-proxy:4000/glm"
  api_key: "${PROXY_TOK}"
auxiliary:
  vision:
    provider: "custom"
    model: "${VIS_MODEL}"
    base_url: "http://llm-proxy:4000/vision"
    api_key: "${PROXY_TOK}"
plugins:
  enabled:
    - herdr-agent-state
EOF

# Append native fallback provider if backup model is defined
if [ -n "$BACKUP_MODEL" ]; then
  cat <<EOF >> "$HOME/.hermes/profiles/architect/config.yaml"
fallback_providers:
  - provider: "custom"
    model: "${BACKUP_MODEL}"
    base_url: "http://llm-proxy:4000/backup"
    api_key: "${PROXY_TOK}"
EOF
fi

# Copy Herdr plugin into profile so Herdr receives native state rollups
if [ -d "$HOME/.hermes/plugins/herdr-agent-state" ]; then
  mkdir -p "$HOME/.hermes/profiles/architect/plugins"
  cp -r "$HOME/.hermes/plugins/herdr-agent-state" "$HOME/.hermes/profiles/architect/plugins/" 2>/dev/null || true
fi

cat <<EOF > "$HOME/.hermes/profiles/architect/.env"
OPENAI_API_KEY=${PROXY_TOK}
OPENAI_BASE_URL=http://llm-proxy:4000/glm
EOF
cp "$HOME/.hermes/profiles/architect/.env" "$HOME/.hermes/.env"
chmod 600 "$HOME/.hermes/.env" "$HOME/.hermes/profiles/architect/.env"

# 2b. Auto-sync Hermes Orchestrator profile inside herdr-hub
SEN_MODEL="${SENIOR_MODEL:-gemini-4-neon}"
SEN_TOK="${SENIOR_PROXY_TOKEN:-proxy-senior-only}"

mkdir -p "$HOME/.hermes/profiles/orchestrator"
cat <<EOF > "$HOME/.hermes/profiles/orchestrator/config.yaml"
# Auto-generated on boot from compose.env
model:
  default: "${SEN_MODEL}"
  provider: "custom"
  base_url: "http://llm-proxy:4000/senior"
  api_key: "${SEN_TOK}"
  context_length: 64000
plugins:
  enabled:
    - herdr-agent-state
EOF

if [ -d "$HOME/.hermes/plugins/herdr-agent-state" ]; then
  mkdir -p "$HOME/.hermes/profiles/orchestrator/plugins"
  cp -r "$HOME/.hermes/plugins/herdr-agent-state" "$HOME/.hermes/profiles/orchestrator/plugins/" 2>/dev/null || true
fi

cat <<EOF > "$HOME/.hermes/profiles/orchestrator/.env"
OPENAI_API_KEY=${SEN_TOK}
OPENAI_BASE_URL=http://llm-proxy:4000/senior
EOF
chmod 600 "$HOME/.hermes/profiles/orchestrator/.env"

# 3. Bootstrap isolated /workspace repo clone
/usr/local/bin/bootstrap-workspace.sh
if [ -f /workspace/.factory/enter-role.sh ]; then
  source /workspace/.factory/enter-role.sh architect
  [ -x /workspace/.factory/sync-hub.sh ] && /workspace/.factory/sync-hub.sh || true
fi
if [ -x /workspace/.factory/sync-skills.sh ]; then
  /workspace/.factory/sync-skills.sh architect
fi

echo "[herdr-hub] Starting headless Herdr server (Architect=${ARCH_MODEL}, Vision=${VIS_MODEL})..."
exec herdr server
