---
name: e2e-testing
description: Deterministic Playwright and CLI end-to-end acceptance testing standards and visual evidence capture.
---

# End-to-End Acceptance Testing Standards

End-to-end tests verify the **whole assembled program** at its real outer boundary (real browser + real Postgres, or real CLI binary + deterministic fixture files) without mocking internal functions.

## Rules for Deterministic E2E Tests
1. **Use Real Boundaries, Never Internal Mocks:**
   - **Web apps (Playwright):** Run against the real app server and isolated worker Postgres DB (`$DATABASE_URL`). Never stub your own internal API routes.
   - **CLI / backend tools:** Execute the real binary/entrypoint against known fixture inputs (e.g., `fixtures/sample.txt`) and assert exact exit codes, stdout/stderr, and output artifacts.
2. **Eliminate Flakiness:**
   - Never use `waitForTimeout(3000)` or arbitrary sleeps.
   - Use semantic Playwright locators (`getByRole`, `getByLabel`, `getByText`) with auto-retrying web-first assertions (`await expect(locator).toBeVisible()`).
   - Seed deterministic test data per test run; never rely on random IDs or wall-clock timestamps without freezing/normalizing them.
3. **Capture Visual Evidence:**
   - Save screenshots (`testInfo.attach` / `page.screenshot`) at key user journey checkpoints and on failure so CI uploads them as `pr-<num>-evidence` for Orchestrator Vision review.
