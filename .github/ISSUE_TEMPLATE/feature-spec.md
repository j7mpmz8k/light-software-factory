---
name: Factory Task / Sub-Issue Spec
about: Atomic single-PR task (1 unique Sub-Issue = 1 Worker = 1 PR)
title: "[TASK] "
labels: []
---

## Objective
<!-- 1–2 sentences describing the exact slice to build, fix, or verify end-to-end -->

## Parent Epic & Wave
- **Parent Epic:** *(None if standalone, or `#<epic_num>`)*
- **Execution Wave:** `Wave 0 (Golden E2E Acceptance)` / `Wave 1 (Foundations)` / `Wave 2 (Parallel Build)` / `Wave 3 (Integration Sign-Off)`
- **Depends On:** *(None, or `#<sub_issue_num>` merged to `staging`)*

## Target Module / Files
- `path/to/module`

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Test Plan (Architect-Authored — Mandatory)
- **Happy Path:** <!-- Concrete scenario(s) & expected UI/API/CLI/Postgres outcome -->
- **Edge / Error Cases:** <!-- Invalid input, empty state, permission/constraint edge case -->
- **Verification Layer:** `Wave 0 Black-Box E2E (deterministic fixtures / Playwright)` OR `Unit + API/DB Integration`

## Routing & Guardrail Hints
- **Human Gate:** *(Auto-locked by `human-gate-guard` & moved to `Awaiting Approval` if touching `migrations/`, `*.sql`, `auth/`, `.github/`, `.factory/`, `docker-compose*.yml`, or `AGENTS.md`. Add `human-gate` label only if manual override is needed on other paths.)*
- **Suggested Worker & Model:**
  - `worker-agy --model gemini-4-carbon-high` *(Wave 0 Golden E2E Acceptance Tests & fixtures)*
  - `worker-agy --model gemini-4-neon-high` *(Complex multi-file backend, DB migrations, deep-module refactors)*
  - `worker-agy --model gemini-4-hydrogen-high` *(Fast routine Wave 1–2 implementation)*
  - `worker-agy --model claude-opus-5-5-high` *(1-pass 3-strike rescue or semantic merge conflict)*
  - `worker-qwen` *(Free local GPU: UI, styling, unit tests, parallel overflow)*
  - `worker-glm` *(Cheap GLM-5.3 API backup when Ultra 5x throttles or 3rd parallel slot)*
- **Relevant Skills:** `.agents/skills/tdd` / `.agents/skills/domain-modeling` / `.agents/skills/simplify` / `.agents/skills/postgres-migrations` / `.agents/skills/e2e-testing` / `.agents/skills/conflict-and-rescue`
- **Out of Scope:** <!-- Explicitly state what NOT to touch (especially files assigned to sibling Sub-Issues in the same wave) -->
