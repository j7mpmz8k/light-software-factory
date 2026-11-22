---
name: code-review
description: Objective review rubric for evaluating pull requests and diffs against requirements.
---

# Code Review & Verification Rubric

Use this checklist when reviewing any PR or performing an audit pass.

## Review Checklist

### 1. Requirements & Spec Adherence
- Does the diff fulfill all acceptance criteria defined in the parent Sub-Issue?
- Does it stay within scope? Flag any out-of-scope refactoring or speculative code.

### 2. Testing & Evidence
- Was strict TDD followed? Are there automated tests covering both happy path and failure cases?
- Are tests deterministic? (No arbitrary sleeps, timeouts, or race conditions).
- Are visual evidence screenshots attached if UI or routes were altered?

### 3. Domain & Naming
- Do all variable, type, and table names conform to `GLOSSARY.md`?
- Are domain invariants enforced at boundaries?

### 4. Code Quality & Hygiene
- Are there any leftover debugging statements (`console.log`, `print`, `TODO`)?
- Are error cases handled gracefully with clear error types?
- Are database queries indexed and protected against injection?

## Verdicts
- **APPROVE:** All criteria met, CI passed, evidence verified.
- **REQUEST_CHANGES:** Provide concrete, actionable feedback referencing specific lines and failure cases.
