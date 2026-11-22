---
name: simplify
description: Aggressive YAGNI and complexity reduction to eliminate over-engineering and dead code.
---

# Codebase Simplification & YAGNI

AI agents tend to over-engineer, creating premature abstractions, unused helper functions, and overly generic patterns. Use this skill to aggressively simplify code.

## Core Directives

1. **You Aren't Gonna Need It (YAGNI):**
   - Write code ONLY for the current requirement.
   - Do not add configuration flags, hooks, or parameters for speculative future use cases.

2. **Flatten Abstractions:**
   - Inline single-use functions or wrappers if they do not provide genuine domain clarity.
   - Prefer straightforward imperative code over convoluted multi-layered indirection.

3. **Dead Code Elimination:**
   - Delete unused exports, unreferenced utility functions, and stale comments.
   - If a test was testing code that no longer exists, clean it up.

4. **Principle of Least Astonishment:**
   - Make control flow obvious. Avoid clever metaprogramming or dynamic dispatch when a simple switch/if statement suffices.
