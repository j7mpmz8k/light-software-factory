#!/usr/bin/env bash
# Usage:
#   .factory/sub-issue.sh link    <parent_issue_num> <child_issue_num>
#   .factory/sub-issue.sh list    <parent_issue_num>
#   .factory/sub-issue.sh parent  <child_issue_num>
#   .factory/sub-issue.sh summary <parent_issue_num>
set -euo pipefail

CMD="${1:-}"
REPO="${FACTORY_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

case "$CMD" in
  link)
    if [ "${FACTORY_ROLE:-}" = "worker" ]; then
      echo "[sub-issue] ERROR: Only Architect may link Sub-Issues." >&2
      exit 1
    fi
    PARENT_NUM="${2:?parent_issue_num required}"
    CHILD_NUM="${3:?child_issue_num required}"
    CHILD_ID="$(gh api "repos/${REPO}/issues/${CHILD_NUM}" --jq '.id')"
    gh api --method POST "repos/${REPO}/issues/${PARENT_NUM}/sub_issues" \
      -F sub_issue_id="${CHILD_ID}" >/dev/null
    echo "[sub-issue] Linked Sub-Issue #${CHILD_NUM} -> Parent Epic #${PARENT_NUM}"
    ;;

  list)
    PARENT_NUM="${2:?parent_issue_num required}"
    gh api --paginate "repos/${REPO}/issues/${PARENT_NUM}/sub_issues" \
      --jq '.[] | {number, state, title, labels: [.labels[].name]}'
    ;;

  parent)
    CHILD_NUM="${2:?child_issue_num required}"
    gh api "repos/${REPO}/issues/${CHILD_NUM}/parent" \
      --jq '{number, state, title, labels: [.labels[].name]}' 2>/dev/null || echo "null"
    ;;

  summary)
    PARENT_NUM="${2:?parent_issue_num required}"
    gh api "repos/${REPO}/issues/${PARENT_NUM}" \
      --jq '.sub_issues_summary // {total: 0, completed: 0, percent_completed: 0}'
    ;;

  *)
    echo "Usage: $0 <link|list|parent|summary> <issue_num> [child_num]" >&2
    exit 1
    ;;
esac
