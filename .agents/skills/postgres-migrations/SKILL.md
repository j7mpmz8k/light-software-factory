---
name: postgres-migrations
description: PostgreSQL 16 migration safety, idempotency, constraint enforcement, and clean-room verification standards.
---

# PostgreSQL Migration & Schema Standards

All database migrations trigger the `human-gate-guard` firewall and require clean-room verification in CI against Postgres 16.

## Core Directives
1. **Enforce Invariants in the Database:**
   - Mirror domain types from `GLOSSARY.md` and `domain-modeling` with real constraints: `NOT NULL`, `FOREIGN KEY`, `UNIQUE`, and `CHECK` constraints.
   - Always create indexes for foreign keys and high-frequency query filters.
2. **Safe, Deterministic & Forward-Clean Migrations:**
   - Migrations must apply cleanly from an empty `public` schema (verified by `.factory/prep-branch.sh` and CI `npm run db:migrate`).
   - Do not depend on superuser privileges — extensions (`pgcrypto`, `uuid-ossp`) live in the pre-provisioned `extensions` schema already on `search_path`.
   - Avoid destructive column drops or lock-heavy table rewrites without an explicit multi-step deprecation plan in `DECISIONS.md`.
3. **Test Against Real Postgres:**
   - Integration tests must run migrations against `$DATABASE_URL` (`app_agy`, `app_qwen`, `app_glm`) and verify constraints reject invalid data as expected.
