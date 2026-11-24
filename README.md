# 🏭 Light Software Factory (`herdr-software-factory`)
### An Autonomous, Sovereign Multi-Agent Development Team in Docker

> **Welcome to your software factory.** This document is written for human operators to understand how the factory works, who is doing what, how it protects your codebase, and how you drive it day-to-day from your GitHub repository.

---

## 1. What Is the Light Software Factory?

The **Light Software Factory** is a private, containerized engineering team that turns GitHub Issues into tested, reviewed, and verified production code.

Instead of treating AI like a single chat window, the factory models a real engineering organization:
* **Chief Architect (GLM-5.3)** collaborates with you in persistent GitHub discussions, drafts specs, and guards domain vocabulary (`GLOSSARY.md`).
* **Factory Orchestrator (GLM-5.3 + Vision)** runs in clean, ephemeral turns, decomposes specs into vertical slices, selects the exact AI model per ticket, reviews PR diffs/screenshots, and squash-merges passing PRs to `staging`.
* **Three Isolated Builder Containers** execute in parallel with zero-trust isolation:
  1. **`worker-agy`** (Antigravity CLI — AI Ultra 5x) dynamically swaps between **Gemini 4 Carbon** (Wave 0 Golden E2E tests), **Gemini 4 Hydrogen** (fast routine tasks), **Gemini 4 Neon** (complex multi-file code), and **Claude Opus 5.5** (1-pass 3-strike rescues & merge conflicts).
  2. **`worker-qwen`** (Local Qwen 27B GPU) runs routine UI/styling/unit tests in parallel at $0 cost.
  3. **`worker-glm`** (GLM-5.3 via `llm-proxy`) acts as a cheap API overflow/backup builder so you never have to burn expensive Gemini credit spillover.
* **You (The Human Owner)** retain absolute sovereign control over production releases, database migrations, and sensitive security logic.

The entire system runs inside **7 lightweight Docker containers** on your own server or GPU host, completely isolated from your host files and credentials.

> 🚀 **Ready to launch your factory?** Follow the step-by-step [Quickstart & Setup Guide (docs/SETUP.md)](docs/SETUP.md). For deep architectural reference, see the complete [System Specification (docs/spec.md)](docs/spec.md).

---

## 2. System Architecture & Zero-Trust Isolation (7 Containers — A1 + B2)

```text
                          ┌─────────────────────────────────────┐
                          │   GitHub (Issues, PRs, Webhooks) │
                          └─────────────────────────────────────┘
                                           │
                     ┌───────────────────────┴───────────────────────────┐
                     ▼                                               ▼
    ┌────────────────────────────────────┐             ┌────────────────────────────────────┐
    │ webhook-bridge (herdr-hub)      │             │ human-gate-guard (GitHub CI)    │
    │ Priority Queue & 8s Coalescer   │             │ Runs from trusted main branch   │
    │ 3-Strike Rescue Circuit Breaker │             │ Locks migrations, auth, config  │
    │ 15m Worker Stall Watchdog       │             │ Surfaces PRs: Awaiting Approval │
    └────────────────────────────────────┘             └────────────────────────────────────┘
                     │
                     ├───────────────────────────────────────────────────┐
                     │ Issues & /architect                           │ PRs, CI & 'ready'
                     ▼                                               ▼
    ┌────────────────────────────────────┐             ┌────────────────────────────────────┐
    │ architect (herdr-hub)           │             │ orchestrator (herdr-hub)        │
    │ GLM-5.3 + GLM-5.3-Flash Vision  │             │ GLM-5.3 + GLM-5.3-Flash Vision  │
    │ Persistent Context (/handoff)   │             │ Ephemeral Context (/clear)      │
    │ Specs, Discussions, GLOSSARY.md │             │ to-tickets & --model Router     │
    │ Shielded from raw diffs & DB    │             │ PR Reviews & Squash-Merges      │
    └────────────────────────────────────┘             └────────────────────────────────────┘
                                                                     │ dispatch-worker.sh
               ┌─────────────────────────────┬────────────────────────────┴┐
               ▼                           ▼                          ▼
  ┌───────────────────────────┐   ┌────────────────────────────┐   ┌───────────────────────────┐
  │ worker-agy (Ultra 5x)   │   │ worker-qwen ($0 Local)  │   │ worker-glm (API Backup) │
  │ agy CLI (--model swap)  │   │ Hermes -> Local GPU     │   │ Hermes -> llm-proxy     │
  │ - Carbon   (Wave 0 E2E) │   │ Qwen 3.8 27B            │   │ GLM-5.3 (/worker-glm)   │
  │ - Hydrogen (Routine)    │   │ - UI & Styling          │   │ - Ultra 5x Backup       │
  │ - Neon     (Complex)    │   │ - Unit Tests            │   │ - 3rd Parallel Lane     │
  │ - Opus 5.5 (Rescues)    │   │ - Parallel Overflow     │   │ - Isolated Hourly Cap   │
  └───────────────────────────┘   └────────────────────────────┘   └───────────────────────────┘
               │                             │                             │
               ▼                             ▼                             ▼
  ┌──────────────────────────────────────────────────────────────────────────────────┐
  │ factory-postgres (internal db-net — zero access from herdr-hub)           │
  │ 3 Isolated Databases:  app_agy  |  app_qwen  |  app_glm  (30s timeout)    │
  │ Clean public schema reset before every branch via .factory/prep-branch.sh │
  └──────────────────────────────────────────────────────────────────────────────────┘
```

### Why It Is "Zero-Trust"
1. **Zero `docker.sock` Mounts:** No container can control Docker or escape to the host.
2. **Zero Herdr Socket Exposure to Workers:** Only `herdr-hub` holds the Herdr server socket; builder containers cannot access or steer the control plane.
3. **Zero Raw API Keys in AI Containers:** API keys live exclusively inside `llm-proxy`, which enforces model allowlists and separate hourly spending caps for the hub vs. `worker-glm`.
4. **Execution-Free Hub:** Neither the Architect nor the Orchestrator runs app builds or migrations directly; `herdr-hub` has no route to `db-net`.
5. **Isolated Per-Worker Databases:** Each builder owns its own PostgreSQL database (`app_agy`, `app_qwen`, `app_glm`) and resets its own `public` schema cleanly between branches.

---

## 3. Meet the AI Roster (7 Containers Total)

| Role | Container & Engine | Model(s) | Primary Mission |
| :--- | :--- | :--- | :--- |
| **🧠 Chief Architect** | `herdr-hub`<br>*(Hermes CLI)* | **GLM-5.3** +<br>GLM-5.3-Flash Vision | **The Thinker & Technical Lead:** Your sole conversational partner on GitHub. Holds persistent memory across features, drafts Strawman specs (`grill-with-docs`), enforces `GLOSSARY.md`, and performs warm resets via `/handoff`. Uses cheap GLM-5.3 credits so marathon chats never drain Ultra 5x quota. |
| **⚙️ Factory Orchestrator** | `herdr-hub`<br>*(Hermes CLI)* | **GLM-5.3** +<br>GLM-5.3-Flash Vision | **The Doer & Assembly Foreman:** Runs in clean ephemeral turns (`/clear` before every turn) on always-on GLM-5.3 so failover never stalls when Antigravity throttles. Slices specs into waves (`to-tickets`), picks the exact `--model` per ticket, inspects PR diffs & Playwright screenshots (`pr-evidence-review`), and squash-merges to `staging`. |
| **🚦 Webhook Bridge** | `herdr-hub`<br>*(Node daemon)* | — | **Traffic Controller & Spend Guard:** Routes Issue comments & `/architect` to Architect, routes Feature PR comments/reviews & CI events to Orchestrator, bundles comments within 8s, tracks per-PR CI strikes (3-strike rescue → spend circuit breaker), and monitors worker stalls (>45 min). |
| **⚡ Primary Multi-Model Builder & Senior/Specialist** | `worker-agy`<br>*(Antigravity CLI)* | **AI Ultra 5x** *(dynamic `--model`)*:<br>• `gemini-4-carbon-high` *(Wave 0 E2E)*<br>• `gemini-4-hydrogen-high` *(Routine)*<br>• `gemini-4-neon-high` *(Complex)*<br>• `claude-opus-5-5-high` *(Rescues)* | **Main Driver #1 + Combined Senior/Specialist:** Single isolated sandbox (`app_agy`) dynamically switched per task by `dispatch-worker.sh --model`. Authors Wave 0 black-box E2E tests, builds core features, and executes 1-pass cross-family rescues & merge conflict fixes. |
| **💻 Parallel Local Builder** | `worker-qwen`<br>*(Hermes CLI)* | **Local Qwen 3.8 27B**<br>*(Local GPU Host)* | **Main Driver #2 ($0 Cost):** Parallel clean-on-dispatch builder (`app_qwen`) for UI styling, components, unit tests, and boilerplate. |
| **🛡️ Cheap API Backup & Overflow Builder** | `worker-glm`<br>*(Hermes CLI)* | **GLM-5.3**<br>*(via `llm-proxy`)* | **Quota Backup & 3rd Parallel Slot:** Isolated builder (`app_glm`, separate hourly cap) that takes over routine tasks whenever Ultra 5x throttles (avoiding expensive Gemini credit spillover) or adds a 3rd parallel lane on large waves. |

---

### 3.1 The Matt Pocock Quality & Skills Suite

The factory integrates a curated suite of operational and architectural skills:

* **[GLOSSARY.md](GLOSSARY.md):** The ubiquitous domain dictionary across the factory (including *Deep Module* vs. *Shallow Module* and canonical entity terms).
* **Strict Behavioral TDD ([.agents/skills/tdd](.agents/skills/tdd/SKILL.md)):** Red-Green-Refactor focused on **black-box determinism** at module/CLI boundaries (avoiding brittle internal mocks).
* **Domain Modeling ([.agents/skills/domain-modeling](.agents/skills/domain-modeling/SKILL.md)):** Type-first schema design, Zod validators, discriminated unions, and **Deep Modules** (narrow interfaces hiding deep implementations).
* **Codebase Simplification ([.agents/skills/simplify](.agents/skills/simplify/SKILL.md)):** Aggressive YAGNI and shallow-wrapper elimination.
* **Conflict & Rescue Playbook ([.agents/skills/conflict-and-rescue](.agents/skills/conflict-and-rescue/SKILL.md)):** 1-pass merge conflict & 3-strike rescue protocol for `worker-agy` (`claude-opus-5-5-high` / `gemini-4-carbon-high`).
* **PR Authoring & Code Review ([.agents/skills/pr](.agents/skills/pr/SKILL.md), [.agents/skills/code-review](.agents/skills/code-review/SKILL.md)):** Standardized PR evidence and objective review rubrics.
* **Lossless Warm Handoff ([.agents/skills/handoff](.agents/skills/handoff/SKILL.md)):** Checkpoint skill (`/handoff`) for the Architect before `/clear`.
* **Fluid Requirements Alignment & Retro ([.factory/role-skills/architect/grill-with-docs](.factory/role-skills/architect/grill-with-docs/SKILL.md), [.factory/role-skills/architect/retro](.factory/role-skills/architect/retro/SKILL.md)):** Strawman defaults with "LGTM" fast-track and post-release continuous learning.
* **Scheduled Codebase Hygiene ([.github/workflows/scheduled-hygiene.yml](.github/workflows/scheduled-hygiene.yml)):** Automated weekly cron audit for types, linting, and regression tests.
* **Dynamic Model Clean-on-Dispatch ([.factory/dispatch-worker.sh](.factory/dispatch-worker.sh)):** Swaps `--model` cleanly on `worker-agy` and sends `/clear` on Hermes workers before every Sub-Issue.
* **Automated Factory Verification Suite ([tests/](tests/)):** Unit and integration tests covering `llm-proxy`, `token-refresher`, `webhook-bridge` (including strike circuit breaker), and shell scripts (`node --test tests/*.test.mjs && tests/test-scripts.sh`).

---

## 4. How You Drive the Factory: The 3 Human Touchpoints

You drive the entire factory through **GitHub Issues and Pull Requests**:

```text
  1. CREATE / PLAN                 2. REVIEW SENSITIVE PRs            3. SHIP TO PRODUCTION
┌─────────────────────────┐      ┌───────────────────────────┐      ┌────────────────────────────┐
│ Feature Request       │      │ Kanban Column:          │      │ Rolling Release PR      │
│ Label: "plan"         │ ───► │ "Awaiting Approval"     │ ───► │ staging -> main         │
│ Review blueprint      │      │ Badge: human-gate       │      │ Approve -> Merge        │
│ Swap to "ready"       │      │ Click Approve & Merge   │      │ ("Create merge commit") │
└─────────────────────────┘      └───────────────────────────┘      └────────────────────────────┘
```

### Touchpoint 1: From Rough Idea to Autonomous Execution
1. **Discuss or Plan:** Open a **Feature Request** on GitHub and apply **`plan`** (or comment `/grill`).
2. **Strawman with Defaults:** The Architect posts a concrete Strawman spec referencing [`GLOSSARY.md`](GLOSSARY.md). Reply **"LGTM"** to fast-track.
3. **Handoff via `ready` Label:** Once locked, apply **`ready`**.
4. **Wave 0 → Wave N Execution:** The **Orchestrator** wakes up cleanly (`/clear`), slices the spec via `to-tickets`, dispatches **Wave 0 (Golden E2E Acceptance Test)** to `worker-agy --model gemini-4-carbon-high`, then dispatches Wave 1+ implementation across `worker-agy` (`hydrogen`/`neon`), `worker-qwen`, and `worker-glm`.

### Touchpoint 2: The Single Column You Check — `Awaiting Approval`
Routine PRs auto-merge to `staging` once CI and Orchestrator review pass. Any PR touching database migrations, auth/security, `.github/`, `.factory/`, `.agents/`, or `AGENTS.md` is locked by `human-gate-guard` and placed in **`Awaiting Approval`** for your review and squash-merge.

### Touchpoint 3: Shipping to Production (`staging -> main`)
When an Epic finishes on `staging`, `.factory/release-pr.sh` opens/updates the rolling Release PR in **`Awaiting Approval`**. Approve and merge with **"Create a merge commit"** (*never Squash!*). Merging triggers the Architect's `retro` skill.

---

## 5. Built-In Guardrails & Spend Controls

* **Two Separate Bot Identities:** Builders authenticate as `factory-worker[bot]`; the Hub authenticates as `factory-architect[bot]`. Builders can never self-approve or merge their own PRs.
* **Tamper-Proof `human-gate-guard`:** Executes from your trusted default branch (`main`/`master`) via `pull_request_target` so worker branches cannot weaken CI or security checks.
* **3-Strike Rescue & Spend Circuit Breaker:** `webhook-bridge.mjs` tracks consecutive CI failures per PR. On Strike 3, it escalates strictly **1 pass** to `worker-agy --model claude-opus-5-5-high`. If CI fails again after rescue, automated retries **halt immediately** (`blocked` label + board `Blocked`) so runaway loops never drain your quota or credits overnight.
* **Isolated `llm-proxy` Telemetry & Hourly Caps:**
  ```bash
  docker compose exec herdr-hub curl -s http://llm-proxy:4000/stats | jq .
  ```
  `hub` (`/glm`, `/vision`) and `worker-glm` (`/worker-glm`) have **separate hourly rate limits** (`GLM_MAX_REQ_PER_HOUR` vs `GLM_WORKER_MAX_REQ_PER_HOUR`), so `worker-glm` can never starve your Architect/Orchestrator.

### Hot-Swapping Models & Providers
```bash
# Hot-swap Architect model & vision
.factory/hotswap.sh architect glm-5.3 glm-5.3-flash

# Hot-swap Orchestrator model
.factory/hotswap.sh orchestrator glm-5.3

# Hot-swap default worker-agy model (used when --model is omitted)
.factory/hotswap.sh agy-default gemini-4-hydrogen-high

# Hot-swap local Qwen model or inference URL
.factory/hotswap.sh qwen qwen3.8:27b http://host.docker.internal:11434/v1

# Hot-swap worker-glm model
.factory/hotswap.sh glm glm-5.3
```

---

## 6. Live Interactive Herdr Workspace
To watch all 6 tabs (`bridge`, `architect`, `orchestrator`, `worker-agy`, `worker-qwen`, `worker-glm`) live or intervene directly:
```bash
docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh
```
Press `ctrl+b q` anytime to detach cleanly while leaving everything running.
