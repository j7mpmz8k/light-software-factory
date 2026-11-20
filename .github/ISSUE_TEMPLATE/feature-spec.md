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
- **Execution Wave:** `Wave 1 (Foundations)` / `Wave 2 (Parallel Build)` / `Final Wave (E2E Verification)`
- **Depends On:** *(None, or `#<sub_issue_num>` merged to `staging`)*

## Target Module / Files
- `path/to/module`

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Test Plan (Architect-Authored — Mandatory)
- **Happy Path:** <!-- Concrete scenario(s) & expected UI/API/Postgres outcome -->
- **Edge / Error Cases:** <!-- Invalid input, empty state, permission/constraint edge case -->
- **Verification Layer:** `Unit + API/DB Integration` *(build slices)* OR `Full-Journey Playwright E2E (real app + Postgres, zero API mocking)` *(Final Wave)*

## Routing & Guardrail Hints
- **Human Gate:** *(Auto-locked by `human-gate-guard` & moved to `Awaiting Approval` if touching `migrations/`, `*.sql`, `auth/`, `.github/`, `.factory/`, `docker-compose*.yml`, or `AGENTS.md`. Add `human-gate` label only if manual override is needed on other paths.)*
- **Suggested Worker:** `worker-gemini` (heavy/multi-file/backend/DB/integration, OR **Primary E2E Writer in fresh session**) OR `worker-qwen` (UI/unit/local, narrow 1–2 screen cross-model E2E in fresh session, or Antigravity quota overflow)
- **Session Mode:** `Standard` *(build slice)* OR `FRESH / STATELESS SESSION REQUIRED` *(Final-Wave E2E — reset chat context before starting)*
- **Relevant Skills:** `.agents/skills/modern-web-standards` / `.agents/skills/postgres-migrations` / `.agents/skills/e2e-testing`
- **Out of Scope:** <!-- Explicitly state what NOT to touch (especially files assigned to sibling Sub-Issues in the same wave) -->
