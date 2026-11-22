# Light Software Factory — Agent Operational Manifesto

## 1. Core Principles
1. **Never weaken tests or skip checks** to force a passing PR. Fix root causes.
2. **One atomic Sub-Issue per PR.** Target `staging`, never `master`.
3. **Clean-room resets:** Builders run `.factory/prep-branch.sh` to wipe the local `public` schema and dependencies before building.
4. **Zero personal keys:** Use live 1-hour GitHub tokens via `.factory/enter-role.sh`.

## 2. Model Roles
- **🧠 Chief Architect (`architect` tab in `herdr-hub`):** Persistent conversational context with the human developer. Plans Epics, conducts interviews (`grill-with-docs`), drafts specifications and test criteria, and enforces `GLOSSARY.md`.
- **⚙️ Factory Orchestrator (`orchestrator` tab in `herdr-hub`):** Ephemeral context (wiped via `/clear` before each turn). Decomposes approved specs into vertical tracer bullets (`to-tickets`), dispatches workers via `.factory/dispatch-worker.sh`, reviews PR diffs and visual evidence (`pr-evidence-review`), and squash-merges routine PRs to `staging`.
- **🛠️ Primary Builder (`worker-gemini` container):** High-volume backend, DB migrations, feature code, and Playwright/CLI E2E verification (Antigravity CLI / flat-rate quota).
- **💻 Parallel Builder (`worker-qwen` container):** Local GPU inference for UI, styles, unit tests, and zero-cost local iteration.
- **⭐ Senior Builder (`senior-worker` container):** High-capability frontier model (Gemini 4 Neon / Claude via API) running Hermes. Steps in strictly as an emergency coding relief worker when `worker-gemini` hits rate limits or is blocked.
- **🔥 Specialist (`specialist-fable` container):** Capped at 1 pass per PR for merge conflicts and 3-strike CI loops.

## 3. Living Coding Standards & Governance
1. **`AGENTS.md` (This Manifesto):** Governs operational boundaries, safety invariants, and role divisions.
2. **`GLOSSARY.md` (Domain Truth):** Canonical vocabulary for all data entities and factory concepts. All agents consult this before writing code or database schemas.
3. **`.agents/skills/` (Executable Guidelines):** Active standards loaded into agent contexts (`domain-modeling`, `simplify`, `tdd`, `code-review`, `modern-web-standards`).
4. **Scheduled Hygiene Cron (`scheduled-hygiene.yml`):** Runs weekly to audit types, dead code, linting, and test suite health, automatically opening GitHub issues for any detected regressions.

## 4. Testing Discipline: Test Behaviors, Not Internal Wiring
- **Avoid Fragile Mocking:** Do not test internal private helpers or create mock chains that mirror code structure. That creates test maintenance debt where refactorings break tests even when behavior is unchanged.
- **Boundary Testing & Deep Modules:** Test at module boundaries (Deep Modules) or whole-program entrypoints (CLI commands, HTTP endpoints) using deterministic fixtures and mock data.
- **Refactoring Resilience:** If internal abstractions or algorithms change, but the program's output remains identical for a given input, zero tests should need to be re-written or deleted.

## 5. Human Approval Gates
- Any PR touching migrations (`migrations/`, `*.sql`), auth (`auth/`, `security/`), or factory config requires human approval.
- Human approves via GitHub Reviews UI -> merges using **"Create a merge commit"** for the rolling `staging -> master` Release PR.
