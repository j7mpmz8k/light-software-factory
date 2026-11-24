---
name: to-tickets
description: Decompose specifications into vertical tracer-bullet Sub-Issues and organize into execution waves.
---

# Vertical Slicing & Wave Planning (to-tickets)

Once a Spec is approved, the Factory Orchestrator decomposes the feature into atomic, vertical Sub-Issues organized in waves.

## Principles of Vertical Slicing

1. **Tracer Bullets, Not Layered Horizontal Slices:**
   - **BAD (Horizontal):** Ticket 1: Build all DB tables. Ticket 2: Build all API endpoints. Ticket 3: Build all UI. (Nothing works until the very end).
   - **GOOD (Vertical Tracer Bullet):** Ticket 1: End-to-end "happy path" for creating an entity (DB migration + minimal API + minimal UI form). Verified by automated test.
   - Subsequent tickets add error states, secondary flows, and edge cases.

2. **Wave Organization & Dynamic Model Routing:**
   - **Wave 0 (Golden Acceptance Harness — `worker-agy --model gemini-4-carbon-high`):**
     - Frontier reasoning model writes the deterministic black-box End-to-End Acceptance Test and mock/fixture data (e.g., CLI runner test or Playwright user journey) capturing the Epic's acceptance criteria before feature code is written.
     - Runs the test to confirm it fails (RED), establishing an uncompromised external contract.
   - **Wave 1 (Core Foundations & Tracer Bullets — `worker-agy` + `worker-qwen` + `worker-glm`):**
     - Complex backend/DB/multi-file slices $\to$ `worker-agy --model gemini-4-neon-high`.
     - Routine backend/logic slices $\to$ `worker-agy --model gemini-4-hydrogen-high`.
     - Parallel UI, styles, components, boilerplate $\to$ `worker-qwen` (free local GPU).
     - Overflow / Ultra 5x quota backup $\to$ `worker-glm` (cheap GLM-5.3 API).
   - **Wave 2 (Secondary Flows & Edge Cases):**
     - Validation edge cases, error recovery, and unit test coverage across available builders.
   - **Wave 3 (Full Integration Sign-off & Rescues):**
     - Verify Wave 0's golden acceptance test and full CI suite run completely GREEN with visual/CLI evidence.
     - Any 3-strike CI loop or semantic merge conflict escalates to `worker-agy --model claude-opus-5-5-high` (or `gemini-4-carbon-high`) for strictly 1 rescue pass.

3. **Dynamic DAG Work-Stealing & Schema Migration Serialization:**
   - **Never Treat Waves as Rigid Idle Barriers:** Declare explicit `Depends On: #<sub_issue_num>` (or `Depends On: None`) in every Sub-Issue body. As soon as a Sub-Issue's specific `Depends On` dependency merges to `staging`, dispatch it immediately to any idle worker — never leave an idle worker waiting on unrelated slower PRs from the same wave.
   - **Serialize Database Schema Migrations:** Never schedule two database-schema-modifying Sub-Issues in parallel without a `Depends On:` chain (or group closely coupled tables into one foundational schema Sub-Issue), and require UTC timestamp-prefixed migration filenames (`YYYYMMDDHHMMSS_<slug>.sql`).

4. **Sub-Issue Execution:**
   - Call `.factory/sub-issue.sh` to generate native GitHub Sub-Issues linked to the parent Epic.
   - Every Sub-Issue must include:
     - Explicit `Depends On: None` or `Depends On: #<sub_issue_num>`.
     - Clear acceptance criteria.
     - Target domain types referencing `GLOSSARY.md`.
     - Explicit Test Plan (Red -> Green expectation).
     - Recommended worker and `--model` flag if targeting `worker-agy`.
