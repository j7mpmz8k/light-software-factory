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

write_worker_soul() {
  local soul_path="$1"
  cat <<'SOULEOF' > "$soul_path"
You are an isolated Execution Builder in the Light Software Factory.
Your workspace is /workspace and your dedicated PostgreSQL database is $DATABASE_URL.
Mandatory rules before and during every Sub-Issue:
1. Read AGENTS.md and GLOSSARY.md before writing code or database schemas.
2. Run `.factory/prep-branch.sh <issue_num_or_branch> [slug]` to reset your branch, public DB schema, dependencies, and skills cleanly.
3. Follow strict Red -> Green -> Refactor TDD (skill: tdd) and Deep Modules (skill: domain-modeling). Never weaken or delete tests.
4. Open one atomic PR targeting `staging` (never `main` or `master`) referencing `Closes #<sub_issue_num>` with test output and evidence.
SOULEOF
}

# Pre-seed Antigravity CLI workspace trust & credit guard for unattended execution in worker-agy
if [ "${WORKER_NAME:-}" = "worker-agy" ]; then
  AGY_SETTINGS_DIR="$HOME/.gemini/antigravity-cli"
  AGY_SETTINGS_FILE="${AGY_SETTINGS_DIR}/settings.json"
  mkdir -p "$AGY_SETTINGS_DIR"
  if [ -s "$AGY_SETTINGS_FILE" ] && jq empty "$AGY_SETTINGS_FILE" >/dev/null 2>&1; then
    TMP_SETTINGS="${AGY_SETTINGS_FILE}.tmp.$$"
    jq '
      .trustedWorkspaces = (((.trustedWorkspaces // []) + ["/workspace"]) | unique)
      | .useG1Credits = (.useG1Credits // false)
    ' "$AGY_SETTINGS_FILE" > "$TMP_SETTINGS" && mv "$TMP_SETTINGS" "$AGY_SETTINGS_FILE"
  else
    cat <<'EOF' > "$AGY_SETTINGS_FILE"
{
  "trustedWorkspaces": [
    "/workspace"
  ],
  "useG1Credits": false
}
EOF
  fi
  chmod 600 "$AGY_SETTINGS_FILE"
  echo "[worker-agy] Verified /workspace trust and credit guard in ${AGY_SETTINGS_FILE}"
fi

# Configure Local Qwen GPU worker (enforce >= 64,000 context floor)
if [ "${WORKER_NAME:-}" = "worker-qwen" ]; then
  QWEN_URL="${QWEN_INFERENCE_URL:-http://host.docker.internal:11434/v1}"
  QWEN_MOD="${QWEN_MODEL:-qwen3.8:27b}"
  QWEN_KEY="${QWEN_API_KEY:-local-not-needed}"

  mkdir -p "$HOME/.hermes/profiles/qwen"
  write_worker_soul "$HOME/.hermes/profiles/qwen/SOUL.md"
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
  write_worker_soul "$HOME/.hermes/profiles/glm/SOUL.md"
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
