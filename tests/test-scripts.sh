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

assert_contains() {
  local label="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  ✔ ${label}"
    PASSED=$((PASSED + 1))
  else
    echo "  ✖ ${label} (expected output to contain '${needle}', got '${haystack}')"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== Running Factory Scripts Integration Tests ==="

# 1. Test dispatch-worker.sh usage, validation, and dynamic --model routing
OUT="$(.factory/dispatch-worker.sh 2>&1 || true)"
assert_eq "dispatch-worker.sh rejects missing args" "Usage: .factory/dispatch-worker.sh <worker_name> <sub_issue_prompt> [--model <model_id>] [--dry-run]" "$OUT"

OUT="$(.factory/dispatch-worker.sh unknown-worker 'test prompt' --dry-run 2>&1 || true)"
assert_contains "dispatch-worker.sh rejects unknown worker name" "Unknown worker 'unknown-worker'" "$OUT"

OUT="$(.factory/dispatch-worker.sh worker-agy 'test prompt' --model 'bad;rm -rf /' --dry-run 2>&1 || true)"
assert_contains "dispatch-worker.sh rejects shell injection in --model" "Invalid model ID" "$OUT"

OUT="$(.factory/dispatch-worker.sh worker-agy 'Wave 1 routine task' --dry-run 2>&1)"
assert_eq "dispatch-worker.sh defaults worker-agy to gemini-4-hydrogen-high" "[dispatch-worker:dry-run] worker=worker-agy model=gemini-4-hydrogen-high" "$OUT"

OUT="$(.factory/dispatch-worker.sh worker-agy 'Wave 0 E2E task' --model gemini-4-carbon-high --dry-run 2>&1)"
assert_eq "dispatch-worker.sh routes worker-agy with explicit --model carbon" "[dispatch-worker:dry-run] worker=worker-agy model=gemini-4-carbon-high" "$OUT"

OUT="$(.factory/dispatch-worker.sh worker-agy 'Strike 3 rescue' --model=claude-opus-5-5-high --dry-run 2>&1)"
assert_eq "dispatch-worker.sh supports --model= syntax for opus rescue" "[dispatch-worker:dry-run] worker=worker-agy model=claude-opus-5-5-high" "$OUT"

OUT="$(.factory/dispatch-worker.sh worker-glm 'Backup overflow task' --dry-run 2>&1)"
assert_eq "dispatch-worker.sh routes worker-glm via hermes profile" "[dispatch-worker:dry-run] worker=worker-glm model=hermes-profile" "$OUT"

OUT="$(.factory/dispatch-worker.sh worker-qwen 'UI component task' --dry-run 2>&1)"
assert_eq "dispatch-worker.sh routes worker-qwen via hermes profile" "[dispatch-worker:dry-run] worker=worker-qwen model=hermes-profile" "$OUT"

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

# 8. Test sync-skills.sh linking across all A1 + B2 roles
MOCK_HOME="/tmp/factory-mock-home-$$"
mkdir -p "${MOCK_HOME}/.hermes/skills"
HOME="$MOCK_HOME" .factory/sync-skills.sh architect
HOME="$MOCK_HOME" .factory/sync-skills.sh orchestrator
HOME="$MOCK_HOME" .factory/sync-skills.sh worker-agy
HOME="$MOCK_HOME" .factory/sync-skills.sh worker-glm
assert_eq "sync-skills.sh links tdd skill for architect" "true" "$([ -L "${MOCK_HOME}/.hermes/profiles/architect/skills/tdd" ] && echo "true" || echo "false")"
assert_eq "sync-skills.sh links grill-with-docs for architect" "true" "$([ -L "${MOCK_HOME}/.hermes/profiles/architect/skills/grill-with-docs" ] && echo "true" || echo "false")"
assert_eq "sync-skills.sh links to-tickets for orchestrator" "true" "$([ -L "${MOCK_HOME}/.hermes/profiles/orchestrator/skills/to-tickets" ] && echo "true" || echo "false")"
assert_eq "sync-skills.sh links conflict-and-rescue for worker-agy" "true" "$([ -L "${MOCK_HOME}/.gemini/antigravity-cli/skills/conflict-and-rescue" ] && echo "true" || echo "false")"
assert_eq "sync-skills.sh links domain-modeling for worker-glm" "true" "$([ -L "${MOCK_HOME}/.hermes/skills/domain-modeling" ] && echo "true" || echo "false")"
rm -rf "$MOCK_HOME"

# 9. Regression guard: never pass text strings ("/clear", "/exit") or tmux "C-d" to herdr agent send-keys
BAD_SENDKEYS="$(grep -rnE 'send-keys.*("/clear"|"/exit"|"C-d")' .factory/ || true)"
assert_eq "no invalid text or tmux keys passed to herdr send-keys" "" "$BAD_SENDKEYS"

echo "=== Scripts Integration Results: ${PASSED} passed, ${FAILED} failed ==="
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
