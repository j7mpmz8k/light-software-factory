---
name: domain-modeling
description: Type-first domain modeling and schema definition standards.
---

# Domain Modeling & Type-First Standards

Always design data contracts, types, and schema invariants before writing business logic or UI components.

## Rules of Domain Modeling

1. **Ubiquitous Language Compliance:**
   - Always reference `GLOSSARY.md` before naming entities, fields, or enums.
   - Reject ambiguous terms (e.g. using `workspace_id` when the glossary defines `organization_id`).

2. **Parse, Don't Validate:**
   - Define domain boundaries using runtime validation schemas (e.g., Zod, Valibot, or TypeScript type guards).
   - Invariants must be enforced at the boundary (API request handlers, DB ingest, webhook listeners).
   - Once parsed into a domain type, inner functions can trust the data without defensive re-validation.

3. **Make Illegal States Unrepresentable:**
   - Prefer tagged unions / discriminated unions over multiple optional boolean flags.
   - Example:
     ```ts
     // BAD
     type Order = { isPending: boolean; isShipped: boolean; trackingNumber?: string };

     // GOOD
     type Order = 
       | { status: 'pending' }
       | { status: 'shipped'; trackingNumber: string };
     ```

4. **Deep Modules (Ousterhout & Pocock Principle):**
   - Design modules with **narrow, simple interfaces and deep implementations**.
   - A deep module hides substantial domain logic, state management, and side effects behind a tiny public API (e.g. standard file I/O `open`/`read`/`write` hides entire filesystem drivers).
   - Reject **shallow modules** (modules where the interface is almost as complex as the implementation, such as 10 one-line getters, setters, or pass-through wrappers).
   - **Deterministic Testing Benefit:** When tests only assert against the public API of a deep module, the test remains 100% deterministic and tests observable behavior rather than internal implementation details. You can completely refactor the module's internals without breaking any tests.

5. **Database & Schema Synchronization:**
   - Migrations must match domain entity schemas 1:1.
   - Enforce database constraints (`NOT NULL`, foreign keys, unique indices) that mirror domain invariants.
