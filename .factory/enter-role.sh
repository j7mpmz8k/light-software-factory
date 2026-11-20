#!/usr/bin/env bash
# Usage: source /workspace/.factory/enter-role.sh <architect|worker>

ROLE="${1:-${FACTORY_ROLE:-}}"
if [ "$ROLE" != "architect" ] && [ "$ROLE" != "worker" ]; then
  echo "Usage: source .factory/enter-role.sh <architect|worker>" >&2
  return 1 2>/dev/null || exit 1
fi

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_ROOT="${FACTORY_AUTH_ROOT:-/run/factory-auth}"
META_FILE="${AUTH_ROOT}/${ROLE}/meta.json"

export FACTORY_ROLE="$ROLE"
export FACTORY_AUTH_ROOT="$AUTH_ROOT"
export GH_CONFIG_DIR="/tmp/factory-gh-config-${ROLE}"
mkdir -p "$GH_CONFIG_DIR"

case ":${PATH}:" in
  *":${FACTORY_DIR}/bin:"*) ;;
  *) export PATH="${FACTORY_DIR}/bin:${PATH}" ;;
esac

# Force HTTPS App-token auth for git (never personal SSH keys)
export GIT_SSH_COMMAND="/bin/false"
export GIT_TERMINAL_PROMPT="0"
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0="credential.helper"
export GIT_CONFIG_VALUE_0=""
export GIT_CONFIG_KEY_1="credential.helper"
export GIT_CONFIG_VALUE_1="!${FACTORY_DIR}/git-credential-factory.sh"

# Attribute commits cleanly to the GitHub App bot identity using bot user ID (Fix enter-role email)
if [ -r "$META_FILE" ] && command -v jq >/dev/null 2>&1; then
  BOT_SLUG="$(jq -r '.slug // empty' "$META_FILE")"
  USER_ID="$(jq -r '.userId // .appId // empty' "$META_FILE")"
  if [ -n "$BOT_SLUG" ] && [ -n "$USER_ID" ]; then
    export GIT_AUTHOR_NAME="${BOT_SLUG}[bot]"
    export GIT_COMMITTER_NAME="${BOT_SLUG}[bot]"
    export GIT_AUTHOR_EMAIL="${USER_ID}+${BOT_SLUG}[bot]@users.noreply.github.com"
    export GIT_COMMITTER_EMAIL="${USER_ID}+${BOT_SLUG}[bot]@users.noreply.github.com"
  fi
fi
