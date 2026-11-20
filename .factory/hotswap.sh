#!/usr/bin/env bash
# Usage:
#   .factory/hotswap.sh architect <model_name> [vision_model_name]
#   .factory/hotswap.sh qwen <model_name> [inference_url]
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

  qwen)
    NEW_MODEL="${2:?Worker model name required (e.g. qwen3.8:27b, codellama)}"
    NEW_URL="${3:-}"
    sed -i "s/^QWEN_MODEL=.*/QWEN_MODEL=${NEW_MODEL}/" "$COMPOSE_ENV"
    [ -n "$NEW_URL" ] && sed -i "s|^QWEN_INFERENCE_URL=.*|QWEN_INFERENCE_URL=${NEW_URL}|" "$COMPOSE_ENV"
    echo "[hotswap] Updated Qwen worker model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" restart worker-qwen
    echo "[hotswap] Restarted worker-qwen with new model."
    ;;

  fable)
    NEW_MODEL="${2:?Fable model name required (e.g. claude-3-7-sonnet-20250219)}"
    sed -i "s/^FABLE_MODEL=.*/FABLE_MODEL=${NEW_MODEL}/" "$COMPOSE_ENV"
    echo "[hotswap] Updated Fable model in compose.env -> ${NEW_MODEL}"
    docker compose --env-file "$COMPOSE_ENV" restart specialist-fable
    echo "[hotswap] Restarted specialist-fable."
    ;;

  *)
    echo "Usage: $0 <architect|qwen|fable> <model_name> [optional_url_or_vision]" >&2
    exit 1
    ;;
esac
