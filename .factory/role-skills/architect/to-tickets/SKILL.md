---
name: to-tickets
description: Decompose specifications into vertical tracer-bullet Sub-Issues and organize into execution waves.
---

# Vertical Slicing & Wave Planning (to-tickets)

Once a Spec is approved, the Architect decomposes the feature into atomic, vertical Sub-Issues organized in waves.

## Principles of Vertical Slicing

1. **Tracer Bullets, Not Layered Horizontal Slices:**
   - **BAD (Horizontal):** Ticket 1: Build all DB tables. Ticket 2: Build all API endpoints. Ticket 3: Build all UI. (Nothing works until the very end).
   - **GOOD (Vertical Tracer Bullet):** Ticket 1: End-to-end "happy path" for creating an entity (DB migration + minimal API + minimal UI form). Verified by automated test.
   - Subsequent tickets add error states, secondary flows, and edge cases.

2. **Wave Organization:**
   - **Wave 1 (Foundations & Independent Tracers):** Tasks that have no dependencies and can execute in parallel across workers.
   - **Wave 2 (Dependent Features):** Tasks that build upon Wave 1.
   - **Wave 3 (Integration & Polish):** End-to-end user journey verification, telemetry, and docs.

3. **Sub-Issue Execution:**
   - Call `.factory/sub-issue.sh` to generate native GitHub Sub-Issues linked to the parent Epic.
   - Every Sub-Issue must include:
     - Clear acceptance criteria.
     - Target domain types referencing `GLOSSARY.md`.
     - Explicit Test Plan (Red -> Green expectation).
