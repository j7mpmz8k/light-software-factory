---
name: pr-evidence-review
description: Rubric for Orchestrator PR diff verification, visual evidence inspection, and safe squash-merging to staging.
---

# Orchestrator PR & Evidence Review Rubric

When CI (`CI & PR Evidence`) passes on a feature PR targeting `staging`, execute these steps in order:

1. **Load Full PR Context:**
   - Run `gh pr view <pr_num> --comments` and `gh pr diff <pr_num>`.
   - Read the linked Sub-Issue spec (`gh issue view <sub_issue_num>`) and check `GLOSSARY.md`.
2. **Fetch Visual & Test Artifacts:**
   - Run `.factory/fetch-evidence.sh <run_id> <pr_num>`.
   - If Playwright PNG screenshots were downloaded, inspect every screenshot using Hermes Vision (`auxiliary.vision`) to verify layout integrity, expected rendered text, and absence of visual errors.
3. **Verify Quality Gates:**
   - Diff stays strictly scoped to the Sub-Issue (no unrelated edits or weakened/deleted tests).
   - PR description documents TDD RED -> GREEN progression and deterministic test outputs.
   - Code favors **Deep Modules** over shallow wrappers and follows `GLOSSARY.md`.
4. **Take Action:**
   - **If branch is `BEHIND` `staging` (Merge-Train Guard):** Check `gh pr view <pr_num> --json mergeStateStatus -q .mergeStateStatus`. If `BEHIND` (another PR merged to `staging` while CI ran), run `gh pr update-branch <pr_num>` and **STOP** — wait for the fresh CI run against the combined `staging` code before merging.
   - **If clean, up-to-date, and ungated:** Run `gh pr review <pr_num> --approve`, squash-merge via `gh pr merge <pr_num> --squash --delete-branch`, and sync board status to `Done`.
   - **If `human-gate` locked:** Post a concise `⚙️ [Orchestrator]` verification summary and **STOP** (do not merge; human owner reviews in `Awaiting Approval`).
   - **If defects found:** Post specific line-level feedback via `gh pr review <pr_num> --request-changes` and dispatch a targeted fix via `.factory/dispatch-worker.sh`.
