# Domain Glossary & Ubiquitous Language

This glossary is the single source of truth for domain terms across the Light Software Factory.
All agents (Architect, Workers, Reviewer) and developers must use these canonical terms. Never invent synonyms.

---

## Core Factory Concepts

| Canonical Term | Definition | Forbidden Synonyms (Do Not Use) |
| :--- | :--- | :--- |
| **Epic / Feature Issue** | The top-level GitHub Issue describing a user capability or product requirement. | Parent ticket, Story, Mega-issue |
| **Sub-Issue** | An atomic, vertical tracer-bullet task executed by a single worker on an isolated branch. | Child ticket, Subtask, Micro-issue |
| **Wave** | A group of independent Sub-Issues that can execute safely in parallel without merge conflicts. | Batch, Sprint, Phase group |
| **Tracer Bullet** | A thin, end-to-end slice spanning database, backend, and UI to prove architecture early. | Prototype, Spike, Vertical spike |
| **Deep Module** | A module with a small, simple interface hiding deep implementation complexity (Ousterhout/Pocock). Maximizes test determinism. | Shallow wrapper, Thin abstraction, Passthrough |
| **Shallow Module** | An anti-pattern where the interface is as complex as the implementation, leaking internals and causing brittle tests. | Thin layer, Trivial wrapper |
| **Spec** | The locked technical specification created by the Architect after grilling and modeling. | Plan, RFC, Blueprint |
| **Evidence** | Deterministic artifacts (Playwright screenshots, test logs, coverage) verifying a PR works. | Proof, Screenshots, Output |
| **Hygiene** | Routine automated maintenance (dead code removal, dependency audit, type checking). | Cleanup, Sweeping, Chore pass |

---

## Codebase Domain Entities

*(Update this section as project business logic is defined. Example below:)*

| Canonical Term | Definition | Forbidden Synonyms |
| :--- | :--- | :--- |
| **Organization** | The top-level tenant boundary grouping users and billing. | Tenant, Workspace, Company, Account |
| **User** | An authenticated individual account belonging to one or more Organizations. | Member, Person, Profile |
| **Role** | Permission set assigned to a User within an Organization (e.g., `owner`, `admin`, `member`). | Access level, Rank |

---

## Agent Rules for GLOSSARY.md
1. **Check First:** Before proposing types, database tables, or function names, check this file.
2. **Flag Ambiguity:** If a user request introduces a new concept or conflicting term, invoke `grill-with-docs` to clarify.
3. **Keep Living:** When a new domain entity is introduced and approved in a Spec, add it to this file immediately.
