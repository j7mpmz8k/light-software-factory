# 🏭 Light Software Factory (`herdr-software-factory`)
### An Autonomous, Sovereign Multi-Agent Development Team in Docker

> **Welcome to your software factory.** This document is written for human operators to understand how the factory works, who is doing what, how it protects your codebase, and how you drive it day-to-day from your GitHub repository.

---

## 1. What Is the Light Software Factory?

The **Light Software Factory** is a private, containerized engineering team that turns GitHub Issues into tested, reviewed, and verified production code. 

Instead of treating AI like a single chat window, the factory models a real engineering organization:
* **One Senior Architect** decomposes high-level features, coordinates tasks, reviews code diffs, inspects visual screenshot evidence, and guards code quality.
* **Specialized Autonomous Builders** write features, run local databases, write comprehensive tests, and resolve issues in parallel.
* **A Turn-Serialized Bridge** manages incoming webhooks, bundles rapid human feedback, and ensures agents never step on each other's toes.
* **You (The Human Owner)** retain absolute sovereign control over production releases, database migrations, and sensitive security logic.

The entire system runs inside **8 lightweight Docker containers** on your own server or GPU host, completely isolated from your host files and credentials.

> 🚀 **Ready to launch your factory?** Follow the step-by-step [Quickstart & Setup Guide (docs/SETUP.md)](docs/SETUP.md). For deep architectural reference, see the complete [System Specification (docs/spec.md)](docs/spec.md).

---

## 2. System Architecture & Zero-Trust Isolation

```
                                🌐 GitHub (Issues, PRs, Webhooks)
                                              │
                      ┌───────────────────────┴───────────────────────┐
                      ▼                                               ▼
         ┌─────────────────────────┐                     ┌─────────────────────────┐
         │ 🚦 webhook-bridge (Hub) │                     │ 🛡️ human-gate-guard     │
         │   Priority Wait-Queue   │                     │   Runs on trusted master│
         │   8s Comment Coalescer  │                     └─────────────────────────┘
         └───────┬─────────────────┘
                 │
      ┌──────────┴──────────────────────────────────────┐
      │ Routes Human Comments & Ideas                   │ Routes CI & 'ready' Events
      ▼                                                 ▼
┌───────────────────────────┐             ┌───────────────────────────┐
│ 🧠 architect (Hermes)     │             │ ⚙️ senior-worker          │
│   Chief Architect / CTO   │             │   Factory Orchestrator    │
│   Persistent Context      │             │   Ephemeral Context       │
│   Discussions, Specs,     │             │   to-tickets, Reviews,    │
│   GLOSSARY.md & /handoff  │             │   Squash-merges, Relief   │
└───────────────────────────┘             └─────────────┬─────────────┘
                                                        │ Dispatches Sub-Issues via
                                                        │ dispatch-worker.sh (/clear)
                 ┌──────────────────────────────────────┼──────────────────────────┐
                 ▼                                      ▼                          ▼
         ┌───────────────┐                      ┌───────────────┐          ┌───────────────────────┐
         │ 🛠️ worker-     │                      │ 🛠️ worker-    │          │ 🔥 specialist-fable   │
         │   gemini      │                      │   qwen        │          │   Claude Code         │
         │ Antigravity   │                      │ Local GPU     │          │ 1-pass conflict/rescue│
         │ Flat Pro Sub  │                      │ 100% Free     │          │ IDLE 95% of the time  │
         └───────┬───────┘                      └───────┬───────┘          └───────────┬───────────┘
                 │                                      │                              │
                 ▼                                      ▼                              ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
 │ 🗄️ factory-postgres (db-net)                                                                    │
 │   4 Isolated Databases: app_gemini | app_qwen | app_senior | app_fable                          │
 │   Clean schema reset on every branch prep via .factory/prep-branch.sh                           │
 └─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Why It Is "Zero-Trust"
1. **Zero `docker.sock` Mounts:** No container can control Docker or escape to the host.
2. **Zero Raw API Keys in AI Containers:** API keys live exclusively inside `llm-proxy`, which enforces model allowlists and strict hourly spending caps.
3. **Execution-Free Hub:** The Architect never runs app builds or migrations directly. It stays completely separated from untrusted branch code and has no route to the database network (`db-net`).
4. **Isolated Per-Worker Databases:** Each builder has its own PostgreSQL database. A builder can wipe and recreate its own `public` schema between branches, but cannot touch another worker's database.

---

## 3. Meet the AI Roster

| Role | Container & Engine | Model | Primary Mission |
| :--- | :--- | :--- | :--- |
| **🧠 Chief Architect** | `herdr-hub`<br>*(Hermes CLI)* | **GLM-5.3** +<br>GLM-5.3-Flash Vision | **The Thinker & Technical Lead:** Your sole conversational partner on GitHub. Holds persistent memory of project history and conventions. Bounces ideas in Discussions, formulates Strawman specs with recommended defaults via `grill-with-docs`, enforces `GLOSSARY.md`, and performs warm resets via `/handoff`. Shielded from low-level CI logs and diffs. Supports automatic failover via `llm-proxy`. |
| **⚙️ Factory Orchestrator** | `herdr-hub`<br>*(Hermes CLI)* | **Gemini 4 Neon**<br>*(or DeepSeek / Frontier API)* | **The Doer & Assembly Foreman:** Operates in clean, ephemeral turns (wiped with `/clear` before each run). Runs as a dedicated tab inside `herdr-hub`. Wakes when an issue is `ready`, slices specs into vertical tracer bullets (`to-tickets` / `sub-issue.sh`), dispatches tasks to workers via `.factory/dispatch-worker.sh` (with `/clear`), inspects PR diffs and visual Playwright evidence (`pr-evidence-review`), and squash-merges to `staging`. Never writes code directly. |
| **🚦 Webhook Bridge** | `herdr-hub`<br>*(Node daemon)* | — | **Traffic Controller & Switchboard:** Routes human comments and ideas to the Architect, routes execution and CI events to the Orchestrator with pre-turn `/clear` wipes, serializes turns, catches post-merge `staging` regressions, and monitors worker stalls (>45 min). |
| **🛠️ Primary Worker** | `worker-gemini`<br>*(Antigravity CLI)* | **Gemini 3.8 Flash**<br>*(Google AI Pro)* | **Tier 1 (Flat-Rate Default):** Clean-on-dispatch task execution, strict Red-Green-Refactor TDD (`tdd`), backend/API logic, migrations, and **Final-Wave Playwright E2E tests** on your flat-rate Google AI Pro subscription. |
| **💻 Parallel Worker** | `worker-qwen`<br>*(Hermes CLI)* | **Local Qwen 3.8 27B**<br>*(Local GPU Host)* | **Tier 2 (Free & Parallel):** Clean-on-dispatch task execution for UI styling, components, unit tests, and overflow parallel capacity. |
| **💼 Senior Worker** | `senior-worker`<br>*(Hermes CLI)* | **Gemini 4 Neon**<br>*(or DeepSeek / Frontier API)* | **Tier 3 (Strict Relief Builder):** Frontier coding worker backed by `app_senior` DB. Dispatched **ONLY IF** `worker-gemini` is rate-limited (`blocked`) or incapacitated. Never called simply because Gemini is busy working (routine tasks wait in queue). |
| **🔥 Specialist** | `specialist-fable`<br>*(Claude Code)* | **Claude Fable** | **Tier 4 (SWAT Team):** Idle 95% of the time. Capped at strictly **1 pass per PR** for hairy merge conflicts or 3-strike CI loops. Never used for routine feature writing. |

---

### 3.1 The Matt Pocock Quality & Skills Suite

The factory integrates a curated suite of operational and architectural skills from Matt Pocock’s ecosystem:

* **[GLOSSARY.md](GLOSSARY.md):** The ubiquitous domain dictionary and source of truth across the factory. Every agent and prompt conforms to canonical terms (e.g. `Organization` over `Tenant`).
* **Strict TDD ([.agents/skills/tdd](.agents/skills/tdd/SKILL.md)):** Red-Green-Refactor enforcement. Workers must commit failing tests (RED) and confirm expected failure before writing implementation code (GREEN).
* **Domain Modeling ([.agents/skills/domain-modeling](.agents/skills/domain-modeling/SKILL.md)):** Type-first schema design, Zod validators, and invariants making illegal states unrepresentable.
* **Codebase Simplification ([.agents/skills/simplify](.agents/skills/simplify/SKILL.md)):** Aggressive YAGNI and complexity reduction to prevent AI over-engineering and dead code.
* **PR Authoring ([.agents/skills/pr](.agents/skills/pr/SKILL.md)):** Standardized pull requests containing verified test run outputs and Playwright visual screenshot evidence.
* **Objective Code Review ([.agents/skills/code-review](.agents/skills/code-review/SKILL.md)):** Rigorous QA rubric used by the Orchestrator for verifying PR diffs and screenshots against acceptance criteria.
* **Lossless Warm Handoff ([.agents/skills/handoff](.agents/skills/handoff/SKILL.md)):** Checkpoint skill for the Architect (`/handoff`), producing `HANDOFF.md` before wiping context, eliminating vendor lossy auto-compression.
* **Fluid Requirements Alignment ([.factory/role-skills/architect/grill-with-docs](.factory/role-skills/architect/grill-with-docs/SKILL.md)):** Strawman proposals with recommended defaults and "LGTM" fast-track, bypassing trivial bug fixes.
* **Continuous Retrospective ([.factory/role-skills/architect/retro](.factory/role-skills/architect/retro/SKILL.md)):** Automated post-release retrospective updating `AGENTS.md` and syncing skills on every merge to `master`.
* **Scheduled Codebase Hygiene ([.github/workflows/scheduled-hygiene.yml](.github/workflows/scheduled-hygiene.yml)):** Automated weekly cron audit running type checks, linters, and dependency audits in an isolated session.
* **Clean-on-Dispatch ([.factory/dispatch-worker.sh](.factory/dispatch-worker.sh)):** Automated `/clear` wipe sent to worker panes before dispatching Sub-Issues, ensuring every ticket starts with a fresh mind.
* **Automated Factory Verification Suite ([tests/](tests/)):** Automated unit and integration tests covering proxy rate limits, token minter JWTs, webhook signature validation, comment coalescing, priority queues, and shell scripts (`node --test tests/*.test.mjs && tests/test-scripts.sh`).

---

## 4. How You Drive the Factory: The 3 Human Touchpoints

You never need to babysit terminal logs or manage containers. You drive the entire factory through **GitHub Issues and Pull Requests**.

```
    [Your 3 Touchpoints]
    
    1. CREATE / PLAN            2. REVIEW SENSITIVE CHANGES         3. SHIP TO PRODUCTION
   ┌───────────────────┐       ┌───────────────────────────┐       ┌──────────────────────┐
   │ Feature Request   │       │ Kanban Column:            │       │ Rolling Release PR   │
   │ Label: "plan"     │ ────► │ "Awaiting Approval"       │ ────► │ staging -> master    │
   │ Review blueprint  │       │ Purple badge: human-gate  │       │ Approve -> Merge     │
   │ Swap to "ready"   │       │ Click Approve & Merge     │       │ ("Create merge")     │
   └───────────────────┘       └───────────────────────────┘       └──────────────────────┘
```

### Touchpoint 1: From Rough Idea to Autonomous Execution
1. **Discuss or Plan:** Open a **Feature Request** on GitHub (or start a Discussion).
   * **Casual Mode:** Chat freely without interrogation. The Architect acts as a conversational sparring partner.
   * **Planning Mode:** Apply the label **`plan`** or comment `/grill`.
2. **Strawman with Defaults:** The Architect analyzes [`GLOSSARY.md`](GLOSSARY.md) and your architecture, then posts a **Concrete Strawman Proposal** with recommended defaults and the **"LGTM" fast-track** (trivial bugfixes bypass grilling automatically).
3. **Align & Lock:**
   * If happy: Reply **"LGTM"** (done in 2 seconds).
   * If adjustments needed: Reply with changes; the Architect updates the spec.
4. **Handoff to Factory Automation:** Once the spec is locked, the Architect applies the label **`ready`**.
5. **Silent Factory Execution:** The **Factory Orchestrator** wakes up in a fresh, ephemeral session, slices the spec into atomic Sub-Issues via `to-tickets` / `.factory/sub-issue.sh`, and dispatches Wave 1 to workers via `.factory/dispatch-worker.sh` (sending `/clear` to workers before prompting).

### Touchpoint 2: The Single Column You Check — `Awaiting Approval`
The Kanban board has 7 columns, but you only ever need to look at **one**:
```
[Backlog] -> [Ready] -> [In Progress] -> [In Review] -> [Awaiting Approval] -> [Blocked] -> [Done]
                                                                ▲
                                                                │
                                                👉 (YOUR ATTENTION HERE)
```

Routine PRs flow straight to `staging` automatically once automated CI and the Orchestrator's evidence review approve them. However, any PR that touches:
* Database migrations or schema definitions (`migrations/`, `*.sql`, `prisma/`, `drizzle/`)
* Authentication or security logic (`auth/`, `security/`, `rbac/`)
* Core factory configuration or skills (`.github/`, `.factory/`, `.agents/`, `AGENTS.md`)
* Or carries a manual **`human-gate`** label

is immediately locked by `human-gate-guard`, badged with a purple **`human-gate`** tag, assigned to **you** as a formal GitHub Reviewer, and placed in **`Awaiting Approval`**.

**Your action:** Read the summary, click **Approve** in the PR review UI, wait ~5–10 seconds for the green checkmark, and click **Squash and merge**.

### Touchpoint 3: Shipping to Production (`staging -> master`)
Once all Sub-Issues for an Epic are merged to `staging`, the Orchestrator verifies the Epic is 100% complete and runs `.factory/release-pr.sh`, opening/updating **one rolling Release PR** (`staging -> master`) in **`Awaiting Approval`**.

**Your action:**
1. Review the aggregated release changelog written by the Architect.
2. Click **Approve**.
3. Merge using **"Create a merge commit"** (*never Squash!*). This keeps `staging` and `master` histories aligned forever.
4. **Continuous Learning:** Upon merging to `master`, the Architect automatically runs `retro`, extracting lessons learned into `AGENTS.md` and updating `GLOSSARY.md`.

### Touchpoint 4: Memory Management & Lossless Handoff (`/handoff`)
The Architect retains persistent context across features so it never suffers from amnesia. However, when you feel context is getting large after weeks of shipping:
* Type **`/handoff`** on any Issue or Discussion.
* The Architect produces a structured `HANDOFF.md` checkpoint (active invariants, decisions log, roadmap, and anti-patterns), clears its context window, and reboots warm with zero lost knowledge.

---

## 5. Built-In Guardrails (Why It Won't Break Things)

### Two Separate Bot Identities
* **`factory-worker[bot]`:** Used by Gemini, Qwen, and Fable.
* **`factory-architect[bot]`:** Used by the Architect.

Because all builders share the worker identity, GitHub treats them as the PR author. A bot **cannot approve or merge its own PR**. Every merge to `staging` requires the Architect's separate review.

### Tamper-Proof `human-gate-guard`
Runs directly from the trusted default branch (`master`) using GitHub's secure `pull_request_target` trigger. A rogue worker branch **cannot bypass the security gate by altering the workflow file**, because GitHub ignores the PR's version of the workflow.

### Post-Merge `staging` Regression Guard
When multiple parallel Wave PRs merge into `staging`, logical conflicts can slip through individual PR checks. Whenever code lands on `staging`, a post-merge CI run verifies the combined result. If anything breaks, the Architect immediately halts further merges and dispatches a targeted hotfix.

### Clean-Room Postgres Resets
Every time a worker switches branches, `.factory/prep-branch.sh` runs `DROP SCHEMA public CASCADE; CREATE SCHEMA public;`. Lingering test tables or uncommitted migration debris from previous branches can never contaminate new work.

---

## 6. Model Hygiene, Telemetry & Cost Controls

All LLM traffic for the Architect and Vision models routes through the internal **`llm-proxy`** sidecar.

### Real-Time Spend & Token Tracking
Check proxied usage and spend anytime from the host:
```bash
docker compose exec herdr-hub curl -s http://llm-proxy:4000/stats | jq .
```
You get rolling 1-hour request counts, total tokens consumed (prompt vs completion), and breakdown by model.

### Spend Circuit Breakers
`llm-proxy` strictly enforces hourly hard caps defined in your secrets configuration (e.g. 240 requests/hour for GLM, 60 requests/hour for Claude). If a runaway loop occurs, the proxy shuts off incoming calls and returns HTTP 429 before your wallet is drained.

### Hot-Swapping Models & Providers
Want to test a new model or switch providers? You never have to rebuild images. Use the built-in hot-swap utility:
```bash
# Hot-swap Architect model & vision
.factory/hotswap.sh architect deepseek-coder glm-5.3-flash

# Set or hot-swap Architect backup model (auto-failover on rate limits / 500s)
.factory/hotswap.sh backup deepseek-chat https://api.deepseek.com/v1

# Hot-swap Senior Worker model or API endpoint
.factory/hotswap.sh senior gemini-4-neon

# Hot-swap Qwen worker model or local inference server URL
.factory/hotswap.sh qwen qwen3.8:27b http://host.docker.internal:11434/v1

# Hot-swap Fable specialist model
.factory/hotswap.sh fable claude-3-7-sonnet-20250219
```
The script automatically updates `compose.env`, updates allowlists in `llm-proxy`, and restarts the targeted container in seconds without data loss.

---

## 7. Emergency Playbook: When Something Goes Wrong

* **PR shows `Blocked`:**
  A PR hit 3 CI failures or post-Fable issues. Inspect the Architect's comment on the PR. You can either push a commit yourself, post advice in a comment, or close the PR.
* **Watchdog alert on an Issue:**
  If an assigned worker goes silent for >45 minutes without pushing commits, the bridge pings the Architect. The Architect checks whether the worker crashed or hit rate limits, and either nudges it or overflows the task to another worker.
* **Live Interactive Herdr Workspace (Watch & Intervene):**
  If you ever want to see what the agents are actively typing in real-time or intervene directly from your laptop:
  ```bash
  docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh
  ```
  This opens the live 6-tab terminal interface (`bridge`, `architect`, `worker-gemini`, `worker-qwen`, `senior-worker`, `specialist-fable`). You can switch tabs, watch live output, or type directly into any agent pane to take over. Press `ctrl+b q` anytime to detach cleanly while leaving everything running.
