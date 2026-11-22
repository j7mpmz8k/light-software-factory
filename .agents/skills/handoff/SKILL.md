---
name: handoff
description: Structured state checkpointing to reset LLM context without losing architectural memory.
---

# Lossless Context Handoff (The Warm Reset)

When conversational context becomes large, sluggish, or after shipping several major milestones, perform a structured handoff. 
Never rely on vendor auto-compression, which causes lossy memory loss, hallucinations, and forgotten architectural agreements.

---

## 1. When to Invoke
- **On Demand:** When the developer comments `/handoff`, `/checkpoint`, or asks to "clean up context".
- **Between Major Epics:** After completing a milestone and before starting a large new feature.
- **Context Bloat:** Whenever prompt latency increases noticeably.

---

## 2. Handoff Procedure

### Step 1: Generate `HANDOFF.md`
The Architect writes (or updates) `HANDOFF.md` in the repository root with this exact structure:

```markdown
# Architectural State & Handoff Checkpoint
*Generated at: <ISO-8601 Timestamp>*

## 1. System Overview & Invariants
- High-level architecture, active tech stack, and foundational packages.
- Critical non-negotiable patterns (e.g. database conventions, authentication flow).

## 2. Ubiquitous Vocabulary (Glossary References)
- Summary of core domain entities conforming strictly to `GLOSSARY.md`.

## 3. Key Architectural Decisions Log
- Recent trade-offs made and the rationale behind them.
- Reference to any entries added to `DECISIONS.md`.

## 4. Current State & Pending Roadmap
- What is currently deployed or merged into `staging`/`master`.
- What is currently in progress, blocked, or queued in the backlog.

## 5. Known Traps, Quirks & Anti-Patterns
- Framework gotchas, test flakiness patterns, or API quirks discovered during previous runs.
```

### Step 2: Post Confirmation on GitHub
Post a comment on the active issue or discussion:
> *"🤖 **[Architect]**: Checkpoint created in `HANDOFF.md`. Ready for warm reset."*

### Step 3: Execute Reset & Warm Reboot
1. Execute `/clear` in the terminal to wipe conversational history.
2. The newly cleared session immediately reads:
   - `HANDOFF.md`
   - `GLOSSARY.md`
   - `AGENTS.md`
3. Resume conversation with **zero loss of architectural memory** at a fraction of the token cost.
