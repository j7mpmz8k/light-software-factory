#!/usr/bin/env bash
# Usage:
#   .factory/hotswap.sh architect <model_name> [vision_model_name]
#   .factory/hotswap.sh backup <model_name> [backup_upstream_url]
#   .factory/hotswap.sh qwen <model_name> [inference_url]
#   .factory/hotswap.sh senior <model_name> [senior_upstream_url]
#   .factory/hotswap.sh fable <model_name>
set -euo pipefail

TARGET="${1:-}"
CONFIG_DIR="${HOME}/.config/light-factory"
COMPOSE_ENV="${CONFIG_DIR}/compose.env"

if [ ! -f "$COMPOSE_ENV" ]; then
  echo "Error: ${COMPOSE_ENV} not found." >&2
  exit 1
fi

case "$TARGET" in
  architect)
    NEW_MODEL="${2:?Architect model name required (e.g. glm-5.3, deepseek-coder)}"
    NEW_VIS="${3:-}"
    sed -i "s/^ARCHITECT_MODEL=.*/ARCHITECT_MODEL=${NEW_MODEL}/" "$COMPOSE_ENV"
    [ -n "$NEW_VIS" ] && sed -i "s/^ARCHITECT_VISION_MODEL=.*/ARCHITECT_VISION_MODEL=${NEW_VIS}/" "$COMPOSE_ENV"
    echo "[hotswap] Updated Architect model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" up -d --force-recreate llm-proxy herdr-hub
    echo "[hotswap] Recreated llm-proxy & herdr-hub with new model."
    ;;

  backup)
    NEW_MODEL="${2:?Backup model name required (e.g. deepseek-chat, qwen2.5-coder:32b)}"
    NEW_URL="${3:-}"
    if grep -q "^ARCHITECT_BACKUP_MODEL=" "$COMPOSE_ENV"; then
      sed -i "s/^ARCHITECT_BACKUP_MODEL=.*/ARCHITECT_BACKUP_MODEL=${NEW_MODEL}/" "$COMPOSE_ENV"
    else
      echo "ARCHITECT_BACKUP_MODEL=${NEW_MODEL}" >> "$COMPOSE_ENV"
    fi
    if [ -n "$NEW_URL" ]; then
      if grep -q "^BACKUP_UPSTREAM_URL=" "$COMPOSE_ENV"; then
        sed -i "s|^BACKUP_UPSTREAM_URL=.*|BACKUP_UPSTREAM_URL=${NEW_URL}|" "$COMPOSE_ENV"
      else
        echo "BACKUP_UPSTREAM_URL=${NEW_URL}" >> "$COMPOSE_ENV"
      fi
    fi
    echo "[hotswap] Updated Architect backup model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" up -d --force-recreate llm-proxy herdr-hub
    echo "[hotswap] Recreated llm-proxy & herdr-hub with backup model enabled."
    ;;

  qwen)
    NEW_MODEL="${2:?Worker model name required (e.g. qwen3.8:27b, codellama)}"
    NEW_URL="${3:-}"
    sed -i "s/^QWEN_MODEL=.*/QWEN_MODEL=${NEW_MODEL}/" "$COMPOSE_ENV"
    [ -n "$NEW_URL" ] && sed -i "s|^QWEN_INFERENCE_URL=.*|QWEN_INFERENCE_URL=${NEW_URL}|" "$COMPOSE_ENV"
    echo "[hotswap] Updated Qwen worker model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" restart worker-qwen
    echo "[hotswap] Restarted worker-qwen with new model."
    ;;

  senior)
    NEW_MODEL="${2:?Senior worker model required (e.g. gemini-4-neon, deepseek-chat, o3-mini)}"
    NEW_URL="${3:-}"
    if grep -q "^SENIOR_MODEL=" "$COMPOSE_ENV"; then
      sed -i "s/^SENIOR_MODEL=.*/SENIOR_MODEL=${NEW_MODEL}/" "$COMPOSE_ENV"
    else
      echo "SENIOR_MODEL=${NEW_MODEL}" >> "$COMPOSE_ENV"
    fi
    if [ -n "$NEW_URL" ]; then
      if grep -q "^SENIOR_UPSTREAM_URL=" "$COMPOSE_ENV"; then
        sed -i "s|^SENIOR_UPSTREAM_URL=.*|SENIOR_UPSTREAM_URL=${NEW_URL}|" "$COMPOSE_ENV"
      else
        echo "SENIOR_UPSTREAM_URL=${NEW_URL}" >> "$COMPOSE_ENV"
      fi
    fi
    echo "[hotswap] Updated Senior Worker model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" restart senior-worker
    echo "[hotswap] Restarted senior-worker with new model."
    ;;

  fable)
    NEW_MODEL="${2:?Fable model name required (e.g. claude-3-7-sonnet-20250219)}"
    sed -i "s/^FABLE_MODEL=.*/FABLE_MODEL=${NEW_MODEL}/" "$COMPOSE_ENV"
    echo "[hotswap] Updated Fable model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" restart specialist-fable
    echo "[hotswap] Restarted specialist-fable."
    ;;

  *)
    echo "Usage: $0 <architect|backup|qwen|senior|fable> <model_name> [optional_url_or_vision]" >&2
    exit 1
    ;;
esac
