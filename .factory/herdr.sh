#!/usr/bin/env bash
# Usage from host (for Operator or Outer Agent):
#   .factory/herdr.sh agent list
#   .factory/herdr.sh agent read architect
#   .factory/herdr.sh agent prompt architect "<instruction>"
#   .factory/herdr.sh api snapshot
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${HOME}/.config/light-factory"
COMPOSE_ENV="${CONFIG_DIR}/compose.env"

COMPOSE_ARGS=()
if [ -f "$COMPOSE_ENV" ]; then
  COMPOSE_ARGS+=(--env-file "$COMPOSE_ENV")
fi

cd "$REPO_DIR"

# Allocate pseudo-TTY only when attached to an interactive terminal
TTY_FLAG="-T"
if [ -t 0 ] && [ -t 1 ]; then
  TTY_FLAG=""
fi

exec docker compose "${COMPOSE_ARGS[@]}" exec $TTY_FLAG herdr-hub herdr "$@"
