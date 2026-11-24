# Light Software Factory (`herdr-software-factory`) — External Bootstrap Agent Setup Specification

> **Instructions for Executing Agent (External Host Bootstrap Agent):**
> You are an **external setup/bootstrap agent running on the host machine**—you are **NOT** the persistent Architect that will later operate inside `herdr-hub`. Your sole job is to construct, configure, build, and verify the sandboxed **`herdr-software-factory`** stack from **Phase 1 to Phase 11**, then hand off day-to-day operations to the human operator and the newly launched `architect` pane inside `herdr-hub`.
>
> **Bootstrap Guardrails:**
> - Execute sequentially from **Phase 1 to Phase 11**, verifying each phase before proceeding.
> - **Auto-populate placeholders:** Dynamically detect the repository owner/name (`gh repo view --json nameWithOwner -q .nameWithOwner`) and human GitHub username (`gh api user -q .login`), and substitute them into `.github/CODEOWNERS`, `.github/workflows/human-gate-guard.yml`, and `~/.config/light-factory/bridge.env`—never commit literal `<YOUR_GITHUB_USERNAME>` placeholders.
> - **Adapt stack commands:** Inspect the repository's existing tech stack (`package.json`, ORM, test runner, etc.) and adapt the build/lint/migration/test commands in `.github/workflows/ci-evidence.yml` accordingly.
> - **STOP and prompt the human operator** whenever you encounter a `[HUMAN ACTION REQUIRED]` block (GitHub App creation, secret file placement, Project Board UI toggles, webhook registration, initial `staging -> master` bootstrap merge, or one-time OAuth logins).
> - **Confirm container CLI installers before Phase 10:** Before running `docker compose up -d --build`, ask the human (if not already provided) for the exact install commands for **Hermes CLI (`hermes`)** in `.factory/docker/Dockerfile.hub` + `Dockerfile.worker` and **Antigravity CLI (`agy`)** in `.factory/docker/Dockerfile.worker`.
> - **Never request or commit secrets:** Never ask the human to paste `.pem` keys, `GLM_API_KEY`, `ANTHROPIC_API_KEY`, or tokens into chat—always let the human write those directly into `~/.config/light-factory/` on the host. Never commit `.env`, `.pem`, SSH private keys, DB passwords, webhook secrets, or runtime state files.

---

## 0. System Architecture — Sandboxed `herdr-software-factory` Stack

From the host machine (Docker Desktop or `docker compose ps`), the entire factory appears as **one self-contained entity: `herdr-software-factory`**. Inside, **7 sibling containers** run across **three** private Docker networks (`factory-net`, `llm-net`, and internal `db-net`) with **zero access to your host `$HOME`**, **zero `docker.sock` mounting**, **zero Herdr socket exposure to workers**, **zero raw API keys inside any AI container**, and **zero Docker-in-Docker (`--privileged`)**.

### Native Herdr Visibility Across Sandboxed Containers (Zero `docker.sock`)
Each worker container is reached from `herdr-hub` over private `factory-net` via a dedicated internal-only SSH key (port `2222`, `AllowTcpForwarding no`) wrapped with Herdr's official **`HERDR_AGENT=<kind>`** screen-detection hint (`agy`, `hermes`) and named via `herdr agent rename`. This preserves **100% of Herdr's native multi-agent workflow** inside **one unified `herdr agent list`**:
- Real-time **`idle` / `working` / `blocked` / `done`** status rollups in the Herdr sidebar and CLI for all 5 agents (`architect`, `orchestrator`, `worker-agy`, `worker-qwen`, `worker-glm`).
- Native cross-agent coordination (`herdr agent list`, `herdr agent prompt`, `herdr agent wait`, `herdr agent read`, `herdr agent send-keys`), taught automatically to the Architect and Orchestrator via `herdr --skill` installed on boot.
- Zero `docker.sock` exposure to any AI container.

### Model Roster (A1 + B2 — GLM-5.3 Control Plane + Dynamic Multi-Model Antigravity Ultra 5x + Local Qwen + GLM Backup)
- **🧠 Chief Architect (`architect` tab inside `herdr-hub`):** **GLM-5.3** inside **Hermes** (`hermes --profile architect`) with `auxiliary.vision` routed to **GLM-5.3-Flash**. Maintains **persistent conversational context** with the human developer across features, holds high-level system design, writes specs, strawman defaults, and enforces `GLOSSARY.md`. Can be losslessly checkpointed via `/handoff`. Stays **execution-free** (no app builds, no direct Postgres access) while burning cheap GLM-5.3 credits so marathon planning chats never consume Ultra 5x quota.
- **⚙️ Factory Orchestrator (`orchestrator` tab inside `herdr-hub`):** **GLM-5.3** inside **Hermes** (`hermes --profile orchestrator`) with `auxiliary.vision` routed to **GLM-5.3-Flash**. Operates with **ephemeral context** (wiped via `/clear` before every wave planning or PR review turn). Running on unthrottled GLM-5.3 guarantees the control plane never stalls if Antigravity throttles—enabling seamless failover to `worker-qwen` and `worker-glm`. Decomposes specs (`to-tickets`), selects the exact `--model` per ticket via `.factory/dispatch-worker.sh`, inspects PR diffs and Playwright screenshots (`pr-evidence-review`), and squash-merges to `staging`.
- **🚦 Turn-Serialized Priority Queue, Comment Coalescer, Strike Circuit Breaker & Watchdog (`bridge` tab inside `herdr-hub`):** `webhook-bridge.mjs` persists pending GitHub events to disk, prioritizes **human comments** ahead of background CI/`plan` webhooks, bundles rapid comments within an 8s window, routes human chats to Architect and execution/CI events to Orchestrator (with `/clear`), tracks per-PR CI strikes (Strike 3 $\to$ 1-pass Opus 5.5/Carbon rescue; Strike 4 $\to$ spend circuit breaker `blocked`), catches post-merge `staging` regressions, and runs a 15-minute stall watchdog (>45 min).
- **⚡ Primary Multi-Model Builder & Combined Senior/Specialist (`worker-agy` container -> `HERDR_AGENT=agy`):** Single isolated Antigravity CLI sandbox on **Google AI Ultra 5x** (`app_agy` DB). Dynamically switched per ticket by `dispatch-worker.sh --model`:
  - **Wave 0 Golden E2E Acceptance Tests:** `gemini-4-carbon-high` (black-box deterministic tests + fixtures, proving RED before coding).
  - **Wave 1–2 Routine Tasks:** `gemini-4-hydrogen-high` (fast default).
  - **Wave 1–2 Complex Tasks:** `gemini-4-neon-high` (multi-file backend, migrations, deep-module refactors).
  - **1-Pass 3-Strike Rescues & Merge Conflicts:** `claude-opus-5-5-high` (or `gemini-4-carbon-high`) using `conflict-and-rescue`.
- **💻 Parallel Local GPU Builder (`worker-qwen` container -> `HERDR_AGENT=hermes`):** **Local Qwen 3.8 27B** inside **Hermes** (`hermes --profile qwen`), reaching host GPU inference server, backed by isolated Postgres DB (`app_qwen`). $0 cost for UI, styling, unit tests, and parallel execution.
- **🛡️ Cheap API Overflow & Quota Backup (`worker-glm` container -> `HERDR_AGENT=hermes`):** **GLM-5.3** inside **Hermes** (`hermes --profile glm`), routed through dedicated `llm-proxy` `/worker-glm` route with its own isolated hourly spend cap and Postgres DB (`app_glm`). Steps in whenever Ultra 5x throttles (avoiding expensive Gemini credit spillover) or adds a 3rd parallel builder lane on large waves.
- **🧩 Plan-First Decomposition, Wave 0 E2E & Rolling Release PR:** Rough or multi-step Issues labeled `plan` are clarified with Strawman defaults (`grill-with-docs`) conforming to `GLOSSARY.md`. Once approved (`ready`), the Orchestrator decomposes the spec into atomic **native GitHub Sub-Issues** via `.factory/sub-issue.sh`, dispatches Wave 0 E2E to `worker-agy --model gemini-4-carbon-high`, then dispatches Wave 1+ across `worker-agy`, `worker-qwen`, and `worker-glm`. Whenever an Epic finishes on `staging`, the Orchestrator opens/updates **one rolling `staging -> master` Release PR** (via `.factory/release-pr.sh`) in **`Awaiting Approval`**. Upon merge to `master`, the Architect triggers `retro`.
- **🛡️ Single-Pane `Awaiting Approval` Board + Trusted-Branch `human-gate-guard`:** Routine PRs flow to `staging` without extra labels once `ci-and-evidence` and `human-gate-guard` pass. `human-gate-guard.yml` executes from the trusted `master` branch and locks protected paths or manual `human-gate` tags.
- **📚 Curated Quality & Pocock Skills Suite:** Shared coding/domain skills (`GLOSSARY.md`, `tdd`, `domain-modeling`, `simplify`, `conflict-and-rescue`, `pr`, `code-review`, `handoff`, `grill-with-docs`, `retro`) are distributed via `.factory/sync-skills.sh`, paired with `.github/workflows/scheduled-hygiene.yml` for weekly quality audits.

### Zero-Trust Container, Secret, Database & GitHub App Isolation
Each tier is isolated across **four** boundaries: container/network isolation (`factory-net`, `llm-net`, `db-net`), zero-key sidecars (`auth-minter` + `llm-proxy`), per-worker Postgres isolation (`factory-postgres`), and GitHub server-side locks (**2 GitHub Apps** + **3 Stacked Rulesets** + **trusted `human-gate-guard`**):

| Container / Role | Network(s) | Can See | Completely Blind To |
| :--- | :--- | :--- | :--- |
| **`auth-minter`** *(No LLM, no repo)* | `factory-net` | Host GitHub `.pem` keys (`:ro`), `apps.env` (`:ro`) | Repo code, LLM API keys, Postgres, inbound internet |
| **`llm-proxy`** *(No LLM, no repo)* | `llm-net` | Host `llm-secrets.env` (`:ro`), model allowlist, isolated hourly caps (`/glm` vs `/worker-glm`), `/stats` telemetry | Repo code, GitHub `.pem` keys, Postgres, `worker-agy`/`worker-qwen` |
| **`factory-postgres`** *(Postgres 16)* | `db-net` *(internal)* | 3 isolated non-superuser DBs (`app_agy`, `app_qwen`, `app_glm`) | Internet, host `$HOME`, `herdr-hub`, GitHub/LLM secrets |
| **`herdr-hub`** *(Herdr + Bridge + Architect + Orchestrator)* | `factory-net`, `llm-net` | `auth-architect:ro`, dummy proxy key, own `/workspace`, `bridge.env:ro`, shared + architect + orchestrator + `herdr` skills | Host `$HOME`, `.pem` keys, **real API keys**, `docker.sock`, **`factory-postgres`**, AGY OAuth |
| **`worker-agy`** *(Antigravity CLI — Multi-Model)* | `factory-net`, `db-net` | `auth-worker:ro`, own `/workspace`, own `agy-auth`/`agy-dotgemini`, `app_agy` DB, shared domain + rescue skills | Host `$HOME`, `.pem` keys, `llm-proxy`, `hub-herdr`, `architect` token, `app_qwen`/`app_glm` DBs |
| **`worker-qwen`** *(Hermes Local Qwen)* | `factory-net`, `db-net` | `auth-worker:ro`, own `/workspace`, host GPU port, `app_qwen` DB, shared domain skills | Host `$HOME`, `.pem` keys, `llm-proxy`, `hub-herdr`, `architect` token, `app_agy`/`app_glm` DBs |
| **`worker-glm`** *(Hermes GLM-5.3 Backup)* | `factory-net`, `llm-net`, `db-net` | `auth-worker:ro`, own `/workspace`, isolated `GLM_WORKER_PROXY_TOKEN` (`/worker-glm`), `app_glm` DB, shared domain skills | Host `$HOME`, `.pem` keys, **real API keys**, `hub-herdr`, `architect` token, `app_agy`/`app_qwen` DBs |

> **Why `worker-agy`, `worker-qwen`, and `worker-glm` Share One `factory-worker` App:**
> Because all execution containers authenticate as `factory-worker[bot]`, GitHub treats them as the **same PR author**—so no worker can rubber-stamp or self-merge its own commits, E2E tests, or rescue fixes. Every PR must pass CI (`ci-and-evidence`) + server-enforced `human-gate-guard` and be formally approved by `factory-architect[bot]` (or You for gated paths/`human-gate`/production `master` PRs).

```text
                        ┌──────────────────────────────────────────────┐
                        │                    GITHUB                    │
                        │  7-Column Board (incl. `Awaiting Approval`)  │
                        │  Stacked Rulesets + Trusted human-gate-guard │
                        │  PR CI + Post-Merge `staging` CI (Postgres)  │
                        │  Rolling Release PR: staging -> master (You) │
                        └───────────────┬───────────────────▲──────────┘
                                        │ Host Tunnel       │ 1h App Tokens (HTTPS)
                                        │ 127.0.0.1:8787    │
┌───────────────────────────────────────▼───────────────────┴──────────────────┐
│  DOCKER COMPOSE STACK: herdr-software-factory  (7 Containers — A1 + B2)      │
│                                                                              │
│  ┌───────────────────────────────┐     ┌──────────────────────────────────┐  │
│  │ Container: auth-minter        │     │ Container: llm-proxy (:4000)     │  │
│  │  • ONLY sees host .pem keys   │     │  • ONLY sees llm-secrets.env     │  │
│  │  • Mints 1h tokens every 45m  │     │  • Injects GLM/Vision headers    │  │
│  └──────┬──────────────────┬─────┘     │  • Separate Hub & Worker caps    │  │
│         │ vol:             │ vol:      └──────────┬───────────────┬───────┘  │
│         │ auth-architect   │ auth-worker          │ llm-net       │ llm-net  │
│         ▼ (:ro)            ▼ (:ro)                ▼ (/glm,/vision)│(/worker- │
│  ┌────────────────────────────────────────┐                       │ glm)     │
│  │ Container: herdr-hub                   │ Identity: factory-architect[bot] │
│  │  • Tab: bridge (Q + 3-strike breaker)  │ Execution-free (NO db-net route) │
│  │  • Tab: architect (GLM-5.3 + Vision)   │ Zero AGY auth needed in hub      │
│  │  • Tab: orchestrator (GLM-5.3 + Vision)│ Dynamic --model dispatch         │
│  └───┬──────────────────┬────────────┬────┘                       │          │
│      │ internal SSH     │            │ internal SSH               │          │
│      ▼ (agy --model)    ▼ (hermes)   ▼ (hermes)                   ▼          │
│  ┌────────────────┐ ┌──────────────┐ ┌────────────────────────────────────┐  │
│  │ worker-agy     │ │ worker-qwen  │ │ worker-glm (Cheap API Backup)      │  │
│  │ Antigravity 5x │ │ Hermes Local │ │ Hermes + GLM-5.3 via /worker-glm   │  │
│  │ Carbon/Neon/   │ │ Qwen 3.8 27B │ │ Overflow & 3rd Parallel Builder    │  │
│  │ Hydrogen/Opus  │ │ $0 Local GPU │ │ Isolated hourly spend cap          │  │
│  │ app_agy        │ │ app_qwen     │ │ app_glm                            │  │
│  └──────┬─────────┘ └──────┬───────┘ └─────────────────┬──────────────────┘  │
│         │ db-net           │ db-net                    │ db-net              │
│         └──────────────────┼───────────────────────────┘                     │
│                            ▼                                                 │
│        ┌───────────────────────────────────────────────────────┐             │
│        │ Container: factory-postgres (Postgres 16, internal)   │             │
│        │  • 3 locked-down non-superuser DBs (REVOKE PUBLIC)    │             │
│        │  • Extensions isolated in `extensions` schema         │             │
│        │  • app_agy | app_qwen | app_glm (30s timeout)         │             │
│        └───────────────────────────────────────────────────────┘             │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Host Prerequisites & Initial Bootstrap Auth

### 1.1 Verify Host Tools on the GPU Server
Run the following checks on the host machine (used by the Host Bootstrap Agent for initial setup and starting the Docker stack):

```bash
docker --version          # Docker Engine / Docker Desktop
docker compose version    # Must be Compose v2 (`docker compose`, not legacy `docker-compose`)
git --version
gh --version              # Must be >= 2.97.0 (for name-based `gh project item-edit`)
jq --version              # Required for parsing GraphQL/REST IDs during setup
openssl version           # Required for generating webhook & DB secrets
ssh-keygen -V || true     # Required for generating internal container-to-container SSH keypair
```

### 1.2 Ensure Host GPU Inference Server Is Reachable From Docker
Because `worker-qwen` (and optionally `llm-proxy` if pointed to a local model) runs inside Docker, your local Qwen 3.8 27B inference server (e.g., Ollama on `:11434`, vLLM/llama.cpp on `:8000`/`:8080`) must listen on the Docker bridge interface (or `0.0.0.0` firewalled to localhost/Docker bridge—never public internet) so containers can reach it at `http://host.docker.internal:<GPU_PORT>/v1`.

### 1.3 Initial Human Bootstrap Auth (Host Setup Only)
> **[HUMAN ACTION REQUIRED]**
> Confirm `gh auth status` is logged into your personal GitHub account on the host with `repo`, `workflow`, and `project` scopes (`gh auth refresh -s project` if missing).
> - *Note: Your personal `gh` config on the host is **never** mounted into any `herdr-software-factory` container. It is used strictly by the Host Bootstrap Agent during Phases 4–5 to create labels, Rulesets, and the Project Board.*

**Phase 1 Verification:** `docker compose version` returns v2+, `gh --version` is `>= 2.97.0`, `jq --version` succeeds, and `gh api user -q .login` returns the human owner's GitHub username.

---

## Phase 2: Role-Based Authorization — GitHub Apps, Token Minter & Zero-Key `llm-proxy`

### 2.1 Register Two Private GitHub Apps & Configure Host Secret Vault
> **[HUMAN ACTION REQUIRED]**
> Create **two** GitHub Apps under **GitHub Settings -> Developer settings -> GitHub Apps -> New GitHub App** (or under your Organization's Developer Settings if this is an org repo).
>
> For **both** apps:
> - **Homepage URL:** `https://github.com/<owner>/<repo>`
> - **Webhook:** **Uncheck "Active"** (webhooks stay configured on the repo directly in Phase 9).
> - **Where can this GitHub App be installed?** Select **"Only on this account"**.
>
> #### App 1: `factory-architect` *(Tech Lead / Reviewer — Hermes GLM-5.3)*
> - **Repository permissions:**
>   - `Contents`: **Read and write** *(merge staging, commit `AGENTS.md`/`DECISIONS.md`)*
>   - `Issues`: **Read and write** *(create specs & native Sub-Issues, swap labels, comment)*
>   - `Pull requests`: **Read and write** *(approve/merge staging PRs, request human reviews, open/update rolling `staging -> master` Release PR)*
>   - `Actions`: **Read-only** *(inspect CI run logs & download Playwright evidence artifacts)*
>   - `Metadata`: **Read-only** *(mandatory)*
> - **Organization permissions *(only if using an Organization repo + Org Project Board)*:**
>   - `Projects`: **Read and write**
> - Click **Create GitHub App** -> note the **App ID** -> click **Generate a private key** (downloads `.pem`) -> click **Install App** -> select **Only select repositories** -> pick **this repository only** -> copy the **Installation ID** from the resulting URL (`.../installations/<INSTALLATION_ID>`).
>
> #### App 2: `factory-worker` *(Peer Execution Workers — Antigravity Multi-Model `worker-agy`, Local `worker-qwen`, & Backup `worker-glm`)*
> - **Repository permissions:**
>   - `Contents`: **Read and write** *(push `feature/*` branches; `staging`/`master` locked by Rulesets)*
>   - `Pull requests`: **Read and write** *(open/update PRs and reply to reviews)*
>   - `Issues`: **Read-only** *(read specs & Sub-Issues via `gh issue view`)*
>   - `Actions`: **Read-only** *(read failing CI logs via `gh run view`)*
>   - `Metadata`: **Read-only** *(mandatory)*
> - Click **Create GitHub App** -> note the **App ID** -> click **Generate a private key** (downloads `.pem`) -> click **Install App** -> select **Only select repositories** -> pick **this repository only** -> copy the **Installation ID** from the resulting URL.
>
> #### Store Private Keys & LLM API Keys Strictly on the Host (`~/.config/light-factory/`)
> **Bootstrap Agent Note:** You may create the directory skeleton and generate the internal SSH keypair, but **do NOT ask the human to paste `.pem` keys or API keys into chat**—let the human populate `keys/*.pem`, `apps.env`, and `llm-secrets.env` directly on the host:
```bash
mkdir -p ~/.config/light-factory/keys ~/.config/light-factory/internal-ssh
chmod 700 ~/.config/light-factory ~/.config/light-factory/keys ~/.config/light-factory/internal-ssh

mv ~/Downloads/*factory-architect*.pem ~/.config/light-factory/keys/architect.pem
mv ~/Downloads/*factory-worker*.pem    ~/.config/light-factory/keys/worker.pem
chmod 600 ~/.config/light-factory/keys/*.pem

# Generate dedicated internal-only SSH keypair for herdr-hub -> worker containers (zero host SSH keys used)
ssh-keygen -t ed25519 -N "" -C "herdr-hub-internal" -f ~/.config/light-factory/internal-ssh/id_ed25519
cp ~/.config/light-factory/internal-ssh/id_ed25519.pub ~/.config/light-factory/internal-ssh/authorized_keys
chmod 600 ~/.config/light-factory/internal-ssh/id_ed25519
chmod 644 ~/.config/light-factory/internal-ssh/authorized_keys

cat <<'EOF' > ~/.config/light-factory/apps.env
ARCHITECT_APP_ID=<paste_architect_app_id>
ARCHITECT_INSTALLATION_ID=<paste_architect_installation_id>
ARCHITECT_KEY_PATH=/run/factory-keys/architect.pem
ARCHITECT_SLUG=factory-architect

WORKER_APP_ID=<paste_worker_app_id>
WORKER_INSTALLATION_ID=<paste_worker_installation_id>
WORKER_KEY_PATH=/run/factory-keys/worker.pem
WORKER_SLUG=factory-worker
EOF
chmod 600 ~/.config/light-factory/apps.env

# LLM API keys & upstream inference servers (mounted :ro ONLY into llm-proxy — NEVER into any AI container)
cat <<'EOF' > ~/.config/light-factory/llm-secrets.env
# 1. Architect Primary Inference Server (OpenAI-compatible: Z.ai, OpenRouter, DeepInfra, or local host.docker.internal)
GLM_UPSTREAM_URL=https://api.z.ai/api/coding/paas/v4
GLM_API_KEY=<paste_your_real_glm_api_key>

# 2. Architect Vision Inference Server (leave blank to reuse GLM_UPSTREAM_URL & GLM_API_KEY above)
VISION_UPSTREAM_URL=
VISION_API_KEY=

# 3. Optional separate endpoint/key for worker-glm (leave blank to reuse GLM settings above)
GLM_WORKER_UPSTREAM_URL=
GLM_WORKER_API_KEY=

# 4. Hard hourly circuit breakers (prevents runaway loop spend; isolated buckets)
GLM_MAX_REQ_PER_HOUR=240
GLM_WORKER_MAX_REQ_PER_HOUR=180
EOF
chmod 600 ~/.config/light-factory/llm-secrets.env
```
> *(Optional — Personal Accounts Only: If this is a personal repo rather than an Organization repo, GitHub currently restricts GitHub Apps from mutating user-owned Projects v2 boards. To keep the Kanban board synced without exposing your full account to workers, you may add `GH_PROJECT_TOKEN=<classic_token_with_project_scope_only>` to `~/.config/light-factory/apps.env`. `auth-minter` will copy it exclusively into the `auth-architect` volume—workers never see it.)*

### 2.2 Create Local Factory Directories & `.gitignore` Entries
```bash
mkdir -p .factory/bin .factory/docker .factory/postgres \
         .factory/role-skills/architect/pr-evidence-review \
         .factory/role-skills/orchestrator/pr-evidence-review \
         .factory/role-skills/orchestrator/to-tickets \
         .agents/skills/conflict-and-rescue \
         .agents/skills/modern-web-standards \
         .agents/skills/postgres-migrations \
         .agents/skills/e2e-testing \
         .github/workflows .github/ISSUE_TEMPLATE
```

Append the following to `.gitignore` (avoiding duplicates):
```gitignore
# Light Software Factory local runtime state & secrets
.factory/.env
.factory/retry-state.json
.factory/architect-queue.json
.factory/bridge.log
*.pem
playwright-report/
test-results/
```

### 2.3 Create 1-Hour GitHub Token Minter (`.factory/token-refresher.mjs`)
Create `.factory/token-refresher.mjs` (`chmod +x .factory/token-refresher.mjs`).
Inside `auth-minter`, this zero-dependency Node.js daemon mints fresh **1-hour** installation tokens (`ghs_...`) every **45 minutes** into two separate Docker volumes (`/run/factory-auth/architect` and `/run/factory-auth/worker`).

> 📂 **Live Implementation:** [`\.factory/token-refresher\.mjs`](file:///home/admin/Github/light-software-factory/.factory/token-refresher.mjs)

```javascript
// Key Interface Contract: Generates RS256 JWT, calls GitHub installations API, writes 1h token
async function refreshAll() {
  const cfg = loadEnvFile(APPS_ENV_PATH);
  await mintInstallationToken("architect", cfg.ARCHITECT_APP_ID, cfg.ARCHITECT_INSTALLATION_ID, cfg.ARCHITECT_KEY_PATH, cfg.ARCHITECT_SLUG);
  await mintInstallationToken("worker", cfg.WORKER_APP_ID, cfg.WORKER_INSTALLATION_ID, cfg.WORKER_KEY_PATH, cfg.WORKER_SLUG);
}
// Automatically schedules refresh every 45 minutes (retrying in 60s on error)
scheduleNextRefresh(REFRESH_MS);
```

### 2.4 Create Zero-Key LLM Proxy Sidecar With `/stats` Telemetry (`.factory/llm-proxy.mjs`)
Create `.factory/llm-proxy.mjs` (`chmod +x .factory/llm-proxy.mjs`).
Runs exclusively inside the `llm-proxy` container. Keeps real API keys completely outside every AI container, injects real upstream auth headers in flight, enforces a strict model allowlist and isolated hourly request caps, and exposes **`GET /stats`** tracking request counts and prompt/completion tokens across proxied API routes (`/glm`, `/vision`, `/backup`, and `/worker-glm`).
> *Telemetry Scope Note:* `/stats` tracks metered API calls passing through `llm-proxy` (Hub GLM-5.3 Architect/Orchestrator, GLM-5.3-Flash Vision, and `worker-glm` backup). Direct Antigravity Ultra 5x CLI (`worker-agy`) and local GPU Qwen (`worker-qwen`) bypass `llm-proxy` by design.

> 📂 **Live Implementation:** [`\.factory/llm-proxy\.mjs`](file:///home/admin/Github/light-software-factory/.factory/llm-proxy.mjs)

```javascript
// Key Interface Contract: Exposes /glm, /vision, /backup, /worker-glm, /health, and /stats
// Strips dummy proxy tokens, validates model allowlists, enforces isolated hub vs worker-glm hourly caps
const server = http.createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/stats") return sendJson(res, 200, telemetry);
  // Enforces hourly request caps and streams request/response usage telemetry
});
server.listen(PORT, "0.0.0.0");
```

### 2.5 Create Role-Isolated `gh` Wrapper, Git Credential Helper & Role Loader
Create `.factory/bin/gh`, `.factory/git-credential-factory.sh`, and `.factory/enter-role.sh` (`chmod +x` all three).

**File 1: `.factory/bin/gh`**
> 📂 **Live Implementations:**
> - [`\.factory/bin/gh`](file:///home/admin/Github/light-software-factory/.factory/bin/gh) *(Role-isolated GitHub CLI wrapper)*
> - [`\.factory/git-credential-factory\.sh`](file:///home/admin/Github/light-software-factory/.factory/git-credential-factory.sh) *(Live token Git credential helper)*
> - [`\.factory/enter-role\.sh`](file:///home/admin/Github/light-software-factory/.factory/enter-role.sh) *(Environment and bot committer identity loader)*

```bash
# Usage inside container sessions:
source .factory/enter-role.sh <architect|worker>
# Sets live App bot committer email: ${USER_ID}+${BOT_SLUG}[bot]@users.noreply.github.com
# Routes git operations through x-access-token credential helper
```

**Phase 2 Verification:** Confirm (via `test -s`, without printing secret contents) that `~/.config/light-factory/keys/{architect,worker}.pem`, `~/.config/light-factory/internal-ssh/id_ed25519`, `~/.config/light-factory/apps.env`, and `~/.config/light-factory/llm-secrets.env` all exist with `600` permissions, and `.factory/token-refresher.mjs`, `.factory/llm-proxy.mjs`, `.factory/bin/gh`, `.factory/git-credential-factory.sh`, and `.factory/enter-role.sh` are executable.

---

## Phase 3: Docker Sandbox Stack (`herdr-software-factory`) & Isolated Postgres

Every container maintains its own **independent repo clone** inside its own Docker volume (`/workspace`), each worker receives its own **locked-down Postgres database** inside `factory-postgres` via `DATABASE_URL` (with clean schema reset between branches), and Hermes / Claude Code / skill paths (including Herdr's built-in `herdr --skill` for the Architect) are **auto-synced on container boot**.

### 3.1 Create Container Helpers: Skill Sync, Hub Sync, Vision Evidence Fetch & Clean Branch Prep
Create all four scripts (`chmod +x` each):

**File 1: `.factory/sync-skills.sh`**
Links repo-tracked progressive-disclosure skills into each agent's native skill directory on boot and before each branch, and installs Herdr's release-matched `herdr --skill` exclusively into the Architect's Hermes skills directory so GLM-5.3 natively masters Herdr multi-agent orchestration.

> 📂 **Live Implementation:** [`\.factory/sync-skills\.sh`](file:///home/admin/Github/light-software-factory/.factory/sync-skills.sh)
>
> Links `.agents/skills/*` into every worker (`worker-agy`, `worker-qwen`, `worker-glm`), plus profile-specific role skills for `architect` (`grill-with-docs`, `retro`, `herdr`) and `orchestrator` (`to-tickets`, `pr-evidence-review`, `herdr`).

**File 2: `.factory/sync-hub.sh`**
Keeps `herdr-hub`'s `/workspace` fast-forwarded to `origin/staging` (and refreshes Architect skills) so the Architect never plans Epics against stale files or hits push rejections when appending rules to `AGENTS.md` / `DECISIONS.md`.

```bash
#!/usr/bin/env bash
# Usage: .factory/sync-hub.sh (runs strictly inside herdr-hub / architect role)
set -euo pipefail

if [ "${FACTORY_ROLE:-}" != "architect" ]; then
  echo "[sync-hub] Skipping: intended only for herdr-hub (architect role)." >&2
  exit 0
fi

cd /workspace
if [ -n "$(git status --porcelain)" ]; then
  echo "[sync-hub] WARNING: /workspace has uncommitted edits; skipping pull to avoid clobbering." >&2
  exit 0
fi

git fetch origin staging --quiet
git checkout staging --quiet
if ! git pull --ff-only origin staging --quiet; then
  echo "[sync-hub] WARNING: Non-fast-forward divergence on staging; manual check needed." >&2
  exit 0
fi

if [ -x /workspace/.factory/sync-skills.sh ]; then
  /workspace/.factory/sync-skills.sh architect
fi

echo "[sync-hub] herdr-hub /workspace synced to origin/staging ($(git rev-parse --short HEAD))."
```

**File 3: `.factory/fetch-evidence.sh`**
Downloads & unzips Playwright screenshot artifacts from GitHub Actions into `/tmp/pr-evidence/` inside `herdr-hub` so Hermes `auxiliary.vision` (GLM-5.3-Flash via `llm-proxy/vision`) can inspect actual local image files directly from disk.

```bash
#!/usr/bin/env bash
# Usage: .factory/fetch-evidence.sh <run_id> <pr_number>
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <run_id> <pr_number>" >&2
  exit 1
fi

RUN_ID="$1"
PR_NUM="$2"
ARTIFACT_NAME="pr-${PR_NUM}-evidence"
OUT_DIR="/tmp/pr-evidence/pr-${PR_NUM}-run-${RUN_ID}"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

if ! /workspace/.factory/bin/gh run download "$RUN_ID" --name "$ARTIFACT_NAME" --dir "$OUT_DIR" 2>/dev/null; then
  echo "[fetch-evidence] No '${ARTIFACT_NAME}' artifact found on run #${RUN_ID} (non-Playwright or skipped E2E run)."
  exit 0
fi

echo "[fetch-evidence] Downloaded '${ARTIFACT_NAME}' into ${OUT_DIR}"
IMAGES="$(find "$OUT_DIR" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) | sort || true)"

if [ -n "$IMAGES" ]; then
  echo "[fetch-evidence] Screenshot files ready for Hermes Vision inspection:"
  printf '%s\n' "$IMAGES"
else
  echo "[fetch-evidence] Artifact extracted (no PNG/JPG screenshots found; inspect HTML/trace reports in ${OUT_DIR})."
fi
```

**File 4: `.factory/prep-branch.sh`**
Run inside any worker container's `/workspace` before starting a unique Sub-Issue, standalone task, Final-Wave E2E test, or conflict resolution. Resets Git cleanly, wipes leftover tables/migrations in the worker's isolated Postgres `public` schema (while keeping pre-installed extensions safe in the `extensions` schema), refreshes dependencies if the lockfile changed, and re-syncs skills.

```bash
#!/usr/bin/env bash
# Usage: .factory/prep-branch.sh <issue_number_or_branch> [short_slug] [--keep-db]
set -euo pipefail

KEEP_DB=false
ARGS=()
for arg in "$@"; do
  if [ "$arg" = "--keep-db" ]; then
    KEEP_DB=true
  else
    ARGS+=("$arg")
  fi
done

if [ ${#ARGS[@]} -lt 1 ]; then
  echo "Usage: $0 <issue_number_or_branch> [short_slug] [--keep-db]"
  echo "  Examples:"
  echo "    $0 14 auth-api"
  echo "    $0 feature/issue-14-auth-api"
  exit 1
fi

TARGET="${ARGS[0]}"
SLUG="${ARGS[1]:-task}"

if [[ "$TARGET" == feature/* ]]; then
  BRANCH_NAME="$TARGET"
else
  BRANCH_NAME="feature/issue-${TARGET}-${SLUG}"
fi

cd /workspace

hash_lockfiles() {
  sha256sum package-lock.json pnpm-lock.yaml yarn.lock 2>/dev/null || true
}
BEFORE_LOCK_HASH="$(hash_lockfiles)"

git fetch origin staging

# Abort any lingering conflict state before resetting cleanly
git merge --abort 2>/dev/null || true
git reset --hard HEAD
git clean -fd

if git ls-remote --exit-code --heads origin "$BRANCH_NAME" >/dev/null 2>&1; then
  git fetch origin "$BRANCH_NAME"
  git checkout -B "$BRANCH_NAME" "origin/$BRANCH_NAME"
  if ! git merge --no-edit origin/staging; then
    echo "MERGE_CONFLICT detected on $BRANCH_NAME against origin/staging."
    exit 2
  fi
else
  git checkout -B "$BRANCH_NAME" origin/staging
fi

# Refresh Node dependencies if lockfile changed or node_modules is missing
AFTER_LOCK_HASH="$(hash_lockfiles)"
if [ -f package-lock.json ] && { [ ! -d node_modules ] || [ "$BEFORE_LOCK_HASH" != "$AFTER_LOCK_HASH" ]; }; then
  echo "[prep-branch] Lockfile changed or node_modules missing — running npm ci..."
  npm ci --no-audit --no-fund
elif [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1 && { [ ! -d node_modules ] || [ "$BEFORE_LOCK_HASH" != "$AFTER_LOCK_HASH" ]; }; then
  echo "[prep-branch] Lockfile changed or node_modules missing — running pnpm install --frozen-lockfile..."
  pnpm install --frozen-lockfile
fi

# Reset isolated worker Postgres `public` schema cleanly so prior-branch tables never pollute migrations/E2E
# (Superuser extensions live safely in the separate `extensions` schema)
if [ "$KEEP_DB" = false ] && [ -n "${DATABASE_URL:-}" ] && command -v psql >/dev/null 2>&1; then
  echo "[prep-branch] Resetting isolated Postgres public schema for ${WORKER_NAME:-worker}..."
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO CURRENT_USER;" >/dev/null
fi

# Refresh progressive-disclosure skill links in case staging added/updated skills
if [ -x /workspace/.factory/sync-skills.sh ] && [ -n "${WORKER_NAME:-}" ]; then
  /workspace/.factory/sync-skills.sh "$WORKER_NAME"
fi

echo "Container /workspace ready on branch $BRANCH_NAME (clean DB + synced deps/skills for ${WORKER_NAME:-worker})"
```
> **Exit Code `2` (`MERGE_CONFLICT`):** Leaves exact conflict markers in `/workspace` for Senior/Specialist rescue on `worker-agy --model claude-opus-5-5-high` (or `gemini-4-carbon-high`)—or signals routine workers to run `git merge --abort` and escalate to the Orchestrator.

**File 5: `.factory/dispatch-worker.sh`**
Used by the Orchestrator to dispatch Sub-Issues to idle workers. Supports dynamic `--model <id>` switching for `worker-agy` (defaulting to `gemini-4-hydrogen-high`) and sends `/clear` to Hermes workers (`worker-qwen`, `worker-glm`), ensuring every ticket begins with the right model and a clean mental slate.

> 📂 **Live Implementation:** [`\.factory/dispatch-worker\.sh`](file:///home/admin/Github/light-software-factory/.factory/dispatch-worker.sh)

### 3.2 Create Isolated Multi-Worker Postgres Init Script (`.factory/postgres/init-dbs.sh`)
Create `.factory/postgres/init-dbs.sh` (`chmod +x .factory/postgres/init-dbs.sh`).
Provisions **3 locked-down, non-superuser databases** (`app_agy`, `app_qwen`, `app_glm`) with `REVOKE ALL ON DATABASE ... FROM PUBLIC`, a `30s` statement timeout, and a dedicated **`extensions` schema** (on each worker's `search_path`) so `.factory/prep-branch.sh` can safely run `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` as a non-superuser without dropping or requiring superuser rights for `pgcrypto` / `uuid-ossp`.

> 📂 **Live Implementation:** [`\.factory/postgres/init-dbs\.sh`](file:///home/admin/Github/light-software-factory/.factory/postgres/init-dbs.sh)
*(ORM Note: If the repository uses **Prisma `migrate dev`**, which requires a shadow database, either use `prisma migrate deploy` + `prisma db push` in workers or grant `CREATEDB` in the `CREATE ROLE` line above.)*

### 3.3 Create Shared Container Workspace Bootstrapper (`.factory/docker/bootstrap-workspace.sh`)
Create `.factory/docker/bootstrap-workspace.sh` (`chmod +x .factory/docker/bootstrap-workspace.sh`).

> 📂 **Live Implementation:** [`\.factory/docker/bootstrap-workspace\.sh`](file:///home/admin/Github/light-software-factory/.factory/docker/bootstrap-workspace.sh)

```bash
# Clones repository into isolated /workspace using live 1h GitHub App token
# Resiliently clones 'staging' or falls back to default branch if staging is not yet on remote
```

### 3.4 Create `herdr-hub` Image & Auto-Configured Hermes Entrypoint
Create `.factory/docker/Dockerfile.hub` *(Bootstrap Agent: confirm the exact `hermes` CLI install line with the human before Phase 10 build)*:

> 📂 **Live Implementations:**
> - [`\.factory/docker/Dockerfile\.hub`](file:///home/admin/Github/light-software-factory/.factory/docker/Dockerfile.hub) *(Hardened Herdr + Hermes Hub image)*
> - [`\.factory/docker/entrypoint-hub\.sh`](file:///home/admin/Github/light-software-factory/.factory/docker/entrypoint-hub.sh) *(Auto-configures Hermes Architect profile & boots headless Herdr server)*

### 3.5 Create Worker Sandbox Image & Auto-Configured Entrypoint
Create `.factory/docker/Dockerfile.worker` (includes `postgresql-client` AND **Playwright Chromium OS dependencies** preinstalled as root so non-root workers can run local Playwright E2E tests without root privileges; non-web repos without Playwright may comment out the `playwright install-deps` line to keep the image smaller):

> 📂 **Live Implementations:**
> - [`\.factory/docker/Dockerfile\.worker`](file:///home/admin/Github/light-software-factory/.factory/docker/Dockerfile.worker) *(Hardened worker sandbox with Playwright, Node, Python, Antigravity CLI, and Hermes)*
> - [`\.factory/docker/Dockerfile\.minter`](file:///home/admin/Github/light-software-factory/.factory/docker/Dockerfile.minter) *(Dedicated non-root token minter image with pre-created 1000:1000 volumes)*
> - [`\.factory/docker/entrypoint-worker\.sh`](file:///home/admin/Github/light-software-factory/.factory/docker/entrypoint-worker.sh) *(Auto-configures profiles for Qwen and GLM backup worker)*

### 3.6 Create Master Compose Stack (`docker-compose.yml` -> `herdr-software-factory`)
Create `docker-compose.yml` in `<repo-root>`.
Notice the **three-network isolation**:
- `llm-net`: connects ONLY `llm-proxy`, `herdr-hub`, and `worker-glm` (`worker-agy` and `worker-qwen` cannot reach `llm-proxy`).
- `db-net` (`internal: true`): connects ONLY `factory-postgres` and the 3 execution workers (`herdr-hub` stays execution-free and cannot reach Postgres).

> 📂 **Live Implementation:** [`docker-compose\.yml`](file:///home/admin/Github/light-software-factory/docker-compose.yml)

The compose configuration orchestrates **7 hardened sibling containers**:
- `auth-minter`: 1-hour GitHub token refresher
- `llm-proxy`: Zero-key GLM-5.3 API proxy, isolated hub vs `worker-glm` spend caps, and `/stats` telemetry
- `factory-postgres`: Multi-tenant isolated Postgres server (`app_agy`, `app_qwen`, `app_glm`)
- `herdr-hub`: Headless Herdr server, Webhook Bridge, Chief Architect (GLM-5.3), and Factory Orchestrator (GLM-5.3 + Vision)
- `worker-agy`: Multi-model Antigravity Ultra 5x builder + combined Senior/Specialist (Carbon, Neon, Hydrogen, Opus 5.5)
- `worker-qwen`: Free local GPU builder (Qwen 3.8 27B)
- `worker-glm`: Cheap GLM-5.3 API overflow & quota backup builder

**Phase 3 Verification:** `docker compose --env-file ~/.config/light-factory/compose.env config -q` exits `0` (verified via `.factory/preflight.sh`), confirming valid Compose v2 syntax for all 7 containers, and `.factory/{sync-skills,sync-hub,fetch-evidence,prep-branch,dispatch-worker}.sh` are executable.

---

## Phase 4: Repository Branches, 6-Label Taxonomy, Issue Forms, `CODEOWNERS` & Stacked Rulesets

### 4.1 Enforce HTTPS Remote & Branch Topology (`feature/*` -> `staging` -> `master`)
```bash
REPO_FULL=$(gh repo view --json nameWithOwner -q .nameWithOwner)
git remote set-url origin "https://github.com/${REPO_FULL}.git"

git fetch origin
git show-ref --verify --quiet refs/heads/staging || git checkout -b staging
git push -u origin staging
git checkout staging
```
*(Bootstrap Agent Note: If the repository uses `main` instead of `master`, adapt branch references consistently across this guide, `.factory/release-pr.sh`, the Rulesets below, and `.github/workflows/*.yml`.)*

### 4.2 Create the 6 Active Automation Labels
Every label below drives a concrete automation behavior. Redundant labels (`auto-staging`, `epic`, `feature`, `factory-rule`) are intentionally omitted: routine PRs flow to `staging` by default, parent Epics are detected natively via GitHub's Sub-Issues API, and high-risk paths are auto-locked by `human-gate-guard` (and auto-badged with `human-gate` on the Project Board).

```bash
gh label create "plan"            --color "D4C5F9" --description "Rough/multi-step idea; triggers Architect to decompose into Sub-Issues & pause" --force
gh label create "ready"           --color "0E8A16" --description "Approved Epic (with Sub-Issues) or atomic task; triggers Architect dispatch" --force
gh label create "in-progress"     --color "FBCA04" --description "Claimed by Architect and actively running in worker sandbox(es)" --force
gh label create "human-gate"      --color "5319E7" --description "Requires human owner approval & merge (manual override, auto-badged protected path, or Release PR)" --force
gh label create "blocked"          --color "D93F0B" --description "CI retry cap exceeded or agent needs human input" --force
gh label create "rescue-escalated" --color "B60205" --description "Escalated once to worker-agy Senior/Specialist (hard 1-pass cap)" --force
```

### 4.3 Create `.github/CODEOWNERS` (Locks `master` to Human Approval)
Bootstrap Agent: populate `<YOUR_GITHUB_USERNAME>` automatically via `GH_OWNER_LOGIN=$(gh api user -q .login)`:

```text
# Only the human repository owner can satisfy Code Owner review on master
* @<YOUR_GITHUB_USERNAME>
```

### 4.4 Create Feature Request Issue Form (`.github/ISSUE_TEMPLATE/feature-request.yml`)

> 📂 **Live Implementation:** [`.github/ISSUE_TEMPLATE/feature-request.yml`](file:///home/admin/Github/light-software-factory/.github/ISSUE_TEMPLATE/feature-request.yml)

### 4.5 Create Atomic Task / Sub-Issue Spec Template (`.github/ISSUE_TEMPLATE/feature-spec.md`)
> 📂 **Live Implementation:** [`.github/ISSUE_TEMPLATE/feature-spec.md`](file:///home/admin/Github/light-software-factory/.github/ISSUE_TEMPLATE/feature-spec.md)



### 4.6 Create PR Template (`.github/PULL_REQUEST_TEMPLATE.md`)

> 📂 **Live Implementation:** [`.github/PULL_REQUEST_TEMPLATE.md`](file:///home/admin/Github/light-software-factory/.github/PULL_REQUEST_TEMPLATE.md)

### 4.7 Enforce Hard Server-Side Locks via Stacked GitHub Rulesets
> **Plan Requirement Note:** GitHub Repository Rulesets are free on **public repos** and require **GitHub Pro / Team / Enterprise** on **private repos**.

Notice Ruleset #1 enforces **both** `ci-and-evidence` **and** the commit status `human-gate-guard` (published strictly from trusted `master` directly onto `pr.head.sha`) with **zero bypasses**—so GitHub physically blocks even `factory-architect[bot]` from merging any PR targeting `master`, touching protected paths, or carrying `human-gate` until you approve the current commit SHA:

```bash
set -euo pipefail
source ~/.config/light-factory/apps.env
REPO_FULL=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# 1. Hard Safety (NO BYPASS) — Applies to master AND staging for everyone
gh api --method POST "/repos/${REPO_FULL}/rulesets" --input - <<EOF
{
  "name": "Factory: Hard Safety (No Bypass)",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/master", "refs/heads/staging"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": true,
        "required_status_checks": [
          { "context": "ci-and-evidence" },
          { "context": "human-gate-guard" }
        ]
      }
    }
  ]
}
EOF

# 2. Gate master (Human Owner Only) — Neither Hub nor Workers can merge or push
gh api --method POST "/repos/${REPO_FULL}/rulesets" --input - <<EOF
{
  "name": "Factory: Gate master (Human Only)",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "always"
    }
  ],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/master"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    }
  ]
}
EOF

# 3. Gate staging (Hub Review & Merge; Execution Workers Hard-Blocked)
gh api --method POST "/repos/${REPO_FULL}/rulesets" --input - <<EOF
{
  "name": "Factory: Gate staging (Architect Only)",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "always"
    },
    {
      "actor_id": ${ARCHITECT_APP_ID},
      "actor_type": "Integration",
      "bypass_mode": "always"
    }
  ],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/staging"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    }
  ]
}
EOF
```

> **[HUMAN ACTION REQUIRED — Only if `gh api` above returns HTTP 403/422]**
> If your repo is a **private personal repo on GitHub Free**, upgrade to GitHub Pro (or make the repo public / move to a GitHub Team org) to enable Repository Rulesets, then have the Bootstrap Agent re-run the block above.

**Phase 4 Verification:** `gh api "/repos/${REPO_FULL}/rulesets" --jq '.[].name'` lists all 3 active rulesets (with Ruleset #1 requiring both `ci-and-evidence` and `human-gate-guard`), `.github/CODEOWNERS` contains the real GitHub username, and `gh label list` shows the 6 active labels (`plan`, `ready`, `in-progress`, `human-gate`, `blocked`, `rescue-escalated`).

---

## Phase 5: GitHub Projects v2 Kanban Board (7 Columns), Native Sub-Issues & Rolling Release PR Helpers

### 5.1 Create, Link & Configure 7-Column Kanban Board via CLI
Includes the dedicated **`Awaiting Approval`** column right after `In Review` so every item requiring your manual click—auto-gated protected-path PRs (`migrations/`, `auth/`, `.factory/`, etc.), manual `human-gate` PRs, and the rolling `staging -> master` Release PR—surfaces cleanly in one place.

Run from the host using the bootstrap `gh` login (set `PROJECT_OWNER` to the org name if using an org repo; keep `@me` for a personal repo):

```bash
PROJECT_OWNER="@me"
REPO_FULL=$(gh repo view --json nameWithOwner -q .nameWithOwner)
REPO_NAME=$(basename "$REPO_FULL")

PROJECT_JSON=$(gh project create --owner "$PROJECT_OWNER" --title "${REPO_NAME} — Light Factory" --format json)
PROJECT_NUMBER=$(echo "$PROJECT_JSON" | jq -r '.number')
echo "Created Project #${PROJECT_NUMBER}"

gh project link "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --repo "$REPO_FULL"

STATUS_FIELD_ID=$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json \
  | jq -r '.fields[] | select(.name == "Status") | .id')

gh api graphql -f fieldId="$STATUS_FIELD_ID" -f query='
mutation($fieldId: ID!) {
  updateProjectV2Field(input: {
    fieldId: $fieldId
    singleSelectOptions: [
      { name: "Backlog",           color: GRAY,   description: "Draft ideas, rough features (plan), and queued future-wave Sub-Issues" }
      { name: "Ready",             color: GREEN,  description: "Approved Epic or atomic Sub-Issue ready for Architect dispatch" }
      { name: "In Progress",       color: YELLOW, description: "Claimed by Architect; worker building or writing E2E in sandbox" }
      { name: "In Review",         color: BLUE,   description: "Routine PR open with CI evidence; Architect reviewing & auto-merging to staging" }
      { name: "Awaiting Approval", color: ORANGE, description: "Human-gated PR (protected path / human-gate / rolling staging->master Release PR) awaiting YOUR Approve & Merge" }
      { name: "Blocked",           color: RED,    description: "CI retry cap hit, broken staging, or needs human decision" }
      { name: "Done",              color: PURPLE, description: "Merged or closed" }
    ]
  }) {
    projectV2Field { ... on ProjectV2SingleSelectField { id name } }
  }
}'

gh project field-create "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" \
  --name "Priority" --data-type "SINGLE_SELECT" \
  --single-select-options "P0 - Critical,P1 - High,P2 - Normal"

gh project field-create "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" \
  --name "Worker" --data-type "SINGLE_SELECT" \
  --single-select-options "Architect,Orchestrator,AGY,Qwen,GLM"

gh issue list --state open --limit 100 --json url -q '.[].url' | while read -r url; do
  gh project item-add "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --url "$url" >/dev/null || true
done

echo "Save for Phase 8: PROJECT_NUMBER=${PROJECT_NUMBER} PROJECT_OWNER=${PROJECT_OWNER}"
```

### 5.2 Create Non-Fatal Board Sync Helper for Issues & PRs (`.factory/board-sync.sh`)
Create `.factory/board-sync.sh` (`chmod +x .factory/board-sync.sh`).
Supports both Issue numbers (`42`) and Pull Request targets (`pr:42`) so both linked feature Issues and the rolling `staging -> master` Release PR itself appear cleanly in **`Awaiting Approval`**.

```bash
#!/usr/bin/env bash
# Usage:
#   .factory/board-sync.sh <issue_number> <field_name> <value>
#   .factory/board-sync.sh pr:<pr_number> <field_name> <value>
set -uo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <issue_number|pr:pr_number> <field_name> <value>" >&2
  exit 0
fi

if [ "${FACTORY_ROLE:-}" = "worker" ]; then
  echo "[board-sync] Skipping: worker role does not modify project board." >&2
  exit 0
fi

ENV_FILE="${BRIDGE_ENV_FILE:-/run/factory-config/bridge.env}"
[ ! -r "$ENV_FILE" ] && ENV_FILE=".factory/.env"
[ -r "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }
[ -z "${PROJECT_NUMBER:-}" ] && exit 0

OWNER="${PROJECT_OWNER:-@me}"
TARGET_REF="$1"
FIELD_NAME="$2"
FIELD_VALUE="$3"
AUTH_ROOT="${FACTORY_AUTH_ROOT:-/run/factory-auth}"

SYNC_TOKEN=""
if [ "$OWNER" = "@me" ] && [ -r "${AUTH_ROOT}/architect/project-token" ]; then
  SYNC_TOKEN="$(cat "${AUTH_ROOT}/architect/project-token")"
fi
if [ -z "$SYNC_TOKEN" ] && [ -r "${AUTH_ROOT}/architect/token" ]; then
  SYNC_TOKEN="$(cat "${AUTH_ROOT}/architect/token")"
fi

if [ -z "$SYNC_TOKEN" ]; then
  echo "[board-sync] WARNING: No token available for board sync; skipping safely." >&2
  exit 0
fi

export GH_CONFIG_DIR="/tmp/factory-gh-config-architect"
mkdir -p "$GH_CONFIG_DIR"

REPO_URL="$(GH_TOKEN="$SYNC_TOKEN" gh repo view --json url -q .url 2>/dev/null || true)"
[ -z "$REPO_URL" ] && exit 0

if [[ "$TARGET_REF" == pr:* ]]; then
  ITEM_LABEL="PR #${TARGET_REF#pr:}"
  ITEM_URL="${REPO_URL}/pull/${TARGET_REF#pr:}"
elif [[ "$TARGET_REF" == https://* ]]; then
  ITEM_LABEL="$TARGET_REF"
  ITEM_URL="$TARGET_REF"
else
  ITEM_LABEL="Issue #${TARGET_REF}"
  ITEM_URL="${REPO_URL}/issues/${TARGET_REF}"
fi

GH_TOKEN="$SYNC_TOKEN" gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$ITEM_URL" >/dev/null 2>&1 || true

if GH_TOKEN="$SYNC_TOKEN" gh project item-edit "$PROJECT_NUMBER" --owner "$OWNER" --url "$ITEM_URL" --field "$FIELD_NAME" --value "$FIELD_VALUE" >/dev/null 2>&1; then
  echo "[board-sync] ${ITEM_LABEL} -> ${FIELD_NAME}: ${FIELD_VALUE}"
else
  echo "[board-sync] WARNING: Could not sync ${ITEM_LABEL} (${FIELD_NAME}=${FIELD_VALUE}); continuing safely." >&2
fi
exit 0
```

### 5.3 Create Native GitHub Sub-Issues Helper (`.factory/sub-issue.sh`)
Create `.factory/sub-issue.sh` (`chmod +x .factory/sub-issue.sh`).
Uses GitHub's GA Sub-Issues REST API (universal across `gh` CLI versions) so `factory-architect[bot]` can link child Sub-Issues to parent Epics, list sub-issue waves, check parent progress, and detect when an Epic is ready to close (with zero extra `epic` label required).

```bash
#!/usr/bin/env bash
# Usage:
#   .factory/sub-issue.sh link    <parent_issue_num> <child_issue_num>
#   .factory/sub-issue.sh list    <parent_issue_num>
#   .factory/sub-issue.sh parent  <child_issue_num>
#   .factory/sub-issue.sh summary <parent_issue_num>
set -euo pipefail

CMD="${1:-}"
REPO="${FACTORY_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

case "$CMD" in
  link)
    if [ "${FACTORY_ROLE:-}" = "worker" ]; then
      echo "[sub-issue] ERROR: Only Architect may link Sub-Issues." >&2
      exit 1
    fi
    PARENT_NUM="${2:?parent_issue_num required}"
    CHILD_NUM="${3:?child_issue_num required}"
    CHILD_ID="$(gh api "repos/${REPO}/issues/${CHILD_NUM}" --jq '.id')"
    gh api --method POST "repos/${REPO}/issues/${PARENT_NUM}/sub_issues" \
      -F sub_issue_id="${CHILD_ID}" >/dev/null
    echo "[sub-issue] Linked Sub-Issue #${CHILD_NUM} -> Parent Epic #${PARENT_NUM}"
    ;;

  list)
    PARENT_NUM="${2:?parent_issue_num required}"
    gh api --paginate "repos/${REPO}/issues/${PARENT_NUM}/sub_issues" \
      --jq '.[] | {number, state, title, labels: [.labels[].name]}'
    ;;

  parent)
    CHILD_NUM="${2:?child_issue_num required}"
    gh api "repos/${REPO}/issues/${CHILD_NUM}/parent" \
      --jq '{number, state, title, labels: [.labels[].name]}' 2>/dev/null || echo "null"
    ;;

  summary)
    PARENT_NUM="${2:?parent_issue_num required}"
    gh api "repos/${REPO}/issues/${PARENT_NUM}" \
      --jq '.sub_issues_summary // {total: 0, completed: 0, percent_completed: 0}'
    ;;

  *)
    echo "Usage: $0 <link|list|parent|summary> <issue_num> [child_num]" >&2
    exit 1
    ;;
esac
```

### 5.4 Create Rolling `staging -> master` Release PR Helper (`.factory/release-pr.sh`)
Create `.factory/release-pr.sh` (`chmod +x .factory/release-pr.sh`).
Called by the Architect whenever a parent Epic closes on `staging`. Ensures there is **never more than one open `staging -> master` Release PR**, auto-populates its changelog from `master...staging`, adds the purple `human-gate` badge, formally requests **you** as Reviewer, adds the Release PR card directly to the Kanban **`Awaiting Approval`** column, and reminds you to merge via **"Create a merge commit" (never Squash)** so `staging` and `master` stay cleanly aligned across releases.

```bash
#!/usr/bin/env bash
# Usage: .factory/release-pr.sh [completed_epic_num]
# Opens or updates the single rolling `staging -> master` Release PR, requests human review,
# and places the PR card directly in the Kanban `Awaiting Approval` column.
set -euo pipefail

if [ "${FACTORY_ROLE:-}" = "worker" ]; then
  echo "[release-pr] ERROR: Only Architect may open or update Release PRs." >&2
  exit 1
fi

ENV_FILE="${BRIDGE_ENV_FILE:-/run/factory-config/bridge.env}"
[ ! -r "$ENV_FILE" ] && ENV_FILE=".factory/.env"
[ -r "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

EPIC_NUM="${1:-}"
REPO="${FACTORY_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
BASE_BRANCH="${RELEASE_BASE_BRANCH:-master}"
HEAD_BRANCH="staging"

# Resolve human reviewer from bridge.env or .github/CODEOWNERS
REVIEWER="${HUMAN_REVIEWER:-}"
if [ -z "$REVIEWER" ] && [ -r /workspace/.github/CODEOWNERS ]; then
  REVIEWER="$(grep -Eo '@[A-Za-z0-9-]+' /workspace/.github/CODEOWNERS | head -n1 | tr -d '@' || true)"
fi

COMPARE_JSON="$(gh api "repos/${REPO}/compare/${BASE_BRANCH}...${HEAD_BRANCH}")"
AHEAD_BY="$(echo "$COMPARE_JSON" | jq -r '.ahead_by // 0')"

if [ "$AHEAD_BY" -eq 0 ]; then
  echo "[release-pr] ${HEAD_BRANCH} has 0 commits ahead of ${BASE_BRANCH}; skipping Release PR."
  exit 0
fi

CHANGELOG="$(echo "$COMPARE_JSON" | jq -r '.commits[] | "- `\(.sha[0:7])` \(.commit.message | split("\n")[0])"')"
EPIC_LINE=""
if [ -n "$EPIC_NUM" ]; then
  EPIC_TITLE="$(gh issue view "$EPIC_NUM" --json title -q .title 2>/dev/null || true)"
  EPIC_LINE="- **Latest Completed Epic:** #${EPIC_NUM}${EPIC_TITLE:+ — ${EPIC_TITLE}}"
fi

BODY="$(cat <<EOF
**[Architect]** Rolling production release PR promoting verified changes from \`${HEAD_BRANCH}\` into \`${BASE_BRANCH}\`.

> 🔒 **Human-Only Production Gate:** This PR is physically locked by \`CODEOWNERS\`, Ruleset #2, and \`human-gate-guard\`.
> ⚠️ **IMPORTANT MERGE METHOD:** After clicking **Approve**, merge using **"Create a merge commit"** — **NEVER "Squash and merge"** — so \`${HEAD_BRANCH}\` and \`${BASE_BRANCH}\` share history and never suffer recurring merge conflicts on future releases.

## Release Summary
- **Commits ahead of \`${BASE_BRANCH}\`:** ${AHEAD_BY}
${EPIC_LINE}

## Changes Included in This Release
${CHANGELOG}
EOF
)"

EXISTING_PR="$(gh pr list --base "$BASE_BRANCH" --head "$HEAD_BRANCH" --state open --json number -q '.[0].number // empty')"
PR_NUM=""

if [ -n "$EXISTING_PR" ]; then
  gh pr edit "$EXISTING_PR" --body "$BODY" >/dev/null
  PR_NUM="$EXISTING_PR"
  echo "[release-pr] Updated rolling Release PR #${PR_NUM} (${HEAD_BRANCH} -> ${BASE_BRANCH}, ${AHEAD_BY} commits)."
else
  PR_URL="$(gh pr create \
    --base "$BASE_BRANCH" \
    --head "$HEAD_BRANCH" \
    --title "chore(release): promote ${HEAD_BRANCH} to ${BASE_BRANCH}" \
    --body "$BODY")"
  PR_NUM="${PR_URL##*/}"
  echo "[release-pr] Opened rolling Release PR #${PR_NUM}: ${PR_URL}"
fi

# Badge purple `human-gate`, formally request human review, & surface directly in `Awaiting Approval`
if [ -n "$PR_NUM" ]; then
  gh pr edit "$PR_NUM" --add-label "human-gate" >/dev/null 2>&1 || true
  if [ -n "$REVIEWER" ]; then
    gh pr edit "$PR_NUM" --add-reviewer "$REVIEWER" >/dev/null 2>&1 || true
  fi
  if [ -x /workspace/.factory/board-sync.sh ]; then
    /workspace/.factory/board-sync.sh "pr:${PR_NUM}" Status "Awaiting Approval" || true
    /workspace/.factory/board-sync.sh "pr:${PR_NUM}" Worker "Architect" || true
  fi
fi
```

### 5.5 Enable Built-In Project Board Workflows & Sub-Issue Progress Layout
> **[HUMAN ACTION REQUIRED]** *(One-time 60-second UI setup)*
> Open the board via `gh project view <PROJECT_NUMBER> --owner "@me" --web` and configure:
> 1. **View 1 -> Board Layout:** Dropdown -> **Layout: Board** -> **Column by: `Status`** -> **Sort by: `Priority` (ascending)** -> **Fields**: toggle ON **`Labels`**, **`Priority`**, **`Worker`**, **`Linked pull requests`**, **`Parent issue`**, and **`Sub-issues progress`** -> **Save changes**.
> 2. **Turn ON 3 Built-In Workflows** (**`...`** top-right -> **Workflows**):
>    - **Auto-add to project** -> Edit -> select this repo -> filter: **`is:issue`** -> **Save and turn on workflow**. *(New Sub-Issues inherit the parent's Project automatically; rolling `staging -> master` Release PRs are added directly to `Awaiting Approval` by `.factory/release-pr.sh`.)*
>    - **Item added to project** -> Edit -> Set `Status` to **`Backlog`** -> **Save and turn on workflow**.
>    - **Item closed** -> Edit -> Set `Status` to **`Done`** -> **Save and turn on workflow**. *(Also auto-moves merged Release PRs from `Awaiting Approval` -> `Done`!)*

**Phase 5 Verification:** `gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER"` lists `Status` (**7 columns**, including `Awaiting Approval`), `Priority`, and `Worker` (`Architect`, `Orchestrator`, `AGY`, `Qwen`, `GLM`), and `.factory/{board-sync,sub-issue,release-pr}.sh` are executable.

---

## Phase 6: Governance, Closed-Loop Memory & Progressive-Disclosure Skills

### 6.1 Create `AGENTS.md` in Repo Root
Keep `AGENTS.md` concise (<200 lines) so it fits cleanly inside context budgets and establishes the factory rules of engagement.

> 📂 **Live Implementation:** [`AGENTS.md`](file:///home/admin/Github/light-software-factory/AGENTS.md)

### 6.2 Create `DECISIONS.md` in Repo Root
Architectural decision record log documenting container topology, queue serialization, and human gating decisions.

> 📂 **Live Implementation:** [`DECISIONS.md`](file:///home/admin/Github/light-software-factory/DECISIONS.md)

### 6.3 Create Starter Progressive-Disclosure Skills
Progressive-disclosure skills allow agents to load domain playbooks on-demand without cluttering their initial prompt context.

> 📂 **Live Implementations:**
> - [`.agents/skills/modern-web-standards/SKILL.md`](file:///home/admin/Github/light-software-factory/.agents/skills/modern-web-standards/SKILL.md) *(Modern UI/API patterns)*
> - [`.agents/skills/postgres-migrations/SKILL.md`](file:///home/admin/Github/light-software-factory/.agents/skills/postgres-migrations/SKILL.md) *(Safe PostgreSQL migration playbook)*
> - [`.agents/skills/e2e-testing/SKILL.md`](file:///home/admin/Github/light-software-factory/.agents/skills/e2e-testing/SKILL.md) *(Zero-mock Playwright verification playbook)*
> - [`.factory/role-skills/architect/pr-evidence-review/SKILL.md`](file:///home/admin/Github/light-software-factory/.factory/role-skills/architect/pr-evidence-review/SKILL.md) *(Architect vision evidence evaluation)*
> - [`.agents/skills/conflict-and-rescue/SKILL.md`](file:///home/admin/Github/light-software-factory/.agents/skills/conflict-and-rescue/SKILL.md) *(Senior/Specialist 1-pass merge conflict & 3-strike rescue playbook)*

## Phase 7: CI Evidence Pipeline (PR + Post-Merge `staging`) & Trusted `human-gate-guard`

### 7.1 Create `.github/workflows/ci-evidence.yml`
Runs on **both** `pull_request` (to `staging`/`master`) **and** `push` (to `staging`) against a fresh, empty **Postgres 16** service container—catching cross-PR logical regressions immediately after two parallel Wave PRs merge into `staging`. PR-only artifact uploads and PR summary comments are safely gated to `github.event_name == 'pull_request'`.
*(Bootstrap Agent Note: Inspect the repository's existing stack and adapt `npm ci` / `db:migrate` / `lint` / `build` / Playwright commands to match the actual package manager and ORM.)*

> 📂 **Live Implementation:** [`.github/workflows/ci-evidence.yml`](file:///home/admin/Github/light-software-factory/.github/workflows/ci-evidence.yml)


### 7.2 Create Tamper-Proof `.github/workflows/human-gate-guard.yml`
Uses **`pull_request_target` + `pull_request_review`** (always executes the trusted copy from `master`, **never** checks out PR code, uses no secrets) and publishes an explicit Commit Status (`context: "human-gate-guard"`) directly onto **`pr.head.sha`**. This closes **both** edge cases:
1. A PR branch cannot bypass the guard by editing `.github/workflows/human-gate-guard.yml`.
2. When you click **Approve**, `pull_request_review` posts `state: "success"` directly onto `pr.head.sha`, immediately unlocking Ruleset #1 so **you** can click **Merge** right away (never auto-merged by bots).

Bootstrap Agent: substitute `<YOUR_GITHUB_USERNAME>` automatically via `gh api user -q .login`:

> 📂 **Live Implementation:** [`.github/workflows/human-gate-guard.yml`](file:///home/admin/Github/light-software-factory/.github/workflows/human-gate-guard.yml)


**Phase 7 Verification:** Both `.github/workflows/ci-evidence.yml` (with `push: branches: [staging]` + PR guards) and `.github/workflows/human-gate-guard.yml` parse cleanly with no YAML syntax errors, `HUMAN_APPROVERS` is set to the real human GitHub username, and `human-gate-guard.yml` contains zero `actions/checkout` steps.

---

## Phase 8: Sandboxed Webhook -> Priority Herdr Wait-Queue Bridge, Native Herdr Launcher, Preflight & Easy Config

### 8.1 Create `.factory/webhook-bridge.mjs`
Implements the **Upgraded Priority Herdr Wait-Queue + `Awaiting Approval` Board Sync + Post-Merge `staging` CI Guard + Stall Watchdog**:
- **Strict 1-Turn-at-a-Time Serialization:** Waits for `herdr agent wait architect --until idle --until done` before every dispatch, then waits for the Architect turn to complete.
- **Disk-Persisted Priority Queue (`hub-herdr` volume):** Persists pending items atomically to `${BRIDGE_STATE_DIR}/architect-queue.json`. Priority order: `HUMAN_COMMENT (10)` > `CI_URGENT / STAGING_BROKEN (20)` > `REVIEW_WAVE (30)` > `PLAN_READY (40)`.
- **8-Second Same-Thread Comment Coalescer:** Bundles rapid human comments on the **same** Issue/PR thread into one prompt while keeping different threads strictly separate.
- **Single-Pane `Awaiting Approval` Surfacing:** Whenever `human-gate-guard` locks a PR (including auto-gated protected paths like `migrations/`/`auth/`), automatically adds the purple `human-gate` badge to the PR & linked Issue, formally requests `HUMAN_REVIEWER` on the PR, and moves the card into **`Awaiting Approval`** (leaving both **Approve** and **Merge** strictly manual by you).
- **Post-Merge `staging` Regression Guard:** Immediately alerts the Architect at `CI_URGENT` priority if `CI & PR Evidence` fails on a `push` to `staging`.
- **Silent Worker Stall Watchdog:** Every 15 minutes, checks open `in-progress` Sub-Issues for >45 minutes of inactivity without active PR pushes and prompts the Architect to inspect `herdr agent list` / `herdr agent read <worker>`.

> 📂 **Live Implementation:** [`\.factory/webhook-bridge\.mjs`](file:///home/admin/Github/light-software-factory/.factory/webhook-bridge.mjs)

The webhook bridge runs inside `herdr-hub` listening on port 8787:
- **Outside Contributor Check:** Rejects webhook actions from non-members.
- **Bot De-duplication:** Checks `sender.type === 'Bot'` to prevent infinite quote-reply loops.
- **8-Second Coalescer:** Groups rapid-fire human comments into a single coherent prompt turn.
- **PR Review & Wave Triggers:** Automatically detects when all Wave sub-issues complete and triggers `release-pr.sh` deterministically.


### 8.2 Create 1-Command Native Herdr Launcher & Seed Prompt (`.factory/architect-seed.md` & `.factory/launch-panes.sh`)
Store the Architect seed prompt in Git and launch all 5 native Herdr tabs cleanly inside the running `herdr server` using verified Herdr v0.9.5 commands (`workspace create`, `tab create`, `pane run`, `agent start`, `agent rename`, and per-command `HERDR_AGENT=` hints—never nested inside `tmux`). Re-running `.factory/launch-panes.sh` after detaching simply reattaches to the live Herdr UI without duplicating tabs.

**File 1: `.factory/architect-seed.md`**
> 📂 **Live Implementations:**
> - [`\.factory/architect-seed\.md`](file:///home/admin/Github/light-software-factory/.factory/architect-seed.md) *(Architect boot system prompt)*
> - [`\.factory/launch-panes\.sh`](file:///home/admin/Github/light-software-factory/.factory/launch-panes.sh) *(Launches 6 native Herdr tabs and seeds the Architect)*


### 8.3 Create `bridge.env` & Single-File Model/Inference/Postgres Control (`compose.env`)
Run on the host. **`compose.env` is your single control panel** for models, vision models, local GPU inference URLs, and Postgres passwords:

```bash
REPO_FULL=$(gh repo view --json nameWithOwner -q .nameWithOwner)
GH_OWNER_LOGIN=$(gh api user -q .login)
SECRET=$(openssl rand -hex 32)
ARCH_PROXY_TOK="proxy-arch-$(openssl rand -hex 12)"
GLM_WORKER_PROXY_TOK="proxy-worker-glm-$(openssl rand -hex 12)"

PG_ADMIN_PW=$(openssl rand -hex 16)
PG_AGY_PW=$(openssl rand -hex 16)
PG_QWEN_PW=$(openssl rand -hex 16)
PG_GLM_PW=$(openssl rand -hex 16)

PROJECT_OWNER="${PROJECT_OWNER:-@me}"
PROJECT_NUMBER="${PROJECT_NUMBER:-$(gh project list --owner "$PROJECT_OWNER" --format json -q '.projects[] | select(.title | contains("Light Factory")) | .number' 2>/dev/null | head -n1 || true)}"

cat <<EOF > ~/.config/light-factory/bridge.env
WEBHOOK_PORT=8787
GITHUB_WEBHOOK_SECRET=${SECRET}
HUMAN_REVIEWER=${GH_OWNER_LOGIN}
ARCHITECT_PANE=architect
ORCHESTRATOR_PANE=orchestrator
AGY_RESCUE_MODEL=claude-opus-5-5-high
MAX_CI_RETRIES=3
CI_WORKFLOW_NAME=CI & PR Evidence
BRIDGE_STATE_DIR=/home/factory/.config/herdr/bridge-state
COMMENT_COALESCE_MS=8000
ARCHITECT_WAIT_TIMEOUT_MS=300000
STALL_WATCHDOG_INTERVAL_MS=900000
STALL_THRESHOLD_MS=2700000
PROJECT_NUMBER=${PROJECT_NUMBER}
PROJECT_OWNER=${PROJECT_OWNER}
EOF
chmod 600 ~/.config/light-factory/bridge.env

cat <<EOF > ~/.config/light-factory/compose.env
# === Core Stack ===
FACTORY_REPO=${REPO_FULL}
FACTORY_UID=$(id -u)
FACTORY_GID=$(id -g)
WEBHOOK_PORT=8787

# === Isolated Worker Postgres (3 locked-down DBs; herdr-hub has NO access) ===
POSTGRES_IMAGE=postgres:16-alpine
POSTGRES_ADMIN_PASSWORD=${PG_ADMIN_PW}
POSTGRES_AGY_PASSWORD=${PG_AGY_PW}
POSTGRES_QWEN_PASSWORD=${PG_QWEN_PW}
POSTGRES_GLM_PASSWORD=${PG_GLM_PW}

# === Hub Control Plane (GLM-5.3 Architect + GLM-5.3 Orchestrator via llm-proxy) ===
ARCHITECT_MODEL=glm-5.3
ARCHITECT_VISION_MODEL=glm-5.3-flash
ORCHESTRATOR_MODEL=glm-5.3
EXTRA_ALLOWED_MODELS=
ARCHITECT_PROXY_TOKEN=${ARCH_PROXY_TOK}

# === Worker AGY (Antigravity Ultra 5x — dynamic --model per ticket) ===
AGY_DEFAULT_MODEL=gemini-4-hydrogen-high

# === Worker Qwen (Hermes -> Local GPU Inference Server) ===
QWEN_INFERENCE_URL=http://host.docker.internal:11434/v1
QWEN_MODEL=qwen3.8:27b
QWEN_API_KEY=local-not-needed

# === Worker GLM (Cheap GLM-5.3 API Backup via isolated /worker-glm proxy route) ===
GLM_WORKER_MODEL=glm-5.3
GLM_WORKER_PROXY_TOKEN=${GLM_WORKER_PROXY_TOK}
EOF
chmod 600 ~/.config/light-factory/compose.env

echo "Generated bridge.env (HUMAN_REVIEWER=${GH_OWNER_LOGIN}) & compose.env — copy GITHUB_WEBHOOK_SECRET from ~/.config/light-factory/bridge.env for Phase 9."
```

> **Quick-Swap Cheat Sheet (Anytime Later):**
> - **Change Architect model or Vision model:** Edit `ARCHITECT_MODEL` / `ARCHITECT_VISION_MODEL` in `~/.config/light-factory/compose.env` (and `GLM_UPSTREAM_URL` / `VISION_UPSTREAM_URL` / keys in `llm-secrets.env` if changing providers) -> run `./.factory/preflight.sh && docker compose --env-file ~/.config/light-factory/compose.env up -d --force-recreate llm-proxy herdr-hub` -> recover all 6 tabs in 1 command via `docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh`.
> - **Change Local Qwen server or model:** Edit `QWEN_INFERENCE_URL` / `QWEN_MODEL` in `~/.config/light-factory/compose.env` -> run `docker compose --env-file ~/.config/light-factory/compose.env up -d --force-recreate worker-qwen`.
> - **Add a new domain skill (e.g., Chrome official web skill, framework guide):** Drop `<skill-name>/SKILL.md` into `.agents/skills/` and push to `staging`; every container picks it up automatically via `.factory/sync-skills.sh`.

### 8.4 Create Host Preflight Script (`.factory/preflight.sh`)
Create `.factory/preflight.sh` (`chmod +x .factory/preflight.sh`).
Prevents the classic Docker bind-mount trap where starting Compose before a host secret file exists silently creates an empty **directory** at that path—and validates `docker compose config` before launching containers.

> 📂 **Live Implementation:** [`\.factory/preflight\.sh`](file:///home/admin/Github/light-software-factory/.factory/preflight.sh)

### 8.5 Commit, Push to `staging` & Sync Bootstrap Workflows to Default Branch (`master`)
```bash
git add .factory .agents .github AGENTS.md DECISIONS.md docker-compose.yml .gitignore
git commit -m "chore: bootstrap herdr-software-factory sandbox, Awaiting Approval board, post-merge staging CI, proxy /stats, preflight & native HERDR_AGENT launcher"
git push origin staging
```

> **[HUMAN ACTION REQUIRED — Mandatory for Trusted `pull_request_target` & `pull_request_review`]**
> GitHub runs `pull_request_target` and `pull_request_review` workflows strictly from your repository's **default branch (`master`)**.
> The Bootstrap Agent may open the initial PR, and the human owner merges it via **"Create a merge commit"** in the GitHub UI (human-authored PR passes `human-gate-guard` automatically):

```bash
gh pr create --base master --head staging --title "chore: bootstrap herdr-software-factory" --body "Initial factory workflows, CODEOWNERS, and trusted human-gate-guard."
```

**Phase 8 Verification:** All bootstrap files (including `.github/workflows/human-gate-guard.yml`, `.factory/{sub-issue,release-pr,sync-hub,fetch-evidence,launch-panes,preflight}.sh`, `.factory/architect-seed.md`, `.agents/skills/`, and `.factory/postgres/`) are merged into `master` (via merge commit) and present on `origin/staging`, and `./.factory/preflight.sh` exits `0`.

---

## Phase 9: Expose Host Tunnel & Register GitHub Webhook

Run the tunnel on the **host machine**, forwarding public HTTPS traffic to `http://127.0.0.1:8787/webhook` (which Docker routes strictly into `herdr-hub`):

| Method | Best For | Command (Run on Host) |
| :--- | :--- | :--- |
| **Tailscale Funnel** *(Recommended)* | Always-on, zero third-party proxy, stable HTTPS URL | `tailscale funnel --bg 8787` |
| **Cloudflare Tunnel** | Free persistent HTTPS URL | `cloudflared tunnel --url http://127.0.0.1:8787` |
| **Smee.io** *(Fastest Test)* | Instant dev webhook relay (no firewall/DNS setup) | `npx smee-client -u https://smee.io/<your-channel> -t http://127.0.0.1:8787/webhook` |

> **[HUMAN ACTION REQUIRED]**
> 1. Start your chosen host tunnel and copy the public HTTPS URL (ending in `/webhook` for Tailscale/Cloudflare, or the Smee channel URL).
> 2. Open GitHub -> **Repo Settings -> Webhooks -> Add webhook**:
>    - **Payload URL:** `<your-public-https-url>`
>    - **Content type:** `application/json`
>    - **Secret:** Paste `GITHUB_WEBHOOK_SECRET` from `~/.config/light-factory/bridge.env`
>    - **Which events?** Select **"Let me select individual events"** and check ONLY these **5 events**:
>      - `Issues` *(handles `plan` decomposition & `ready` dispatch)*
>      - `Issue comments` *(routes human feedback & plan approvals)*
>      - `Pull requests` *(auto-advances Epic waves, syncs hub, triggers Final-Wave E2E & rolling `staging -> master` Release PR on Epic completion)*
>      - `Pull request review comments` *(routes inline code-review feedback)*
>      - `Workflow runs` *(handles PR `CI & PR Evidence`, post-merge `staging` regression alerts, `Awaiting Approval` surfacing, 3-strike rescue escalation & spend circuit breaker)*
>    - Click **Add webhook**.

---

## Phase 10: Build, Boot & Launch `herdr-software-factory`

### 10.1 Run Preflight, Build & Start the Unified 7-Container Stack
Before building, confirm with the human that any custom `hermes` and `agy` CLI install lines have been added to `.factory/docker/Dockerfile.hub` and `.factory/docker/Dockerfile.worker`, then run from `<repo-root>` on the host:

```bash
./.factory/preflight.sh
docker compose --env-file ~/.config/light-factory/compose.env up -d --build
docker compose --env-file ~/.config/light-factory/compose.env ps
```
You will see one unified project **`herdr-software-factory`** with **7 healthy running containers** (`auth-minter`, `llm-proxy`, `factory-postgres`, `herdr-hub`, `worker-agy`, `worker-qwen`, `worker-glm`).
- **`herdr-hub`** boots directly into headless `herdr server`, auto-configuring Hermes (`architect` + `orchestrator` profiles with Vision), `herdr --skill`, and skills—while **`worker-qwen`**, **`worker-glm`**, **`factory-postgres`**, and **Playwright Chromium** auto-configure on boot!

### 10.2 One-Time OAuth Login (Only 1 Container!)
> **[HUMAN ACTION REQUIRED]**
> Complete a single one-time interactive OAuth login strictly inside `worker-agy` (credentials persist inside its private Docker volumes `agy-auth` / `agy-dotgemini` and never touch your host `$HOME`):
>
1. **Antigravity Multi-Model Worker (`worker-agy` -> `agy-auth` / `agy-dotgemini` — Google AI Ultra 5x):**
```bash
docker compose exec -it -e SSH_CONNECTION=1 worker-agy agy
# Copy the printed OAuth URL into your browser, paste back the code (keep "Use AI Credits" OFF), then /exit
```

### 10.3 Launch the Native 6-Tab Herdr Workspace (1-Command Recovery & Handoff)

> **[HUMAN ACTION REQUIRED — Factory Handoff]**
> Run the 1-command launcher on your GPU host (or over SSH from your laptop/phone):

```bash
docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh
```
>
> This automatically creates the native Herdr `factory` workspace with **6 tabs** (`bridge`, `architect`, `orchestrator`, `worker-agy`, `worker-qwen`, `worker-glm`), attaches per-command `HERDR_AGENT=` hints to all 3 SSH workers, persists `worker-agy`'s `pane_id` for dynamic `--model` swaps, seeds `architect` & `orchestrator`, and opens the live Herdr UI.
>
> * **Detach anytime without stopping agents:** Press `ctrl+b q` (all 6 tabs and `herdr server` keep running in the background inside `herdr-hub`).
> * **Reattach anytime later:** Re-run `docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh` (detects the live `factory` workspace and attaches immediately without duplicating tabs).
> * **If a remote worker tab didn't finish booting before `herdr agent rename`:** Wait for its prompt to appear, then run `herdr agent rename <pane_id> <worker_name>` once inside `herdr-hub`. If a pane shows the wrong state, inspect it with `herdr agent explain <agent_name>`.

### 10.4 Quick Health, Isolation & Telemetry Check

Run from the host to confirm all 7 containers, `llm-proxy` telemetry, and `webhook-bridge` priority queue telemetry are live:

```bash
# 1. Verify webhook-bridge health, recovered queue depth & configured human reviewer
curl -s http://127.0.0.1:8787/health | jq .

# 2. Verify llm-proxy health & /stats token/request telemetry (from inside herdr-hub on llm-net)
docker compose exec herdr-hub curl -s http://llm-proxy:4000/health | jq .
docker compose exec herdr-hub curl -s http://llm-proxy:4000/stats | jq .

# 3. Verify all 5 agents appear natively in Herdr with live states (idle/working/blocked/done)
docker compose exec herdr-hub herdr agent list
```

---

## Phase 11: End-to-End Verification & Smoke Tests

Run these 8 verification checks before handing the factory real production Epics.

### Test 0 — Preflight, Zero-Trust Isolation, Postgres Isolation & Skills Check
1. **Host Preflight:** Run `./.factory/preflight.sh` on the host — must exit `0` with all 8 secret/config files green.
2. **Zero Raw Secrets & Zero `docker.sock`:**
   ```bash
   docker compose exec herdr-hub bash -lc 'test ! -e /var/run/docker.sock && test ! -e /run/factory-keys && ! env | grep -qiE "GLM_API_KEY"'
   docker compose exec worker-agy bash -lc 'test ! -e /run/factory-auth/architect && ! curl -s --max-time 2 http://llm-proxy:4000/health'
   ```
   *(Both commands must exit `0`: `herdr-hub` has no `docker.sock` or real API keys; `worker-agy` cannot read Architect tokens or reach `llm-proxy`.)*
3. **Database & Execution-Free Hub Isolation:**
   ```bash
   # herdr-hub must NOT be able to reach factory-postgres (no db-net route)
   docker compose exec herdr-hub bash -lc '! getent hosts factory-postgres'
   # worker-agy CAN connect to app_agy and reset public schema, but CANNOT connect to app_qwen
   docker compose exec worker-agy bash -lc 'psql "$DATABASE_URL" -c "SELECT current_database(), current_user;" && ! psql "${DATABASE_URL%app_agy}app_qwen" -c "SELECT 1;"'
   ```
4. **Skills Synced Properly:** Confirm `herdr-hub` has `.agents/skills/*`, `grill-with-docs`, `to-tickets`, `pr-evidence-review`, AND `herdr/SKILL.md`; confirm `worker-agy` has `.agents/skills/*` including `conflict-and-rescue`.

### Test 1 — Native Herdr Visibility Over Internal SSH (`HERDR_AGENT=`)
1. Inside `herdr-hub`, run `herdr agent list`.
2. Confirm all 5 agents (`architect`, `orchestrator`, `worker-agy`, `worker-qwen`, `worker-glm`) appear with real-time states (`idle` / `done` / `working` / `blocked`).

### Test 2 — Plan-First Epic Decomposition (`plan` -> Sub-Issues + Test Plans -> Pause)
1. Open a multi-part test Feature Request Issue on GitHub and apply the **`plan`** label.
2. Verify `webhook-bridge` syncs `/workspace` via `.factory/sync-hub.sh`, enqueues `plan_request`, and wakes `architect`.
3. Verify the Architect posts a concrete Strawman Blueprint with Wave 0 + Wave 1+ Test Plans and **STOPS** without dispatching any worker.

### Test 3 — Wave 0 Carbon Acceptance -> Routine Build Wave -> Auto-Merge to `staging`
1. Apply **`ready`** to the approved Epic.
2. Verify the Orchestrator dispatches **Wave 0** to `worker-agy --model gemini-4-carbon-high` to author the failing (RED) black-box E2E test & fixtures.
3. Verify the Orchestrator dispatches Wave 1+ implementation tickets to `worker-agy --model gemini-4-hydrogen-high` (or `gemini-4-neon-high` for complex slices), `worker-qwen`, and `worker-glm` (on overflow).
4. Verify `CI & PR Evidence` passes against clean-room Postgres 16 AND `human-gate-guard` publishes green Commit Status on `pr.head.sha`.
5. For UI/E2E PRs, confirm the Orchestrator runs `.factory/fetch-evidence.sh <run_id> <pr_num>` and inspects downloaded PNGs with Vision (`llm-proxy` `/stats` shows `/glm` and `/vision` token counts incrementing).
6. Verify the Orchestrator approves and squash-merges to `staging`, **post-merge `CI & PR Evidence` runs automatically on `push` to `staging`**, and the Sub-Issue moves to `Done`.

### Test 4 — Turn-Serialized Priority Wait-Queue & 8-Second Comment Coalescer
1. Post **2 rapid comments** (2–3 seconds apart) on the **same** open Issue or PR. Confirm `bridge` logs show them bundled into **1** combined `[GITHUB EVENT: HUMAN COMMENTS (2 bundled...)]` prompt instead of waking the Architect twice.
2. While the Architect is actively `working` on Issue A, post a comment on Issue B. Confirm `bridge` persists Issue B to `architect-queue.json`, waits for `herdr agent wait architect --until idle --until done`, and dispatches Issue B **strictly after** Issue A finishes.

### Test 5 — `Awaiting Approval` Board Column & Tamper-Proof `human-gate-guard`
1. Open a small test PR from `factory-worker[bot]` touching a protected path (e.g., `migrations/test.sql` or `auth/README.md`) **without** manually adding `human-gate`.
2. Verify `human-gate-guard` locks the PR, `webhook-bridge` adds `human-gate` + moves the card to **`Awaiting Approval`**, and the Orchestrator posts its review and **STOPS**.
3. Click **Approve** in the GitHub PR UI, wait ~10s for green status, and click **Squash and merge**.

### Test 6 — Rolling `staging -> master` Release PR & Continuous Learning
1. Once `completed === total` Sub-Issues (with Wave 0 E2E passing GREEN in CI), verify `webhook-bridge` / Orchestrator closes the parent Epic and runs `.factory/release-pr.sh <epic_num>`, opening/updating **one** rolling `staging -> master` Release PR in **`Awaiting Approval`**.
2. Click **Approve** and merge using **"Create a merge commit"** (**never Squash**). Confirm the Release PR triggers the Architect's `retro` skill.

### Test 7 — 3-Strike Specialist Rescue & Spend Circuit Breaker (`rescue-escalated`)
1. On a failing throwaway PR, verify Strikes 1–2 dispatch normal retries, Strike 3 adds `rescue-escalated` and dispatches **1 pass** to `worker-agy --model claude-opus-5-5-high` (using `conflict-and-rescue`), and a 4th failure trips the **Spend Circuit Breaker** (`blocked` label + board `Blocked` + Architect alert to human, halting all automated retries).

---

## Daily Operating Loop (Once Bootstrapped)

### 1. Start / Reattach to the Factory (1 Command)
On boot or after container recreates:
```bash
./.factory/preflight.sh
docker compose --env-file ~/.config/light-factory/compose.env up -d
docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh
```
*(Press `ctrl+b q` anytime to detach while everything keeps running. Make sure your host webhook tunnel—e.g. `tailscale funnel --bg 8787`—is running.)*

### 2. Drive Everything From GitHub (Your 3 High-Leverage Touchpoints)
1. **Rough Idea -> Plan:** Open a Feature Request and add **`plan`**. Read the Architect's Wave Blueprint + Sub-Issue Test Plans on the Issue, tweak if needed, and add **`ready`** to start autonomous execution across waves.
2. **Check One Column — `Awaiting Approval`:** Everything needing your eyes (auto-gated `migrations/`/`auth/`/`.factory/` PRs, manual `human-gate` PRs, and the rolling `staging -> master` Release PR) lands in **`Awaiting Approval`** with a purple `human-gate` badge and a formal GitHub Review Request in your inbox.
   * For gated `staging` PRs: review Architect summary -> **Approve** -> wait ~5–10s for green `human-gate-guard` -> **Squash and merge**.
   * For the rolling `staging -> master` Release PR: review changelog -> **Approve** -> wait ~5–10s -> **"Create a merge commit"** *(never Squash!)*.
3. **Check `Blocked` (Only When Pinged):** Step in if a PR hit 3 CI retries, a worker hit a stall watchdog alert, or post-merge `staging` CI flagged a regression.

### 3. Monitoring & Model/Cost Hygiene
* **Check Proxied API Spend (`GLM-5.3` Hub, `GLM-5.3-Flash` Vision, and `worker-glm` Backup):**
  ```bash
  docker compose exec herdr-hub curl -s http://llm-proxy:4000/stats | jq .
  ```
* **Check Live Queue & Watchdog Status:**
  ```bash
  curl -s http://127.0.0.1:8787/health | jq .
  ```
* **Compact Architect Between Epics:** After shipping an Epic, ask the Architect to log key decisions in `DECISIONS.md` and compact/reset its chat session to keep GLM-5.3 prompt caching fast and cheap.
* **Hot-Swap Models Anytime:** Edit `~/.config/light-factory/compose.env` (and `llm-secrets.env` if changing providers), run `./.factory/preflight.sh`, recreate `llm-proxy` / `herdr-hub` (or `worker-qwen`), and run `launch-panes.sh`.
