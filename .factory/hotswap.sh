#!/usr/bin/env bash
# Usage:
#   .factory/hotswap.sh architect <model_name> [vision_model_name]
#   .factory/hotswap.sh orchestrator <model_name>
#   .factory/hotswap.sh backup <model_name> [backup_upstream_url]
#   .factory/hotswap.sh qwen <model_name> [inference_url]
#   .factory/hotswap.sh glm <model_name>
#   .factory/hotswap.sh agy-default <model_name>
set -euo pipefail

TARGET="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${HOME}/.config/light-factory"
COMPOSE_ENV="${CONFIG_DIR}/compose.env"

if [ ! -f "$COMPOSE_ENV" ]; then
  echo "Error: ${COMPOSE_ENV} not found." >&2
  exit 1
fi

cd "$REPO_DIR"

# Auto-detect rootless Podman socket & keep-id user namespace mapping if DOCKER_HOST is not explicitly set
USER_ID="$(id -u)"
if [ -z "${DOCKER_HOST:-}" ] && [ -S "/run/user/${USER_ID}/podman/podman.sock" ]; then
  export DOCKER_HOST="unix:///run/user/${USER_ID}/podman/podman.sock"
  export FACTORY_USERNS_MODE="${FACTORY_USERNS_MODE:-keep-id}"
fi

set_env_var() {
  local key="$1"
  local val="$2"
  local tmp_file="${COMPOSE_ENV}.tmp.$$"
  awk -v k="$key" -v v="$val" '
    BEGIN { updated = 0 }
    index($0, k "=") == 1 {
      print k "=" v
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) print k "=" v
    }
  ' "$COMPOSE_ENV" > "$tmp_file"
  chmod 600 "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$COMPOSE_ENV"
}

case "$TARGET" in
  architect)
    NEW_MODEL="${2:?Architect model name required (e.g. glm-5.3)}"
    NEW_VIS="${3:-}"
    set_env_var "ARCHITECT_MODEL" "$NEW_MODEL"
    [ -n "$NEW_VIS" ] && set_env_var "ARCHITECT_VISION_MODEL" "$NEW_VIS"
    echo "[hotswap] Updated Architect model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" up -d --force-recreate llm-proxy herdr-hub
    echo "[hotswap] Recreated llm-proxy & herdr-hub with new model."
    ;;

  orchestrator)
    NEW_MODEL="${2:?Orchestrator model name required (e.g. glm-5.3)}"
    set_env_var "ORCHESTRATOR_MODEL" "$NEW_MODEL"
    echo "[hotswap] Updated Orchestrator model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" up -d --force-recreate llm-proxy herdr-hub
    echo "[hotswap] Recreated llm-proxy & herdr-hub with new Orchestrator model."
    ;;

  backup)
    NEW_MODEL="${2:?Backup model name required (e.g. deepseek-chat, qwen2.5-coder:32b)}"
    NEW_URL="${3:-}"
    set_env_var "ARCHITECT_BACKUP_MODEL" "$NEW_MODEL"
    [ -n "$NEW_URL" ] && set_env_var "BACKUP_UPSTREAM_URL" "$NEW_URL"
    echo "[hotswap] Updated Hub backup model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" up -d --force-recreate llm-proxy herdr-hub
    echo "[hotswap] Recreated llm-proxy & herdr-hub with backup model enabled."
    ;;

  qwen)
    NEW_MODEL="${2:?Qwen model name required (e.g. qwen3.8:27b)}"
    NEW_URL="${3:-}"
    set_env_var "QWEN_MODEL" "$NEW_MODEL"
    [ -n "$NEW_URL" ] && set_env_var "QWEN_INFERENCE_URL" "$NEW_URL"
    echo "[hotswap] Updated Qwen worker model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" restart worker-qwen
    echo "[hotswap] Restarted worker-qwen with new model."
    ;;

  glm)
    NEW_MODEL="${2:?GLM worker model required (e.g. glm-5.3)}"
    set_env_var "GLM_WORKER_MODEL" "$NEW_MODEL"
    echo "[hotswap] Updated worker-glm model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" up -d --force-recreate llm-proxy worker-glm
    echo "[hotswap] Recreated llm-proxy & worker-glm with new model."
    ;;

  agy-default)
    NEW_MODEL="${2:?Default AGY model required (e.g. gemini-4-hydrogen-high, gemini-4-neon-high)}"
    set_env_var "AGY_DEFAULT_MODEL" "$NEW_MODEL"
    echo "[hotswap] Updated AGY default model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" up -d --force-recreate herdr-hub
    echo "[hotswap] Recreated herdr-hub with new AGY_DEFAULT_MODEL."
    ;;

  *)
    echo "Usage: $0 <architect|orchestrator|backup|qwen|glm|agy-default> <model_name> [optional_url_or_vision]" >&2
    exit 1
    ;;
esac
