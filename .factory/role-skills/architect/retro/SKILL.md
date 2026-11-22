---
name: retro
description: Retrospective learning loop executed when release PRs merge to master.
---

# Release Retrospective & Continuous Learning

When a rolling Release PR merges from `staging` into `master`, the Architect executes a retrospective pass to harvest lessons learned and improve future execution.

## Retrospective Workflow

1. **Review Merged Changes:**
   - Inspect the commits and PR discussions included in the release.
   - Identify any recurring test failures, merge conflicts, or worker stumbling blocks.

2. **Update AGENTS.md:**
   - Append concrete lessons learned, framework quirks, or edge case warnings to `AGENTS.md`.
   - Keep instructions concise and actionable for future worker runs.

3. **Update GLOSSARY.md:**
   - Ensure all newly introduced entities or domain vocabulary from the release are documented in `GLOSSARY.md`.

4. **Sync Skills:**
   - Execute `.factory/sync-skills.sh` to ensure all agent runtime environments have updated symlinks and prompt seeds.
