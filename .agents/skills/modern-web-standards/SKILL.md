---
name: modern-web-standards
description: Platform standards for Node 22+, strict TypeScript 5+, semantic HTML, and modern Web/CSS APIs.
---

# Modern Web & Runtime Standards

1. **Runtime & TypeScript:**
   - Target **Node 22+** built-in APIs (`fetch`, `node:test`, `node:crypto`, `AbortSignal.timeout`) before adding third-party utility packages.
   - Enable TypeScript `strict: true`, `noUncheckedIndexedAccess: true`, and avoid `any` (use `unknown` + boundary parsing via Zod/Valibot).
2. **Semantic HTML & Accessibility:**
   - Use native semantic elements (`<button>`, `<nav>`, `<main>`, `<form>`, `<dialog>`) with proper `<label>` associations so both screen readers and Playwright `getByRole`/`getByLabel` locators work seamlessly.
3. **Modern CSS:**
   - Prefer CSS Grid, Flexbox, custom properties (`--var`), and container queries over JS-driven layout calculations.
4. **Zero Unnecessary Dependencies:**
   - Do not add heavy npm packages when the web platform or Node 22 standard library solves the problem cleanly.
