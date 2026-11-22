#!/usr/bin/env bash
# Integration test for Light Software Factory scripts
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✔ ${label}"
    PASSED=$((PASSED + 1))
  else
    echo "  ✖ ${label} (expected '${expected}', got '${actual}')"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== Running Factory Scripts Integration Tests ==="

# 1. Test dispatch-worker.sh usage check
OUT="$(.factory/dispatch-worker.sh 2>&1 || true)"
assert_eq "dispatch-worker.sh rejects missing args" "Usage: .factory/dispatch-worker.sh <worker_name> <sub_issue_prompt>" "$OUT"

# 2. Test prep-branch.sh usage check
OUT="$(.factory/prep-branch.sh 2>&1 || true)"
assert_eq "prep-branch.sh rejects missing args" "Usage: .factory/prep-branch.sh <issue_number_or_branch> [short_slug] [--keep-db]" "$OUT"

# 3. Test sub-issue.sh usage check
OUT="$(.factory/sub-issue.sh 2>&1 || true)"
assert_eq "sub-issue.sh rejects invalid/missing command" "Usage: .factory/sub-issue.sh <link|list|parent|summary> <issue_num> [child_num]" "$OUT"

# 4. Test fetch-evidence.sh usage check
OUT="$(.factory/fetch-evidence.sh 2>&1 || true)"
assert_eq "fetch-evidence.sh rejects missing args" "Usage: .factory/fetch-evidence.sh <run_id> <pr_number>" "$OUT"

# 5. Test enter-role.sh usage check
OUT="$(source .factory/enter-role.sh invalid-role 2>&1 || true)"
assert_eq "enter-role.sh rejects invalid role" "Usage: source .factory/enter-role.sh <architect|worker>" "$OUT"

# 6. Test board-sync.sh worker role restriction
OUT="$(FACTORY_ROLE=worker .factory/board-sync.sh 1 Status "In Progress" 2>&1 || true)"
assert_eq "board-sync.sh skips for worker role" "[board-sync] Skipping: worker role does not modify project board." "$OUT"

# 7. Test git-credential-factory.sh credential retrieval
MOCK_AUTH_DIR="/tmp/factory-mock-auth-$$"
mkdir -p "${MOCK_AUTH_DIR}/worker"
echo "ghp_mock_token_123456" > "${MOCK_AUTH_DIR}/worker/token"

CRED_OUT="$(printf 'protocol=https\nhost=github.com\n\n' | FACTORY_ROLE=worker FACTORY_AUTH_ROOT="$MOCK_AUTH_DIR" .factory/git-credential-factory.sh get)"
EXPECTED_CRED="$(printf 'protocol=https\nhost=github.com\nusername=x-access-token\npassword=ghp_mock_token_123456\n')"
assert_eq "git-credential-factory.sh formats credentials correctly" "$EXPECTED_CRED" "$CRED_OUT"
rm -rf "$MOCK_AUTH_DIR"

# 8. Test sync-skills.sh linking
MOCK_HOME="/tmp/factory-mock-home-$$"
mkdir -p "${MOCK_HOME}/.hermes/skills"
HOME="$MOCK_HOME" .factory/sync-skills.sh architect
assert_eq "sync-skills.sh links tdd skill" "true" "$([ -L "${MOCK_HOME}/.hermes/skills/tdd" ] && echo "true" || echo "false")"
assert_eq "sync-skills.sh links grill-with-docs skill" "true" "$([ -L "${MOCK_HOME}/.hermes/skills/grill-with-docs" ] && echo "true" || echo "false")"
rm -rf "$MOCK_HOME"

echo "=== Scripts Integration Results: ${PASSED} passed, ${FAILED} failed ==="
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
