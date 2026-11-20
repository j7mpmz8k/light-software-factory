#!/usr/bin/env bash
# Git credential helper: serves the live 1-hour GitHub App token over HTTPS
set -euo pipefail

[ "${1:-}" = "get" ] || exit 0

ROLE="${FACTORY_ROLE:-}"
AUTH_ROOT="${FACTORY_AUTH_ROOT:-/run/factory-auth}"
TOKEN_FILE="${AUTH_ROOT}/${ROLE}/token"

if [ -z "$ROLE" ] || [ ! -r "$TOKEN_FILE" ]; then
  exit 1
fi

HOST=""
while IFS='=' read -r k v; do
  [ -z "$k" ] && break
  if [ "$k" = "host" ]; then HOST="$v"; fi
done

if [ "$HOST" = "github.com" ]; then
  printf 'protocol=https\nhost=github.com\nusername=x-access-token\npassword=%s\n' "$(cat "$TOKEN_FILE")"
fi
