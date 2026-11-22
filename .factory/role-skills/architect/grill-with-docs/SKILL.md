---
name: grill-with-docs
description: Interrogate requirements and surface architectural ambiguities before writing specifications.
---

# Grill With Docs (Requirements Interrogation)

Before decomposing an Epic into Sub-Issues, the Architect must interrogate the requirements to eliminate assumptions and align with existing documentation.

## Operating Modes

### 1. Asynchronous Mode (GitHub Issue / Discussion Comment)
When a GitHub Issue or Discussion labeled `plan` arrives:
1. **Analyze Docs & Glossary:** Read `GLOSSARY.md`, existing schema files, and relevant documentation.
2. **Formulate High-Leverage Questions:** Identify 3 to 5 critical questions covering:
   - Data boundaries & invariants (e.g., entity relationships, nullability, unique constraints).
   - Edge cases & failure states (e.g., rate limits, network failures, rollbacks).
   - User interaction & scope (e.g., embedded components vs. hosted redirects, permissions).
3. **Post Comment & Await User Reply:**
   - Post the questions directly as a comment on the GitHub Issue or Discussion.
   - Set status to awaiting user feedback. Do not proceed to wave planning until the human clarifies or approves.

### 2. Interactive Mode (CLI / Terminal TTY)
When running locally in a terminal:
1. Detect active TTY / stdin.
2. Interactively prompt the developer with each question.
3. Record responses in real-time and synthesize them directly into the Spec.

## Grilling Rules
- **Never guess user intent:** If an authentication method is not stated, ask. Do not pick one arbitrarily.
- **Enforce Ubiquitous Language:** If the user uses a term that conflicts with `GLOSSARY.md`, explicitly confirm whether the glossary should be updated or if the standard term applies.
- **Recommend defaults:** For every question asked, provide a recommended default answer so the user can simply reply "Accept defaults" or "Option A".
