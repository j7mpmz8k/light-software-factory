#!/usr/bin/env bash
# Usage: .factory/sync-skills.sh <architect|worker-gemini|worker-qwen|specialist-fable>
set -euo pipefail

AGENT_ID="${1:-${WORKER_NAME:-architect}}"
SHARED_DIR="/workspace/.agents/skills"
ROLE_DIR="/workspace/.factory/role-skills"

link_skills_into() {
  local target_dir="$1"
  shift
  mkdir -p "$target_dir"
  # Remove stale symlinks pointing into /workspace
  find "$target_dir" -maxdepth 1 -type l -lname '/workspace/*' -delete 2>/dev/null || true
  for src_root in "$@"; do
    [ -d "$src_root" ] || continue
    for skill_dir in "$src_root"/*; do
      [ -d "$skill_dir" ] || continue
      ln -sfn "$skill_dir" "${target_dir}/$(basename "$skill_dir")"
    done
  done
}

case "$AGENT_ID" in
  architect)
    link_skills_into "$HOME/.hermes/skills" "$SHARED_DIR" "${ROLE_DIR}/architect"
    if command -v herdr >/dev/null 2>&1; then
      mkdir -p "$HOME/.hermes/skills/herdr"
      herdr --skill > "$HOME/.hermes/skills/herdr/SKILL.md" 2>/dev/null || true
    fi
    ;;
  worker-gemini)
    link_skills_into "$HOME/.gemini/antigravity/skills" "$SHARED_DIR"
    link_skills_into "$HOME/.gemini/config/skills" "$SHARED_DIR"
    ;;
  worker-qwen)
    link_skills_into "$HOME/.hermes/skills" "$SHARED_DIR"
    ;;
  specialist-fable)
    link_skills_into "$HOME/.claude/skills" "$SHARED_DIR" "${ROLE_DIR}/fable"
    ;;
esac
