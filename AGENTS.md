# Light Software Factory — Agent Operational Manifesto

## 1. Core Principles
1. **Never weaken tests or skip checks** to force a passing PR. Fix root causes.
2. **One atomic Sub-Issue per PR.** Target `staging`, never `main` (or `master`).
3. **Clean-room resets:** Builders run `.factory/prep-branch.sh` to wipe the local `public` schema and dependencies before building.
4. **Zero personal keys:** Use live 1-hour GitHub tokens via `.factory/enter-role.sh`.

## 2. Model Roles (7-Container A1 + B2 Architecture)
- **🧠 Chief Architect (`architect` tab in `herdr-hub` — GLM-5.3 + Vision):** Persistent conversational context with the human developer. Plans Epics, conducts interviews (`grill-with-docs`), drafts specifications and acceptance criteria, and enforces `GLOSSARY.md`. Uses cheap GLM-5.3 credits so marathon brainstorming never drains Ultra 5x quota.
- **⚙️ Factory Orchestrator (`orchestrator` tab in `herdr-hub` — GLM-5.3 + Vision):** Ephemeral context (wiped via `/clear` before each turn). Runs on unthrottled GLM-5.3 so the control plane stays online even if Antigravity throttles. Decomposes approved specs (`to-tickets`), selects the exact `--model` per ticket via `.factory/dispatch-worker.sh`, inspects PR diffs and visual screenshots (`pr-evidence-review`), and squash-merges routine PRs to `staging`.
- **⚡ Primary Multi-Model Builder & Combined Senior/Specialist (`worker-agy` container — Antigravity CLI, AI Ultra 5x):** Single isolated sandbox (`app_agy` DB) dynamically switched per task by the Orchestrator via `--model`:
  1. **Wave 0 Golden Acceptance Engineer (`gemini-4-carbon-high`):** Authors black-box E2E acceptance tests & mock fixtures before feature coding begins (eliminates author bias; proves RED failure).
  2. **Routine Feature Builder (`gemini-4-hydrogen-high`):** High-speed default for standard Wave 1–2 Sub-Issues.
  3. **Complex Feature Builder (`gemini-4-neon-high`):** Heavy multi-file backend, migrations, and deep-module refactoring.
  4. **1-Pass Specialist Rescue (`claude-opus-5-5-high` / `gemini-4-carbon-high`):** Cross-family debugging for 3-strike CI failures and semantic merge conflicts (`conflict-and-rescue`).
- **💻 Parallel Local Builder (`worker-qwen` container — Local Qwen 27B GPU):** Free parallel builder (`app_qwen` DB) for UI, styles, unit tests, and boilerplate at $0 cost.
- **🛡️ Cheap API Backup & Overflow Builder (`worker-glm` container — GLM-5.3 via `llm-proxy`):** Isolated backup builder (`app_glm` DB, dedicated hourly spend cap) that takes over routine coding when Ultra 5x hits a quota window (avoiding expensive Gemini credit spillover) or runs as a 3rd parallel builder on large waves.

## 3. Living Coding Standards & Governance
1. **`AGENTS.md` (This Manifesto):** Governs operational boundaries, safety invariants, and role divisions.
2. **`GLOSSARY.md` (Domain Truth):** Canonical vocabulary for all data entities and factory concepts. All agents consult this before writing code or database schemas.
3. **`.agents/skills/` (Executable Guidelines):** Active standards loaded into agent contexts (`domain-modeling`, `simplify`, `tdd`, `code-review`, `modern-web-standards`, `conflict-and-rescue`).
4. **Scheduled Hygiene Cron (`scheduled-hygiene.yml`):** Runs weekly to audit types, dead code, linting, and test suite health, automatically opening GitHub issues for any detected regressions.

## 4. Testing Discipline: Test Behaviors, Not Internal Wiring
- **Avoid Fragile Mocking:** Do not test internal private helpers or create mock chains that mirror code structure. That creates test maintenance debt where refactorings break tests even when behavior is unchanged.
- **Boundary Testing & Deep Modules:** Test at module boundaries (Deep Modules) or whole-program entrypoints (CLI commands, HTTP endpoints) using deterministic fixtures and mock data.
- **Refactoring Resilience:** If internal abstractions or algorithms change, but the program's output remains identical for a given input, zero tests should need to be re-written or deleted.

## 5. Human Approval Gates & Spend Circuit Breakers
- Any PR touching migrations (`migrations/`, `*.sql`), auth (`auth/`, `security/`), or factory config requires human approval.
- Human approves via GitHub Reviews UI -> merges using **"Create a merge commit"** for the rolling `staging -> main` Release PR.
- **CI Strike Circuit Breaker:** After 3 CI failures, `webhook-bridge.mjs` triggers 1 rescue pass on `worker-agy` (`claude-opus-5-5-high`). If CI fails again after rescue, automated retries halt (`blocked` label) and the Architect alerts the human owner.
