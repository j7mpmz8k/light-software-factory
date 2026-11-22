---
name: tdd
description: Strict Test-Driven Development (Red-Green-Refactor) workflow for all code changes.
---

# Test-Driven Development (TDD) Workflow

Every worker must adhere to the Red-Green-Refactor discipline. Writing implementation code before a failing test is strictly forbidden.

## The 3 Mandatory Steps

### 1. RED (Prove Failure)
- Write an automated unit, integration, or E2E test that captures the specific requirement or bug fix.
- Run the test suite: verify that the test **fails**.
- **Crucial:** Confirm that the test failed for the **expected reason** (e.g. missing function, assertion failure, missing route), not a syntax error or broken setup.
- If the test passes before implementation, your test is invalid or the feature already exists.

### 2. GREEN (Minimal Implementation)
- Write the **minimum amount of code** necessary to make the failing test pass.
- Do not write anticipatory features, unneeded abstractions, or speculative error handling.
- Run the test suite: verify that all tests pass cleanly.

### 3. REFACTOR (Clean Up)
- Clean up the code while keeping all tests passing.
- Eliminate duplicate code, improve variable naming according to `GLOSSARY.md`, and simplify control flow.
- Re-run tests to confirm zero regressions.

## Test Coarseness: Test Behaviors, Not Internal Wiring

TDD must never become a straightjacket that penalizes refactoring. Adhere to these principles to prevent brittle tests:

1. **Black-Box Determinism (Outer Boundary Testing):**
   - Test at whole-program or module entrypoints (e.g. CLI commands with deterministic mock input fixtures, HTTP routes with sample payloads).
   - Verify observable outputs (stdout, returned JSON, database state) against known fixtures.
   - Example (CLI Tool): Running `my-cli parse fixtures/sample.txt` with mock input should deterministically produce `fixtures/expected.json`. If output matches, the program works.

2. **Avoid Mocking Internal Classes & Functions:**
   - Never write tests that mock internal helper methods or verify private call counts.
   - Tests that mirror internal file structures break whenever abstractions are refactored, forcing costly rewrites.
   - Test the public interface of a **Deep Module**; leave internal plumbing free to change.

3. **Refactoring Resilience:**
   - A well-designed test survives an internal architectural redesign without modifying a single line of test code. If the user-visible input/output contract didn't change, the test must not change.

## Agent Commitments
- Never commit implementation code without an accompanying test.
- Every PR description must document the test run output proving the RED -> GREEN progression.
