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
         └────────────┬────────────┘
                      │ Wakes & prompts via Herdr CLI
                      ▼
         ┌─────────────────────────┐
         │ 🧠 architect (Hermes)   │ ◄─── Zero DB access, Zero raw keys
         │    GLM-5.3 & Vision     │ ◄─── Evaluates diffs, approves to staging
         └────────────┬────────────┘
                      │ Dispatches atomic Sub-Issues over internal SSH (port 2222)
         ┌────────────┼──────────────────────────┬──────────────────────────┐
         ▼            ▼                          ▼                          ▼
 ┌───────────────┐ ┌───────────────┐ ┌───────────────────────┐ ┌───────────────────────┐
 │ 🛠️ worker-     │ │ 🛠️ worker-    │ │ ⭐ senior-worker      │ │ 🔥 specialist-fable   │
 │   gemini      │ │   qwen        │ │   Hermes (Gemini/API) │ │   Claude Code         │
 │ Antigravity   │ │ Local GPU     │ │ Frontier API Relief   │ │ 1-pass conflict/rescue│
 │ Flat Pro Sub  │ │ 100% Free     │ │ IDLE until needed     │ │ IDLE 95% of the time  │
 └───────┬───────┘ └───────┬───────┘ └───────────┬───────────┘ └───────────┬───────────┘
         │                 │                     │                         │
         ▼                 ▼                     ▼                         ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────┐
 │ 🗄️ factory-postgres (db-net)                                                        │
 │   4 Isolated Databases: app_gemini | app_qwen | app_senior | app_fable              │
 │   Clean schema reset on every branch prep                                           │
 └─────────────────────────────────────────────────────────────────────────────────────┘
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
| **🧠 Architect** | `herdr-hub`<br>*(Hermes CLI)* | **GLM-5.3** +<br>GLM-5.3-Flash Vision | **Orchestrator & Reviewer:** Plans Epics into atomic Sub-Issues, inspects PR diffs, downloads and inspects Playwright screenshot evidence with Vision, squash-merges routine PRs to `staging`, and opens rolling Release PRs. Supports automatic failover to backup models via `llm-proxy`. |
| **🚦 Webhook Bridge** | `herdr-hub`<br>*(Node daemon)* | — | **Traffic Controller:** Buffers human comments (8s window), serializes agent turns, catches post-merge `staging` CI breakages, and monitors for stalled workers (>45 min). |
| **🛠️ Primary Worker** | `worker-gemini`<br>*(Antigravity CLI)* | **Gemini 3.8 Flash**<br>*(Google AI Pro)* | **Heavy Lifter:** High-speed, high-volume feature building, backend/API logic, migrations, and **Final-Wave Playwright E2E tests** (in fresh, stateless sessions). |
| **💻 Parallel Worker** | `worker-qwen`<br>*(Hermes CLI)* | **Local Qwen 3.8 27B**<br>*(Local GPU Host)* | **Free & Parallel:** UI styling, components, unit tests, narrow 1–2 screen cross-model verification, and overflow capacity if Gemini hits rolling rate limits. |
| **⭐ Senior Worker** | `senior-worker`<br>*(Hermes CLI)* | **Gemini 4 Neon**<br>*(or DeepSeek / Frontier API)* | **High-Difficulty Relief:** Steps in for complex architectural slices, difficult algorithmic refactors, or when Antigravity quota is depleted. Idles when not needed to conserve API spend. |
| **🔥 Specialist** | `specialist-fable`<br>*(Claude Code)* | **Claude Fable** | **On-Demand SWAT Team:** Idle 95% of the time. Capped at strictly **1 pass per PR** for hairy merge conflicts or 3-strike CI loops. Never used for routine feature writing. |

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
1. Open a **Feature Request** on GitHub and apply the label **`plan`**.
2. The Architect wakes up, syncs `/workspace`, analyzes your architecture, and breaks the feature down into **atomic Sub-Issues** (each with its own explicit Test Plan).
3. The Architect posts a **Wave Blueprint** comment on the parent Issue and **stops**.
4. You review the blueprint. If you want changes, reply on the Issue (the Bridge bundles your comments and informs the Architect).
5. When satisfied, apply the label **`ready`**. The Architect claims the first wave and assigns sub-tasks to idle workers.

### Touchpoint 2: The Single Column You Check — `Awaiting Approval`
The Kanban board has 7 columns, but you only ever need to look at **one**:
```
[Backlog] -> [Ready] -> [In Progress] -> [In Review] -> [Awaiting Approval] -> [Blocked] -> [Done]
                                                                ▲
                                                                │
                                                👉 (YOUR ATTENTION HERE)
```

Routine PRs flow straight to `staging` automatically once automated CI and the Architect approve them. However, any PR that touches:
* Database migrations or schema definitions (`migrations/`, `*.sql`, `prisma/`, `drizzle/`)
* Authentication or security logic (`auth/`, `security/`, `rbac/`)
* Core factory configuration or skills (`.github/`, `.factory/`, `.agents/`, `AGENTS.md`)
* Or carries a manual **`human-gate`** label

is immediately locked by `human-gate-guard`, badged with a purple **`human-gate`** tag, assigned to **you** as a formal GitHub Reviewer, and placed in **`Awaiting Approval`**.

**Your action:** Read the Architect's summary, click **Approve** in the PR review UI, wait ~5–10 seconds for the green checkmark, and click **Squash and merge**.

### Touchpoint 3: Shipping to Production (`staging -> master`)
Once all Sub-Issues for an Epic are merged to `staging`, the Architect runs a Final-Wave Playwright E2E verification in a clean environment. When green, it closes the parent Epic and opens/updates **one rolling Release PR** (`staging -> master`) in **`Awaiting Approval`**.

**Your action:**
1. Review the aggregated release changelog.
2. Click **Approve**.
3. Merge using **"Create a merge commit"** (*never Squash!*). This keeps `staging` and `master` histories aligned forever.

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
