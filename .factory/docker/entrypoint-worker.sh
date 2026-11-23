#!/usr/bin/env bash
set -euo pipefail

cat <<EOF > "$HOME/.worker-env.sh"
export WORKER_NAME="${WORKER_NAME:-worker}"
export FACTORY_ROLE="${FACTORY_ROLE:-worker}"
export FACTORY_AUTH_ROOT="${FACTORY_AUTH_ROOT:-/run/factory-auth}"
export FACTORY_REPO="${FACTORY_REPO:-}"
export DATABASE_URL="${DATABASE_URL:-}"
export PLAYWRIGHT_BROWSERS_PATH="/home/factory/.cache/ms-playwright"
EOF
chmod 600 "$HOME/.worker-env.sh"

/usr/local/bin/bootstrap-workspace.sh

if [ -x /workspace/.factory/sync-skills.sh ] && [ -n "${WORKER_NAME:-}" ]; then
  /workspace/.factory/sync-skills.sh "$WORKER_NAME"
fi

# Configure Local Qwen GPU worker (enforce >= 64,000 context floor)
if [ "${WORKER_NAME:-}" = "worker-qwen" ]; then
  QWEN_URL="${QWEN_INFERENCE_URL:-http://host.docker.internal:11434/v1}"
  QWEN_MOD="${QWEN_MODEL:-qwen3.8:27b}"
  QWEN_KEY="${QWEN_API_KEY:-local-not-needed}"

  mkdir -p "$HOME/.hermes/profiles/qwen"
  cat <<EOF > "$HOME/.hermes/profiles/qwen/config.yaml"
model:
  default: "${QWEN_MOD}"
  provider: "custom"
  base_url: "${QWEN_URL}"
  api_key: "${QWEN_KEY}"
  context_length: 64000
EOF
  cat <<EOF > "$HOME/.hermes/profiles/qwen/.env"
OPENAI_API_KEY=${QWEN_KEY}
OPENAI_BASE_URL=${QWEN_URL}
EOF
  cp "$HOME/.hermes/profiles/qwen/.env" "$HOME/.hermes/.env"
  chmod 600 "$HOME/.hermes/.env" "$HOME/.hermes/profiles/qwen/.env"
  echo "[worker-qwen] Configured Hermes -> ${QWEN_MOD} (64k context) @ ${QWEN_URL}"
fi

# Configure GLM-5.3 Backup / Overflow worker (isolated proxy route & spend cap)
if [ "${WORKER_NAME:-}" = "worker-glm" ]; then
  GLM_URL="${GLM_WORKER_INFERENCE_URL:-http://llm-proxy:4000/worker-glm}"
  GLM_MOD="${GLM_WORKER_MODEL:-glm-5.3}"
  GLM_KEY="${GLM_WORKER_API_KEY:-proxy-worker-glm-only}"

  mkdir -p "$HOME/.hermes/profiles/glm"
  cat <<EOF > "$HOME/.hermes/profiles/glm/config.yaml"
model:
  default: "${GLM_MOD}"
  provider: "custom"
  base_url: "${GLM_URL}"
  api_key: "${GLM_KEY}"
  context_length: 64000
EOF
  cat <<EOF > "$HOME/.hermes/profiles/glm/.env"
OPENAI_API_KEY=${GLM_KEY}
OPENAI_BASE_URL=${GLM_URL}
EOF
  cp "$HOME/.hermes/profiles/glm/.env" "$HOME/.hermes/.env"
  chmod 600 "$HOME/.hermes/.env" "$HOME/.hermes/profiles/glm/.env"
  echo "[worker-glm] Configured Hermes -> ${GLM_MOD} (64k context) @ ${GLM_URL}"
fi

HOST_KEY="/tmp/ssh_host_ed25519_key"
[ -f "$HOST_KEY" ] || ssh-keygen -t ed25519 -N "" -f "$HOST_KEY" >/dev/null

cat <<EOF > /tmp/sshd_config
Port 2222
ListenAddress 0.0.0.0
HostKey ${HOST_KEY}
PidFile /tmp/sshd.pid
AuthorizedKeysFile /run/factory-ssh/authorized_keys
StrictModes no
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers factory
AllowTcpForwarding no
X11Forwarding no
PrintMotd no
Subsystem sftp internal-sftp
EOF

echo "[worker:${WORKER_NAME:-worker}] Starting non-root sshd on internal port 2222..."
exec /usr/sbin/sshd -D -e -f /tmp/sshd_config
