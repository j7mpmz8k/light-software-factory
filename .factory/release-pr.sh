#!/usr/bin/env bash
# Usage: .factory/release-pr.sh [completed_epic_num]
set -euo pipefail

if [ "${FACTORY_ROLE:-}" = "worker" ]; then
  echo "[release-pr] ERROR: Only Architect may open or update Release PRs." >&2
  exit 1
fi

ENV_FILE="${BRIDGE_ENV_FILE:-/run/factory-config/bridge.env}"
[ ! -r "$ENV_FILE" ] && ENV_FILE=".factory/.env"
[ -r "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

EPIC_NUM="${1:-}"
REPO="${FACTORY_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
DEFAULT_BRANCH="$(gh repo view "$REPO" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "main")"
BASE_BRANCH="${RELEASE_BASE_BRANCH:-${DEFAULT_BRANCH:-main}}"
HEAD_BRANCH="staging"

REVIEWER="${HUMAN_REVIEWER:-}"
if [ -z "$REVIEWER" ] && [ -r /workspace/.github/CODEOWNERS ]; then
  REVIEWER="$(grep -Eo '@[A-Za-z0-9-]+' /workspace/.github/CODEOWNERS | head -n1 | tr -d '@' || true)"
fi

COMPARE_JSON="$(gh api "repos/${REPO}/compare/${BASE_BRANCH}...${HEAD_BRANCH}")"
AHEAD_BY="$(echo "$COMPARE_JSON" | jq -r '.ahead_by // 0')"

if [ "$AHEAD_BY" -eq 0 ]; then
  echo "[release-pr] ${HEAD_BRANCH} has 0 commits ahead of ${BASE_BRANCH}; skipping Release PR."
  exit 0
fi

CHANGELOG="$(echo "$COMPARE_JSON" | jq -r '.commits[] | "- `\(.sha[0:7])` \(.commit.message | split("\n")[0])"')"
EPIC_LINE=""
if [ -n "$EPIC_NUM" ]; then
  EPIC_TITLE="$(gh issue view "$EPIC_NUM" --json title -q .title 2>/dev/null || true)"
  EPIC_LINE="- **Latest Completed Epic:** #${EPIC_NUM}${EPIC_TITLE:+ — ${EPIC_TITLE}}"
fi

BODY="$(cat <<EOF
**[Architect]** Rolling production release PR promoting verified changes from \`${HEAD_BRANCH}\` into \`${BASE_BRANCH}\`.

> 🔒 **Human-Only Production Gate:** This PR is physically locked by \`CODEOWNERS\`, Ruleset #2, and \`human-gate-guard\`.
> ⚠️ **IMPORTANT MERGE METHOD:** After clicking **Approve**, merge using **"Create a merge commit"** — **NEVER "Squash and merge"** — so \`${HEAD_BRANCH}\` and \`${BASE_BRANCH}\` share history cleanly.

## Release Summary
- **Commits ahead of \`${BASE_BRANCH}\`:** ${AHEAD_BY}
${EPIC_LINE}

## Changes Included in This Release
${CHANGELOG}
EOF
)"

EXISTING_PR="$(gh pr list --base "$BASE_BRANCH" --head "$HEAD_BRANCH" --state open --json number -q '.[0].number // empty')"
PR_NUM=""

if [ -n "$EXISTING_PR" ]; then
  gh pr edit "$EXISTING_PR" --body "$BODY" >/dev/null
  PR_NUM="$EXISTING_PR"
  echo "[release-pr] Updated rolling Release PR #${PR_NUM} (${HEAD_BRANCH} -> ${BASE_BRANCH}, ${AHEAD_BY} commits)."
else
  PR_URL="$(gh pr create \
    --base "$BASE_BRANCH" \
    --head "$HEAD_BRANCH" \
    --title "chore(release): promote ${HEAD_BRANCH} to ${BASE_BRANCH}" \
    --body "$BODY")"
  PR_NUM="${PR_URL##*/}"
  echo "[release-pr] Opened rolling Release PR #${PR_NUM}: ${PR_URL}"
fi

if [ -n "$PR_NUM" ]; then
  gh pr edit "$PR_NUM" --add-label "human-gate" >/dev/null 2>&1 || true
  if [ -n "$REVIEWER" ]; then
    gh pr edit "$PR_NUM" --add-reviewer "$REVIEWER" >/dev/null 2>&1 || true
  fi
  if [ -x /workspace/.factory/board-sync.sh ]; then
    /workspace/.factory/board-sync.sh "pr:${PR_NUM}" Status "Awaiting Approval" || true
    /workspace/.factory/board-sync.sh "pr:${PR_NUM}" Worker "Architect" || true
  fi
fi
