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

2. **Wave Organization & Agent Routing:**
   - **Wave 0 (Golden Acceptance Harness — Assigned to `senior-worker`):**
     - Frontier reasoning model writes the deterministic black-box End-to-End Acceptance Test and mock/fixture data (e.g. CLI runner test or Playwright user journey) capturing the Epic's acceptance criteria before feature code is written.
     - Runs the test to confirm it fails (RED), establishing an uncompromised external contract.
   - **Wave 1 (Core Foundations & Tracer Bullets — Assigned to `worker-gemini` / `worker-qwen`):**
     - Flat-rate / local builders implement core domain models, schema migrations, and happy-path logic to work toward turning the acceptance test GREEN.
   - **Wave 2 (Secondary Flows & Edge Cases — Assigned to `worker-gemini` / `worker-qwen`):**
     - Validation edge cases, error recovery, and unit test coverage.
   - **Wave 3 (Full Integration Sign-off):**
     - Verify that Wave 0's golden acceptance test and full test suite pass completely GREEN in CI with visual and CLI evidence.

3. **Sub-Issue Execution:**
   - Call `.factory/sub-issue.sh` to generate native GitHub Sub-Issues linked to the parent Epic.
   - Every Sub-Issue must include:
     - Clear acceptance criteria.
     - Target domain types referencing `GLOSSARY.md`.
     - Explicit Test Plan (Red -> Green expectation).
