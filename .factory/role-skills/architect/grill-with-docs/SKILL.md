---
name: grill-with-docs
description: Fluid requirements alignment, strawman proposals with defaults, and targeted interrogation.
---

# Fluid Requirements Alignment (Grill With Docs)

The goal of this skill is to eliminate architectural ambiguities without frustrating the developer.
Keep interactions conversational, fast-track straightforward decisions with recommended defaults, and only interrogate when genuine architectural risk exists.

---

## 1. When to Engage (The Fluid Gate)

- **Casual Discussion Mode (Default):**
  In open GitHub Discussions, casual comments, or issues without the `plan` label, act as a helpful conversational partner. Bounce ideas, answer questions, and explore options naturally. **Do not interrogate.**

- **Formal Alignment Mode:**
  Engage this skill **only** when:
  1. An issue is explicitly labeled `plan` or `ready-to-spec`.
  2. The developer explicitly requests it (e.g., `/grill`, `/grill-me`, *"Grill me on this"*, or *"Turn this into a spec"*).

- **Trivial / Bug Bypass Threshold:**
  **Never grill on small-scope tasks.** Automatically bypass this skill if:
  - The task is a bugfix with a known stack trace or reproduction.
  - The task is a localized UI tweak, text copy change, dependency bump, or simple config update.
  - In bypass cases, log `[grill: bypassed - straightforward scope]`, post the proposed plan immediately, and proceed.

---

## 2. The "Strawman with Defaults" Pattern (Zero-Friction)

Never present the developer with a barrage of open-ended quiz questions. Instead, formulate a **Concrete Strawman Proposal** with clear recommended defaults.

### Structure of a Strawman Alignment Comment:
1. **Context & Objective:** 1 sentence confirming the core goal and checking `GLOSSARY.md`.
2. **Proposed Architectural Choices (With Defaults):**
   - Present 2 to 4 key technical decisions.
   - For every decision, state your recommended default clearly (e.g., `(Recommended) Option A`).
3. **The "LGTM" Fast-Track:**
   Explicitly tell the developer:
   > *"If you are happy with these defaults, reply **'LGTM'** or **'Proceed'** to lock the spec immediately. If you want to change any choice, let me know."*

---

## 3. Operating Modes

### Asynchronous Mode (GitHub Issue / Discussion Comment)
1. Read `GLOSSARY.md`, existing schema migrations, and relevant code.
2. If genuine architectural ambiguity exists (e.g., new DB entity, external API boundary, permissions):
   - Post the Strawman Proposal comment with recommended defaults and the "LGTM" fast-track.
   - Pause and wait for human feedback. Do not slice tickets until confirmed.
3. If the user replies with "LGTM", "Proceed", or confirms the defaults, immediately lock the Spec and transition to `to-tickets`.

### Interactive Mode (CLI / Terminal TTY)
1. When running locally in a terminal (stdin/TTY detected):
   - Print the Strawman summary with defaults.
   - Ask: *"Accept defaults [Y/n] or modify?"*
   - If accepted (default: enter/Y), synthesize the Spec instantly without tedious multi-step questioning.

---

## 4. Golden Rules
- **Respect Developer Velocity:** Enable 2-second alignment via "LGTM" whenever possible.
- **Enforce Ubiquitous Language:** If the user introduces a synonym conflicting with `GLOSSARY.md` (e.g. `Tenant` vs `Organization`), note the mapping in your strawman proposal.
- **Never Guess Silently:** Do not make hidden architectural assumptions without exposing them in your strawman defaults.
