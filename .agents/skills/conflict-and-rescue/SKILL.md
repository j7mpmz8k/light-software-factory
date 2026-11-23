---
name: conflict-and-rescue
description: Playbook for Senior/Specialist 1-pass merge conflict resolution and 3-strike CI rescue on worker-agy.
---
# Conflict Resolution & 3-Strike Rescue Playbook

When invoked as a **Senior/Specialist Rescue** (`worker-agy` running `claude-opus-5-5-high` or `gemini-4-carbon-high`):

1. **Inspect Before Editing:**
   - Read the failing CI logs (`gh run view <run_id> --log-failed`) and the existing PR diff (`gh pr diff <pr_num>`).
   - Identify the **root cause** — never patch symptoms or weaken/delete Wave 0 acceptance tests.
2. **Clean Merge Conflict Resolution:**
   - Fetch `origin/staging` and rebase/merge cleanly, preserving both incoming staging changes and the PR's domain invariants.
3. **Verify Locally Before Pushing:**
   - Run the full relevant test suite (`npm test`, typecheck, linter, and Wave 0 E2E test) against your isolated Postgres DB (`app_agy`).
   - Confirm clean exit code `0` before pushing the single rescue pass.
4. **1-Pass Discipline:**
   - You have strictly **1 rescue pass**. If the failure stems from a contradictory requirement or missing secret, do NOT hack around it — document the exact blocker on the PR so the circuit breaker halts cleanly for the Architect/Human.
