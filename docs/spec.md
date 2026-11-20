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

From the host machine (Docker Desktop or `docker compose ps`), the entire factory appears as **one self-contained entity: `herdr-software-factory`**. Inside, **7 sibling containers** run across **three** private Docker networks (`factory-net`, `llm-net`, and internal `db-net`) with **zero access to your host `$HOME`**, **zero `docker.sock` mounting**, **zero raw API keys inside any AI container**, and **zero Docker-in-Docker (`--privileged`)**.

### Native Herdr Visibility Across Sandboxed Containers (Zero `docker.sock`)
Each worker container is reached from `herdr-hub` over private `factory-net` via a dedicated internal-only SSH key (port `2222`, `AllowTcpForwarding no`) wrapped with Herdr's official **`HERDR_AGENT=<kind>`** screen-detection hint (`antigravity-cli`, `hermes`, `claude`) and named via `herdr agent rename`. This preserves **100% of Herdr's native multi-agent workflow** inside **one unified `herdr agent list`**:
- Real-time **`idle` / `working` / `blocked` / `done`** status rollups in the Herdr sidebar and CLI for all 4 agents (`architect`, `worker-gemini`, `worker-qwen`, `specialist-fable`).
- Native cross-agent coordination (`herdr agent list`, `herdr agent prompt`, `herdr agent wait`, `herdr agent read`, `herdr agent send-keys`), taught automatically to the Architect via `herdr --skill` installed on boot.
- Zero `docker.sock` exposure to any AI container.

### Model Roster (Option B — Unthrottled Architect + Subscription/Local Workers + Claude Code Escalation)
- **🧠 Architect (`architect` tab inside `herdr-hub`):** **GLM-5.3** inside **Hermes** (`hermes --profile architect`) with `auxiliary.vision` routed to **GLM-5.3-Flash** for inspecting Playwright screenshots downloaded locally via `.factory/fetch-evidence.sh`. Stays **execution-free** (no app builds, no direct Postgres access) so `herdr-hub` credentials stay shielded from untrusted branch code, while `.factory/sync-hub.sh` keeps `/workspace` synced with `origin/staging` before planning and rule commits. All LLM calls flow through `llm-proxy` (which also exposes `GET /stats` for proxied request & token telemetry).
- **🚦 Turn-Serialized Priority Queue, Comment Coalescer & Stall Watchdog (`bridge` tab inside `herdr-hub`):** `webhook-bridge.mjs` persists pending GitHub events to disk (inside the `hub-herdr` volume), prioritizes **human comments** ahead of queued background CI/`plan` webhooks, bundles rapid comments on the **same** Issue/PR thread within an 8-second debounce window (while keeping different threads strictly separate), waits on Herdr's native `idle`/`done` agent state before sending the next prompt, catches **post-merge `staging` CI regressions**, and runs a lightweight 15-minute watchdog alerting the Architect if an `in-progress` Sub-Issue stalls for >45 minutes without PR activity.
- **🛠️ Primary Worker & Default E2E Writer (`worker-gemini` container -> `HERDR_AGENT=antigravity-cli`):** **Gemini 3.8 Flash** inside **Antigravity CLI (`agy`)**. Absorbs fast, high-volume multi-file coding, backend/API/DB integration work, edit-test-retry loops, and **Final-Wave Playwright E2E tests** (always in a fresh, stateless session, with Chromium system deps preinstalled) on your flat-rate Google AI Pro subscription, backed by its own locked-down Postgres DB (`app_gemini`) that resets cleanly between branches.
- **🛠️ Parallel & Overflow Worker (`worker-qwen` container -> `HERDR_AGENT=hermes`):** **Local Qwen 3.8 27B** inside **Hermes** (`hermes --profile qwen`), reaching **only** your host GPU inference server via `host.docker.internal`, backed by its own locked-down Postgres DB (`app_qwen`). Handles UI, styling, unit tests, narrow 1–2 screen cross-model E2E flows (in a fresh session), and overflow if `worker-gemini` hits Antigravity's rolling quota.
- **🔥 On-Demand Escalation (`specialist-fable` container -> `HERDR_AGENT=claude`):** Borrowed **Claude Fable** via **Claude Code (`claude`)** isolated strictly inside this container—idle 95% of the time and hard-capped at **1 pass per PR** for merge conflicts, 3-strike `blocked` rescues (including deeply flaky E2E rescues), and manual `human-gate` audits, backed by its own locked-down Postgres DB (`app_fable`). Never used for routine feature coding or routine E2E writing.
- **🧩 Plan-First Decomposition, Final-Wave E2E & Rolling Release PR:** Rough or multi-step Issues labeled `plan` are inspected against a freshly synced `/workspace` and decomposed by the Architect into atomic **native GitHub Sub-Issues** (each with an explicit **Test Plan**, plus a **Final-Wave E2E Verification** Sub-Issue for multi-layer features) for a quick human sanity check before any code is written. Once approved (`ready`), the Architect checks **both** live `herdr agent list` states (`idle`/`done` vs. `working`/`blocked`) and `gh issue list --label in-progress` so no busy or blocked worker is ever double-assigned, dispatches strictly **1 unique Sub-Issue per idle worker container per PR**, and advances automatically across sequential/parallel dependency waves as PRs merge to `staging`. Whenever a parent Epic finishes on `staging`, the Architect automatically opens or updates **one rolling `staging -> master` Release PR** (via `.factory/release-pr.sh`), places it directly in the Kanban **`Awaiting Approval`** column, and requests your formal GitHub review so you can click **Approve** and merge via **"Create a merge commit"** (never squash) to production.
- **🛡️ Single-Pane `Awaiting Approval` Board + Trusted-Branch `human-gate-guard`:** Routine PRs flow to `staging` without extra labels once `ci-and-evidence` and `human-gate-guard` pass (and post-merge `staging` CI immediately catches cross-PR logical regressions). `human-gate-guard.yml` executes via `pull_request_target` + `pull_request_review` (strictly from the trusted `master` branch, never checking out PR code) and posts an explicit commit status directly onto `pr.head.sha`. Any PR locked by `human-gate-guard` (protected paths, manual `human-gate` label, or rolling `staging -> master` Release PR) is automatically badged purple (`human-gate`), requests **you as a formal PR Reviewer**, and moves straight into the dedicated **`Awaiting Approval`** column on the Project Board—waiting for **you** to click **Approve** and **Merge**.
- **📚 Progressive-Disclosure Skills (`.agents/skills/` & `.factory/role-skills/`):** Shared coding/domain skills (`modern-web-standards`, `postgres-migrations`, `e2e-testing`) are available on demand to **all** builders and reviewers without bloating Qwen's 54k context budget, while orchestration/rescue playbooks (including Herdr's bundled `herdr --skill`) are scoped strictly to Architect and Fable.

### Zero-Trust Container, Secret, Database & GitHub App Isolation
Each tier is isolated across **four** boundaries: container/network isolation (`factory-net`, `llm-net`, `db-net`), zero-key sidecars (`auth-minter` + `llm-proxy`), per-worker Postgres isolation (`factory-postgres`), and GitHub server-side locks (**2 GitHub Apps** + **3 Stacked Rulesets** + **trusted `human-gate-guard`**):

| Container / Role | Network(s) | Can See | Completely Blind To |
| :--- | :--- | :--- | :--- |
| **`auth-minter`** *(No LLM, no repo)* | `factory-net` | Host GitHub `.pem` keys (`:ro`), `apps.env` (`:ro`) | Repo code, LLM API keys, Postgres, inbound internet |
| **`llm-proxy`** *(No LLM, no repo)* | `llm-net` | Host `llm-secrets.env` (`:ro`), model allowlist, hourly caps, `/stats` telemetry | Repo code, GitHub `.pem` keys, Postgres, routine workers |
| **`factory-postgres`** *(Postgres 16)* | `db-net` *(internal)* | 3 isolated non-superuser DBs (`app_gemini`, `app_qwen`, `app_fable`) | Internet, host `$HOME`, `herdr-hub`, GitHub/LLM secrets |
| **`herdr-hub`** *(Herdr + Bridge + Architect)* | `factory-net`, `llm-net` | `auth-architect:ro`, dummy proxy key, own `/workspace`, `bridge.env:ro`, shared + architect + `herdr` skills | Host `$HOME`, `.pem` keys, **real API keys**, `docker.sock`, **`factory-postgres`**, Fable auth |
| **`worker-gemini`** *(Antigravity CLI)* | `factory-net`, `db-net` | `auth-worker:ro`, own `/workspace`, own `gemini-auth`, `app_gemini` DB, shared domain skills | Host `$HOME`, `.pem` keys, `llm-proxy`, `architect` token, `app_qwen`/`app_fable` DBs, Fable auth |
| **`worker-qwen`** *(Hermes Local Qwen)* | `factory-net`, `db-net` | `auth-worker:ro`, own `/workspace`, host GPU port, `app_qwen` DB, shared domain skills | Host `$HOME`, `.pem` keys, `llm-proxy`, `architect` token, `app_gemini`/`app_fable` DBs, Fable auth |
| **`specialist-fable`** *(Claude Code, IDLE 95%)* | `factory-net`, `llm-net`, `db-net` | `auth-worker:ro`, own `/workspace`, own `fable-auth`, `app_fable` DB, shared + fable skills | Host `$HOME`, `.pem` keys, **real API keys**, `architect` token, `app_gemini`/`app_qwen` DBs |

> **Why Gemini, Qwen, and `specialist-fable` Share One `factory-worker` App:**
> Because all execution containers authenticate as `factory-worker[bot]`, GitHub treats them as the **same PR author**—so no worker or specialist can rubber-stamp or self-merge its own commits, E2E tests, or conflict fixes. Every PR must pass CI (`ci-and-evidence`) + server-enforced `human-gate-guard` and be formally approved by `factory-architect[bot]` (or You for gated paths/`human-gate`/production `master` PRs).

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
│  DOCKER COMPOSE STACK: herdr-software-factory  (ZERO host $HOME / docker.sock)
│                                                                              │
│  ┌───────────────────────────────┐     ┌──────────────────────────────────┐  │
│  │ Container: auth-minter        │     │ Container: llm-proxy (:4000)     │  │
│  │  • ONLY sees host .pem keys   │     │  • ONLY sees llm-secrets.env     │  │
│  │  • Mints 1h tokens every 45m  │     │  • Injects real GLM/Vision/Anth  │  │
│  └──────┬──────────────────┬─────┘     │    headers + cap + GET /stats    │  │
│         │ vol:             │ vol:      └──────────┬───────────────┬───────┘  │
│         │ auth-architect   │ auth-worker          │ llm-net       │ llm-net  │
│         ▼ (:ro)            ▼ (:ro)                ▼ (/glm,/vision)│ (/anthr) │
│  ┌────────────────────────────────────┐                           │          │
│  │ Container: herdr-hub               │ Identity: factory-architect[bot]     │
│  │  • Tab: bridge (priority Q+watch)  │ Execution-free (NO db-net route)     │
│  │  • Tab: architect (GLM-5.3+Vision) │ Unified `herdr agent list` via       │
│  │  • HERDR_AGENT=<kind> ssh-t tabs   │ `HERDR_AGENT=` + `herdr --skill`     │
│  └───┬──────────────────┬─────────┬───┘                           │          │
│      │ internal SSH     │         │ internal SSH (escalation ONLY)│          │
│      ▼ (antigravity-cli)▼ (hermes)▼ (claude)                      ▼          │
│  ┌──────────────┐ ┌──────────────┐ ┌────────────────────────────────────┐    │
│  │ worker-gemini│ │ worker-qwen  │ │ specialist-fable (IDLE 95%)        │    │
│  │ Antigravity  │ │ Hermes Local │ │ Claude Code (`claude`)             │    │
│  │ Gemini 3.8 Fl│ │ Qwen 3.8 27B │ │ OAuth in fable-auth OR proxied key │    │
│  │ + Primary E2E│ │ + Narrow E2E │ │ + 1-Pass Rescue Only               │    │
│  │ app_gemini   │ │ app_qwen     │ │ app_fable                          │    │
│  └──────┬───────┘ └──────┬───────┘ └─────────────────┬──────────────────┘    │
│         │ db-net         │ db-net                    │ db-net                │
│         └────────────────┼───────────────────────────┘                       │
│                          ▼                                                   │
│        ┌───────────────────────────────────────────────────────┐             │
│        │ Container: factory-postgres (Postgres 16, internal)   │             │
│        │  • 3 locked-down non-superuser DBs (REVOKE PUBLIC)    │             │
│        │  • Extensions isolated in `extensions` schema         │             │
│        │  • app_gemini | app_qwen | app_fable (30s timeout)    │             │
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
> #### App 2: `factory-worker` *(Peer Execution Workers — Gemini 3.8 Flash, Local Qwen & Claude Code Fable)*
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

# 3. Specialist Fable via Claude Code (OPTIONAL: leave ANTHROPIC_API_KEY blank if using `claude login` OAuth)
ANTHROPIC_UPSTREAM_URL=https://api.anthropic.com
ANTHROPIC_API_KEY=

# 4. Hard hourly circuit breakers (prevents runaway loop spend)
GLM_MAX_REQ_PER_HOUR=240
FABLE_MAX_REQ_PER_HOUR=60
EOF
chmod 600 ~/.config/light-factory/llm-secrets.env
```
> *(Optional — Personal Accounts Only: If this is a personal repo rather than an Organization repo, GitHub currently restricts GitHub Apps from mutating user-owned Projects v2 boards. To keep the Kanban board synced without exposing your full account to workers, you may add `GH_PROJECT_TOKEN=<classic_token_with_project_scope_only>` to `~/.config/light-factory/apps.env`. `auth-minter` will copy it exclusively into the `auth-architect` volume—workers never see it.)*

### 2.2 Create Local Factory Directories & `.gitignore` Entries
```bash
mkdir -p .factory/bin .factory/docker .factory/postgres \
         .factory/role-skills/architect/pr-evidence-review \
         .factory/role-skills/fable/conflict-and-rescue \
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

```javascript
#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const APPS_ENV_PATH =
  process.env.FACTORY_APPS_ENV || "/run/factory-config/apps.env";
const AUTH_ROOT = process.env.FACTORY_AUTH_ROOT || "/run/factory-auth";
const REFRESH_MS = 45 * 60 * 1000;
const RUN_ONCE = process.argv.includes("--once");

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing apps config file: ${filePath}`);
  }
  const env = {};
  for (const line of fs.readFileSync(filePath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx > 0) {
      const key = trimmed.slice(0, idx).trim();
      let val = trimmed.slice(idx + 1).trim().replace(/^["']|["']$/g, "");
      val = val.replace(/^\$HOME\b/, os.homedir()).replace(/^~\//, `${os.homedir()}/`);
      env[key] = val;
    }
  }
  return env;
}

function createAppJwt(appId, privateKeyPem) {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: "RS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(
    JSON.stringify({ iat: now - 60, exp: now + 540, iss: String(appId) })
  ).toString("base64url");
  const unsigned = `${header}.${payload}`;
  const signature = crypto
    .sign("RSA-SHA256", Buffer.from(unsigned), privateKeyPem)
    .toString("base64url");
  return `${unsigned}.${signature}`;
}

function writeAtomic(filePath, content, mode = 0o600) {
  const tmpPath = `${filePath}.tmp.${process.pid}`;
  fs.writeFileSync(tmpPath, content, { mode });
  fs.renameSync(tmpPath, filePath);
}

async function mintInstallationToken(roleName, appId, installationId, keyPath, slug) {
  if (!appId || !installationId || !keyPath) {
    throw new Error(`Incomplete configuration for role "${roleName}" in ${APPS_ENV_PATH}`);
  }
  const pem = fs.readFileSync(keyPath, "utf8");
  const jwt = createAppJwt(appId, pem);

  const res = await fetch(
    `https://api.github.com/app/installations/${installationId}/access_tokens`,
    {
      method: "POST",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${jwt}`,
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "herdr-software-factory-token-refresher",
      },
    }
  );

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`GitHub token mint failed for ${roleName} (${res.status}): ${errText}`);
  }

  const data = await res.json();
  const roleDir = path.join(AUTH_ROOT, roleName);
  fs.mkdirSync(roleDir, { recursive: true, mode: 0o700 });

  writeAtomic(path.join(roleDir, "token"), data.token, 0o600);
  writeAtomic(
    path.join(roleDir, "meta.json"),
    JSON.stringify(
      {
        role: roleName,
        slug: slug || `factory-${roleName}`,
        appId: String(appId),
        expiresAt: data.expires_at,
        mintedAt: new Date().toISOString(),
      },
      null,
      2
    ),
    0o600
  );

  console.log(
    `[auth-minter] Minted 1h token for ${roleName} (${slug || roleName}[bot]) — expires ${data.expires_at}`
  );
}

async function refreshAll() {
  const cfg = loadEnvFile(APPS_ENV_PATH);
  fs.mkdirSync(AUTH_ROOT, { recursive: true, mode: 0o700 });

  await mintInstallationToken(
    "architect",
    cfg.ARCHITECT_APP_ID,
    cfg.ARCHITECT_INSTALLATION_ID,
    cfg.ARCHITECT_KEY_PATH,
    cfg.ARCHITECT_SLUG
  );

  await mintInstallationToken(
    "worker",
    cfg.WORKER_APP_ID,
    cfg.WORKER_INSTALLATION_ID,
    cfg.WORKER_KEY_PATH,
    cfg.WORKER_SLUG
  );

  const projectTokenPath = path.join(AUTH_ROOT, "architect", "project-token");
  if (cfg.GH_PROJECT_TOKEN) {
    writeAtomic(projectTokenPath, cfg.GH_PROJECT_TOKEN, 0o600);
  } else if (fs.existsSync(projectTokenPath)) {
    fs.unlinkSync(projectTokenPath);
  }
}

try {
  await refreshAll();
  if (RUN_ONCE) process.exit(0);
} catch (err) {
  console.error("[auth-minter] FATAL initial token mint error:", err.message);
  process.exit(1);
}

async function scheduleNextRefresh(delayMs) {
  setTimeout(async () => {
    try {
      await refreshAll();
      scheduleNextRefresh(REFRESH_MS);
    } catch (err) {
      console.error("[auth-minter] ERROR refreshing tokens (retrying in 60s):", err.message);
      scheduleNextRefresh(60 * 1000);
    }
  }, delayMs);
}

scheduleNextRefresh(REFRESH_MS);
```

### 2.4 Create Zero-Key LLM Proxy Sidecar With `/stats` Telemetry (`.factory/llm-proxy.mjs`)
Create `.factory/llm-proxy.mjs` (`chmod +x .factory/llm-proxy.mjs`).
Runs exclusively inside the `llm-proxy` container. Keeps real API keys completely outside every AI container, injects real upstream auth headers in flight, enforces a strict model allowlist and hourly request caps, and exposes **`GET /stats`** tracking request counts and prompt/completion tokens across proxied API routes (`/glm`, `/vision`, and `/anthropic` when `FABLE_AUTH_MODE=proxy`).
> *Telemetry Scope Note:* `/stats` tracks metered API calls passing through `llm-proxy` (Architect GLM-5.3, GLM-5.3-Flash Vision, and Fable in `proxy` mode). Direct subscription CLIs (`agy` OAuth and `claude login` OAuth) and local GPU Qwen bypass `llm-proxy` by design.

```javascript
#!/usr/bin/env node
import http from "node:http";
import fs from "node:fs";
import { Readable, Transform } from "node:stream";

const SECRETS_FILE =
  process.env.LLM_SECRETS_FILE || "/run/factory-config/llm-secrets.env";
const PORT = Number(process.env.LLM_PROXY_PORT || 4000);
const ARCHITECT_PROXY_TOKEN =
  process.env.ARCHITECT_PROXY_TOKEN || "proxy-architect-only";
const FABLE_PROXY_TOKEN =
  process.env.FABLE_PROXY_TOKEN || "proxy-fable-only";
const MAX_BODY_BYTES = 25 * 1024 * 1024; // 25MB (supports Playwright base64 screenshots)

function loadSecrets(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing LLM secrets file: ${filePath}`);
  }
  const cfg = {};
  for (const line of fs.readFileSync(filePath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx > 0) {
      const k = trimmed.slice(0, idx).trim();
      const v = trimmed.slice(idx + 1).trim().replace(/^["']|["']$/g, "");
      cfg[k] = v;
    }
  }
  return cfg;
}

const secrets = loadSecrets(SECRETS_FILE);

const GLM_UPSTREAM_URL = (secrets.GLM_UPSTREAM_URL || "").replace(/\/+$/, "");
const GLM_API_KEY = secrets.GLM_API_KEY || "";
const VISION_UPSTREAM_URL = (
  secrets.VISION_UPSTREAM_URL || GLM_UPSTREAM_URL
).replace(/\/+$/, "");
const VISION_API_KEY = secrets.VISION_API_KEY || GLM_API_KEY;

const ANTHROPIC_UPSTREAM_URL = (
  secrets.ANTHROPIC_UPSTREAM_URL || "https://api.anthropic.com"
).replace(/\/+$/, "");
const ANTHROPIC_API_KEY = secrets.ANTHROPIC_API_KEY || "";

const GLM_MAX_REQ_PER_HOUR = Number(secrets.GLM_MAX_REQ_PER_HOUR || 240);
const FABLE_MAX_REQ_PER_HOUR = Number(secrets.FABLE_MAX_REQ_PER_HOUR || 60);

const ALLOWED_ARCHITECT_MODELS = new Set(
  [
    process.env.ARCHITECT_MODEL,
    process.env.ARCHITECT_VISION_MODEL,
    ...(process.env.EXTRA_ALLOWED_MODELS || "").split(","),
  ]
    .map((m) => (m || "").trim())
    .filter(Boolean)
);

if (!GLM_UPSTREAM_URL) {
  console.error("[llm-proxy] FATAL: GLM_UPSTREAM_URL is required in llm-secrets.env");
  process.exit(1);
}

const rateBuckets = { glm: [], fable: [] };

function emptyRouteStats() {
  return {
    requests: 0,
    errors: 0,
    rateLimited: 0,
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0,
    byModel: {},
    lastRequestAt: null,
  };
}

const telemetry = {
  startedAt: new Date().toISOString(),
  note: "Tracks API traffic routed through llm-proxy (GLM, Vision, and Fable proxy mode). Direct OAuth subscriptions (Antigravity / claude login) and local GPU Qwen bypass llm-proxy.",
  routes: {
    glm: emptyRouteStats(),
    vision: emptyRouteStats(),
    anthropic: emptyRouteStats(),
  },
};

function recordUsage(route, modelName, promptTokens, completionTokens, totalTokens) {
  const r = telemetry.routes[route];
  if (!r) return;
  const p = Number(promptTokens || 0);
  const c = Number(completionTokens || 0);
  const t = Number(totalTokens || p + c);
  if (p <= 0 && c <= 0 && t <= 0) return;

  r.promptTokens += p;
  r.completionTokens += c;
  r.totalTokens += t;

  const mKey = modelName || "unknown";
  if (!r.byModel[mKey]) {
    r.byModel[mKey] = { requests: 0, promptTokens: 0, completionTokens: 0, totalTokens: 0 };
  }
  r.byModel[mKey].promptTokens += p;
  r.byModel[mKey].completionTokens += c;
  r.byModel[mKey].totalTokens += t;
}

function recordModelRequest(route, modelName) {
  const r = telemetry.routes[route];
  if (!r) return;
  r.requests += 1;
  r.lastRequestAt = new Date().toISOString();
  const mKey = modelName || "unknown";
  if (!r.byModel[mKey]) {
    r.byModel[mKey] = { requests: 0, promptTokens: 0, completionTokens: 0, totalTokens: 0 };
  }
  r.byModel[mKey].requests += 1;
}

// Non-blocking pass-through telemetry stream (supports JSON & SSE for OpenAI/GLM & Anthropic)
function createUsageTapStream(route, modelName, contentType) {
  const isSse = String(contentType || "").toLowerCase().includes("text/event-stream");
  const isJson = String(contentType || "").toLowerCase().includes("application/json");
  let sseTail = "";
  let jsonBuf = [];
  let jsonSize = 0;
  let capturedPrompt = 0;
  let capturedCompletion = 0;
  let capturedTotal = 0;

  function extractFromObj(obj) {
    if (!obj || typeof obj !== "object") return;
    // OpenAI / GLM format
    if (obj.usage && typeof obj.usage === "object") {
      if (obj.usage.prompt_tokens != null) capturedPrompt = Math.max(capturedPrompt, Number(obj.usage.prompt_tokens) || 0);
      if (obj.usage.completion_tokens != null) capturedCompletion = Math.max(capturedCompletion, Number(obj.usage.completion_tokens) || 0);
      if (obj.usage.total_tokens != null) capturedTotal = Math.max(capturedTotal, Number(obj.usage.total_tokens) || 0);
      // Anthropic format (non-streaming & message_delta)
      if (obj.usage.input_tokens != null) capturedPrompt = Math.max(capturedPrompt, Number(obj.usage.input_tokens) || 0);
      if (obj.usage.output_tokens != null) capturedCompletion = Math.max(capturedCompletion, Number(obj.usage.output_tokens) || 0);
    }
    // Anthropic message_start SSE event
    if (obj.message?.usage) {
      if (obj.message.usage.input_tokens != null) {
        capturedPrompt = Math.max(capturedPrompt, Number(obj.message.usage.input_tokens) || 0);
      }
      if (obj.message.usage.output_tokens != null) {
        capturedCompletion = Math.max(capturedCompletion, Number(obj.message.usage.output_tokens) || 0);
      }
    }
  }

  return new Transform({
    transform(chunk, _encoding, callback) {
      try {
        if (isSse) {
          sseTail += chunk.toString("utf8");
          const lines = sseTail.split(/\r?\n/);
          sseTail = lines.pop() || "";
          for (const line of lines) {
            if (!line.startsWith("data:")) continue;
            const dataStr = line.slice(5).trim();
            if (!dataStr || dataStr === "[DONE]") continue;
            try {
              extractFromObj(JSON.parse(dataStr));
            } catch {
              // Ignore partial or non-JSON SSE lines
            }
          }
        } else if (isJson && jsonSize < 2 * 1024 * 1024) {
          jsonBuf.push(chunk);
          jsonSize += chunk.length;
        }
      } catch {
        // Telemetry must never interrupt LLM response streaming
      }
      callback(null, chunk);
    },
    flush(callback) {
      try {
        if (isJson && jsonBuf.length > 0) {
          extractFromObj(JSON.parse(Buffer.concat(jsonBuf).toString("utf8")));
        }
        recordUsage(route, modelName, capturedPrompt, capturedCompletion, capturedTotal);
      } catch {
        // Ignore parse failures on non-JSON or truncated responses
      }
      callback();
    },
  });
}

function checkRateLimit(bucket, limit) {
  if (limit <= 0) return true;
  const now = Date.now();
  const cutoff = now - 60 * 60 * 1000;
  rateBuckets[bucket] = rateBuckets[bucket].filter((ts) => ts > cutoff);
  if (rateBuckets[bucket].length >= limit) return false;
  rateBuckets[bucket].push(now);
  return true;
}

function joinUpstreamUrl(baseUrl, subPath) {
  let cleanSub = subPath.startsWith("/") ? subPath : `/${subPath}`;
  if (/\/v\d+$/.test(baseUrl) && cleanSub.startsWith("/v1/")) {
    cleanSub = cleanSub.slice(3);
  }
  return `${baseUrl}${cleanSub}`;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    req.on("data", (chunk) => {
      total += chunk.length;
      if (total > MAX_BODY_BYTES) {
        reject(new Error("Payload too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

function sendJson(res, status, obj) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(obj, null, 2));
}

const SKIP_REQ_HEADERS = new Set([
  "host",
  "connection",
  "content-length",
  "transfer-encoding",
  "authorization",
  "x-api-key",
]);

const SKIP_RES_HEADERS = new Set([
  "connection",
  "keep-alive",
  "transfer-encoding",
  "content-encoding",
  "content-length",
]);

const server = http.createServer(async (req, res) => {
  const rawUrl = req.url || "/";
  if (req.method === "GET" && rawUrl === "/health") {
    return sendJson(res, 200, {
      ok: true,
      routes: {
        glm: Boolean(GLM_UPSTREAM_URL),
        vision: Boolean(VISION_UPSTREAM_URL),
        anthropic: Boolean(ANTHROPIC_API_KEY),
      },
      allowedArchitectModels: [...ALLOWED_ARCHITECT_MODELS],
    });
  }

  if (req.method === "GET" && rawUrl === "/stats") {
    const now = Date.now();
    const cutoff = now - 60 * 60 * 1000;
    return sendJson(res, 200, {
      ...telemetry,
      rollingLastHour: {
        glmAndVisionRequests: rateBuckets.glm.filter((ts) => ts > cutoff).length,
        glmMaxPerHour: GLM_MAX_REQ_PER_HOUR,
        fableRequests: rateBuckets.fable.filter((ts) => ts > cutoff).length,
        fableMaxPerHour: FABLE_MAX_REQ_PER_HOUR,
      },
    });
  }

  let route = null;
  let subPath = "";
  if (rawUrl === "/glm" || rawUrl.startsWith("/glm/")) {
    route = "glm";
    subPath = rawUrl.slice("/glm".length) || "/";
  } else if (rawUrl === "/vision" || rawUrl.startsWith("/vision/")) {
    route = "vision";
    subPath = rawUrl.slice("/vision".length) || "/";
  } else if (rawUrl === "/anthropic" || rawUrl.startsWith("/anthropic/")) {
    route = "anthropic";
    subPath = rawUrl.slice("/anthropic".length) || "/";
  } else {
    return sendJson(res, 404, { error: "Unknown proxy route. Use /glm, /vision, /anthropic, /health, or /stats." });
  }

  const incomingAuth = String(req.headers["authorization"] || "");
  const incomingXApiKey = String(req.headers["x-api-key"] || "");

  if (route === "glm" || route === "vision") {
    if (incomingAuth !== `Bearer ${ARCHITECT_PROXY_TOKEN}`) {
      return sendJson(res, 401, { error: "Unauthorized for architect LLM route" });
    }
    if (!checkRateLimit("glm", GLM_MAX_REQ_PER_HOUR)) {
      telemetry.routes[route].rateLimited += 1;
      return sendJson(res, 429, { error: `Architect hourly limit (${GLM_MAX_REQ_PER_HOUR}/hr) exceeded` });
    }
  } else if (route === "anthropic") {
    if (!ANTHROPIC_API_KEY) {
      return sendJson(res, 503, {
        error: "Anthropic proxy disabled (ANTHROPIC_API_KEY unset; using Claude Code OAuth mode)",
      });
    }
    const valid =
      incomingXApiKey === FABLE_PROXY_TOKEN ||
      incomingAuth === `Bearer ${FABLE_PROXY_TOKEN}`;
    if (!valid) {
      return sendJson(res, 401, { error: "Unauthorized for Fable Anthropic route" });
    }
    if (!checkRateLimit("fable", FABLE_MAX_REQ_PER_HOUR)) {
      telemetry.routes.anthropic.rateLimited += 1;
      return sendJson(res, 429, { error: `Fable hourly limit (${FABLE_MAX_REQ_PER_HOUR}/hr) exceeded` });
    }
  }

  let bodyBuf;
  try {
    bodyBuf = req.method === "GET" || req.method === "HEAD" ? null : await readBody(req);
  } catch (err) {
    return sendJson(res, 413, { error: err.message });
  }

  let requestedModel = "";
  if (
    bodyBuf &&
    bodyBuf.length > 0 &&
    String(req.headers["content-type"] || "").includes("application/json")
  ) {
    try {
      const parsed = JSON.parse(bodyBuf.toString("utf8"));
      requestedModel = String(parsed?.model || "");
      if (
        (route === "glm" || route === "vision") &&
        ALLOWED_ARCHITECT_MODELS.size > 0 &&
        requestedModel &&
        !ALLOWED_ARCHITECT_MODELS.has(requestedModel)
      ) {
        console.warn(`[llm-proxy] Blocked disallowed model "${requestedModel}" on /${route}`);
        return sendJson(res, 403, {
          error: `Model "${requestedModel}" is not in allowed list: ${[...ALLOWED_ARCHITECT_MODELS].join(", ")}`,
        });
      }
    } catch {
      // Non-JSON or malformed body; let upstream validate
    }
  }

  let targetUrl = "";
  const outHeaders = {};
  for (const [k, v] of Object.entries(req.headers)) {
    const lk = k.toLowerCase();
    if (!SKIP_REQ_HEADERS.has(lk) && v !== undefined) {
      outHeaders[lk] = Array.isArray(v) ? v.join(", ") : v;
    }
  }

  if (route === "glm") {
    targetUrl = joinUpstreamUrl(GLM_UPSTREAM_URL, subPath);
    if (GLM_API_KEY) outHeaders["authorization"] = `Bearer ${GLM_API_KEY}`;
  } else if (route === "vision") {
    targetUrl = joinUpstreamUrl(VISION_UPSTREAM_URL, subPath);
    if (VISION_API_KEY) outHeaders["authorization"] = `Bearer ${VISION_API_KEY}`;
  } else if (route === "anthropic") {
    targetUrl = joinUpstreamUrl(ANTHROPIC_UPSTREAM_URL, subPath);
    outHeaders["x-api-key"] = ANTHROPIC_API_KEY;
  }

  recordModelRequest(route, requestedModel);

  try {
    const upstreamRes = await fetch(targetUrl, {
      method: req.method,
      headers: outHeaders,
      body: bodyBuf && bodyBuf.length > 0 ? bodyBuf : undefined,
    });

    if (!upstreamRes.ok) {
      telemetry.routes[route].errors += 1;
    }

    const resHeaders = {};
    upstreamRes.headers.forEach((val, key) => {
      if (!SKIP_RES_HEADERS.has(key.toLowerCase())) {
        resHeaders[key] = val;
      }
    });

    res.writeHead(upstreamRes.status, resHeaders);
    if (upstreamRes.body) {
      const tap = createUsageTapStream(route, requestedModel, upstreamRes.headers.get("content-type"));
      res.on("close", () => tap.destroy());
      Readable.fromWeb(upstreamRes.body).pipe(tap).pipe(res);
    } else {
      res.end();
    }
  } catch (err) {
    telemetry.routes[route].errors += 1;
    console.error(`[llm-proxy] Upstream error on /${route}:`, err.message);
    if (!res.headersSent) {
      sendJson(res, 502, { error: "Upstream inference server unreachable" });
    }
  }
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(
    `[llm-proxy] Listening on :${PORT} | GLM->${GLM_UPSTREAM_URL} | Vision->${VISION_UPSTREAM_URL} | AnthropicProxy=${ANTHROPIC_API_KEY ? "enabled" : "oauth-mode"} | Allowed=[${[...ALLOWED_ARCHITECT_MODELS].join(", ")}] | Telemetry: GET /stats`
  );
});
```

### 2.5 Create Role-Isolated `gh` Wrapper, Git Credential Helper & Role Loader
Create `.factory/bin/gh`, `.factory/git-credential-factory.sh`, and `.factory/enter-role.sh` (`chmod +x` all three).

**File 1: `.factory/bin/gh`**
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEAN_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -Fxv "$SCRIPT_DIR" | paste -sd ':' -)"
REAL_GH="$(PATH="$CLEAN_PATH" command -v gh)"

ROLE="${FACTORY_ROLE:-}"
AUTH_ROOT="${FACTORY_AUTH_ROOT:-/run/factory-auth}"

if [ -n "$ROLE" ]; then
  TOKEN_FILE="${AUTH_ROOT}/${ROLE}/token"
  if [ ! -r "$TOKEN_FILE" ]; then
    echo "[factory-gh] ERROR: Missing 1h token for role '${ROLE}' at ${TOKEN_FILE}. Is auth-minter running?" >&2
    exit 1
  fi
  export GH_TOKEN="$(cat "$TOKEN_FILE")"
  export GH_CONFIG_DIR="/tmp/factory-gh-config-${ROLE}"
  mkdir -p "$GH_CONFIG_DIR"
fi

exec "$REAL_GH" "$@"
```

**File 2: `.factory/git-credential-factory.sh`**
```bash
#!/usr/bin/env bash
# Git credential helper: serves the live 1-hour GitHub App token over HTTPS
set -euo pipefail

[ "${1:-}" = "get" ] || exit 0

ROLE="${FACTORY_ROLE:-}"
AUTH_ROOT="${FACTORY_AUTH_ROOT:-/run/factory-auth}"
TOKEN_FILE="${AUTH_ROOT}/${ROLE}/token"

if [ -z "$ROLE" ] || [ ! -r "$TOKEN_FILE" ]; then
  exit 1
fi

HOST=""
while IFS='=' read -r k v; do
  [ -z "$k" ] && break
  if [ "$k" = "host" ]; then HOST="$v"; fi
done

if [ "$HOST" = "github.com" ]; then
  printf 'protocol=https\nhost=github.com\nusername=x-access-token\npassword=%s\n' "$(cat "$TOKEN_FILE")"
fi
```

**File 3: `.factory/enter-role.sh`**
*(Automatically sourced by container `.bashrc` inside `herdr-hub` and all 3 worker containers)*
```bash
#!/usr/bin/env bash
# Usage: source /workspace/.factory/enter-role.sh <architect|worker>

ROLE="${1:-${FACTORY_ROLE:-}}"
if [ "$ROLE" != "architect" ] && [ "$ROLE" != "worker" ]; then
  echo "Usage: source .factory/enter-role.sh <architect|worker>" >&2
  return 1 2>/dev/null || exit 1
fi

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_ROOT="${FACTORY_AUTH_ROOT:-/run/factory-auth}"
META_FILE="${AUTH_ROOT}/${ROLE}/meta.json"

export FACTORY_ROLE="$ROLE"
export FACTORY_AUTH_ROOT="$AUTH_ROOT"
export GH_CONFIG_DIR="/tmp/factory-gh-config-${ROLE}"
mkdir -p "$GH_CONFIG_DIR"

case ":${PATH}:" in
  *":${FACTORY_DIR}/bin:"*) ;;
  *) export PATH="${FACTORY_DIR}/bin:${PATH}" ;;
esac

# Force HTTPS App-token auth for git (never personal SSH keys)
export GIT_SSH_COMMAND="/bin/false"
export GIT_TERMINAL_PROMPT="0"
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0="credential.helper"
export GIT_CONFIG_VALUE_0=""
export GIT_CONFIG_KEY_1="credential.helper"
export GIT_CONFIG_VALUE_1="!${FACTORY_DIR}/git-credential-factory.sh"

# Attribute commits cleanly to the GitHub App bot identity
if [ -r "$META_FILE" ] && command -v jq >/dev/null 2>&1; then
  BOT_SLUG="$(jq -r '.slug' "$META_FILE")"
  APP_ID="$(jq -r '.appId' "$META_FILE")"
  export GIT_AUTHOR_NAME="${BOT_SLUG}[bot]"
  export GIT_COMMITTER_NAME="${BOT_SLUG}[bot]"
  export GIT_AUTHOR_EMAIL="${APP_ID}+${BOT_SLUG}[bot]@users.noreply.github.com"
  export GIT_COMMITTER_EMAIL="${APP_ID}+${BOT_SLUG}[bot]@users.noreply.github.com"
fi
```

**Phase 2 Verification:** Confirm (via `test -s`, without printing secret contents) that `~/.config/light-factory/keys/{architect,worker}.pem`, `~/.config/light-factory/internal-ssh/id_ed25519`, `~/.config/light-factory/apps.env`, and `~/.config/light-factory/llm-secrets.env` all exist with `600` permissions, and `.factory/token-refresher.mjs`, `.factory/llm-proxy.mjs`, `.factory/bin/gh`, `.factory/git-credential-factory.sh`, and `.factory/enter-role.sh` are executable.

---

## Phase 3: Docker Sandbox Stack (`herdr-software-factory`) & Isolated Postgres

Every container maintains its own **independent repo clone** inside its own Docker volume (`/workspace`), each worker receives its own **locked-down Postgres database** inside `factory-postgres` via `DATABASE_URL` (with clean schema reset between branches), and Hermes / Claude Code / skill paths (including Herdr's built-in `herdr --skill` for the Architect) are **auto-synced on container boot**.

### 3.1 Create Container Helpers: Skill Sync, Hub Sync, Vision Evidence Fetch & Clean Branch Prep
Create all four scripts (`chmod +x` each):

**File 1: `.factory/sync-skills.sh`**
Links repo-tracked progressive-disclosure skills into each agent's native skill directory on boot and before each branch, and installs Herdr's release-matched `herdr --skill` exclusively into the Architect's Hermes skills directory so GLM-5.3 natively masters Herdr multi-agent orchestration.

```bash
#!/usr/bin/env bash
# Usage: .factory/sync-skills.sh <architect|worker-gemini|worker-qwen|specialist-fable>
set -euo pipefail

AGENT_ID="${1:-${WORKER_NAME:-architect}}"
SHARED_DIR="/workspace/.agents/skills"
ROLE_DIR="/workspace/.factory/role-skills"

link_skills_into() {
  local target_dir="$1"
  shift
  mkdir -p "$target_dir"
  # Remove stale symlinks pointing into /workspace so deleted/renamed skills stay clean
  find "$target_dir" -maxdepth 1 -type l -lname '/workspace/*' -delete 2>/dev/null || true
  for src_root in "$@"; do
    [ -d "$src_root" ] || continue
    for skill_dir in "$src_root"/*; do
      [ -d "$skill_dir" ] || continue
      ln -sfn "$skill_dir" "${target_dir}/$(basename "$skill_dir")"
    done
  done
}

case "$AGENT_ID" in
  architect)
    # Architect gets shared domain skills + architect review rubric + native Herdr CLI skill
    link_skills_into "$HOME/.hermes/skills" "$SHARED_DIR" "${ROLE_DIR}/architect"
    if command -v herdr >/dev/null 2>&1; then
      mkdir -p "$HOME/.hermes/skills/herdr"
      herdr --skill > "$HOME/.hermes/skills/herdr/SKILL.md" 2>/dev/null || true
    fi
    ;;
  worker-gemini)
    # Antigravity discovers .agents/skills natively + fallback symlink in user skills dir
    link_skills_into "$HOME/.gemini/antigravity/skills" "$SHARED_DIR"
    ;;
  worker-qwen)
    # Qwen (Hermes) gets shared domain skills ONLY (keeps 54k context clean)
    link_skills_into "$HOME/.hermes/skills" "$SHARED_DIR"
    ;;
  specialist-fable)
    # Claude Code gets shared domain skills + Fable conflict/rescue playbook
    link_skills_into "$HOME/.claude/skills" "$SHARED_DIR" "${ROLE_DIR}/fable"
    ;;
esac
```

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
> **Exit Code `2` (`MERGE_CONFLICT`):** Leaves exact conflict markers in `/workspace` for `specialist-fable` to resolve—or signals `worker-gemini` / `worker-qwen` to immediately run `git merge --abort` and escalate to the Architect for Fable.

### 3.2 Create Isolated Multi-Worker Postgres Init Script (`.factory/postgres/init-dbs.sh`)
Create `.factory/postgres/init-dbs.sh` (`chmod +x .factory/postgres/init-dbs.sh`).
Provisions **3 locked-down, non-superuser databases** (`app_gemini`, `app_qwen`, `app_fable`) with `REVOKE ALL ON DATABASE ... FROM PUBLIC`, a `30s` statement timeout, and a dedicated **`extensions` schema** (on each worker's `search_path`) so `.factory/prep-branch.sh` can safely run `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` as a non-superuser without dropping or requiring superuser rights for `pgcrypto` / `uuid-ossp`.

```bash
#!/usr/bin/env bash
set -euo pipefail

create_isolated_db() {
  local role_name="$1"
  local db_name="$2"
  local role_pass="$3"

  echo "[factory-postgres] Provisioning isolated DB '${db_name}' for role '${role_name}'..."
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE ROLE ${role_name} WITH LOGIN PASSWORD '${role_pass}' NOSUPERUSER NOCREATEDB NOCREATEROLE;
    ALTER ROLE ${role_name} SET statement_timeout = '30s';
    ALTER ROLE ${role_name} SET search_path TO public, extensions;
    CREATE DATABASE ${db_name} OWNER ${role_name};
    REVOKE ALL ON DATABASE ${db_name} FROM PUBLIC;
    GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${role_name};
EOSQL

  # Pre-install extensions in a dedicated `extensions` schema so workers can cleanly
  # DROP/CREATE SCHEMA public between branches without needing superuser privileges.
  # (If your app uses pgvector, set POSTGRES_IMAGE=pgvector/pgvector:pg16 in compose.env
  #  and add: CREATE EXTENSION IF NOT EXISTS vector SCHEMA extensions;)
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db_name" <<-EOSQL
    CREATE SCHEMA IF NOT EXISTS extensions;
    GRANT USAGE ON SCHEMA extensions TO ${role_name};
    CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA extensions;
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA extensions;
    ALTER SCHEMA public OWNER TO ${role_name};
    REVOKE CREATE ON SCHEMA public FROM PUBLIC;
    GRANT ALL ON SCHEMA public TO ${role_name};
EOSQL
}

create_isolated_db "worker_gemini" "app_gemini" "${POSTGRES_GEMINI_PASSWORD:?POSTGRES_GEMINI_PASSWORD required}"
create_isolated_db "worker_qwen"   "app_qwen"   "${POSTGRES_QWEN_PASSWORD:?POSTGRES_QWEN_PASSWORD required}"
create_isolated_db "worker_fable"  "app_fable"  "${POSTGRES_FABLE_PASSWORD:?POSTGRES_FABLE_PASSWORD required}"

# Lock down default postgres database from non-superuser workers as well
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  REVOKE ALL ON DATABASE ${POSTGRES_DB} FROM PUBLIC;
EOSQL

echo "[factory-postgres] All 3 isolated worker databases ready (extensions isolated cleanly)."
```
*(ORM Note: If the repository uses **Prisma `migrate dev`**, which requires a shadow database, either use `prisma migrate deploy` + `prisma db push` in workers or grant `CREATEDB` in the `CREATE ROLE` line above.)*

### 3.3 Create Shared Container Workspace Bootstrapper (`.factory/docker/bootstrap-workspace.sh`)
Create `.factory/docker/bootstrap-workspace.sh` (`chmod +x .factory/docker/bootstrap-workspace.sh`).

```bash
#!/usr/bin/env bash
set -euo pipefail

ROLE="${FACTORY_ROLE:?FACTORY_ROLE is required}"
REPO_FULL="${FACTORY_REPO:?FACTORY_REPO is required (owner/repo)}"
AUTH_ROOT="${FACTORY_AUTH_ROOT:-/run/factory-auth}"
TOKEN_FILE="${AUTH_ROOT}/${ROLE}/token"

echo "[bootstrap] Waiting for 1h token at ${TOKEN_FILE}..."
for _ in $(seq 1 60); do
  [ -s "$TOKEN_FILE" ] && break
  sleep 1
done

if [ ! -s "$TOKEN_FILE" ]; then
  echo "[bootstrap] ERROR: Timed out waiting for ${TOKEN_FILE}" >&2
  exit 1
fi

if [ ! -d /workspace/.git ]; then
  echo "[bootstrap] Cloning ${REPO_FULL} (staging) into isolated /workspace..."
  TOKEN="$(cat "$TOKEN_FILE")"
  git clone --branch staging "https://x-access-token:${TOKEN}@github.com/${REPO_FULL}.git" /workspace
  git -C /workspace remote set-url origin "https://github.com/${REPO_FULL}.git"
fi

grep -Fq "enter-role.sh" "$HOME/.bashrc" 2>/dev/null || cat <<'EOF' >> "$HOME/.bashrc"
[ -f "$HOME/.worker-env.sh" ] && source "$HOME/.worker-env.sh"
if [ -f /workspace/.factory/enter-role.sh ]; then
  source /workspace/.factory/enter-role.sh "${FACTORY_ROLE}"
fi
cd /workspace 2>/dev/null || true
EOF

echo "[bootstrap] /workspace ready for role=${ROLE}."
```

### 3.4 Create `herdr-hub` Image & Auto-Configured Hermes Entrypoint
Create `.factory/docker/Dockerfile.hub` *(Bootstrap Agent: confirm the exact `hermes` CLI install line with the human before Phase 10 build)*:

```dockerfile
FROM node:22-bookworm-slim

ARG FACTORY_UID=1000
ARG FACTORY_GID=1000

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git jq openssh-client python3 python3-pip python3-venv gnupg \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
     | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
     > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

RUN userdel -r node 2>/dev/null || true \
  && groupadd -f -g "${FACTORY_GID}" factory \
  && useradd -m -u "${FACTORY_UID}" -g "${FACTORY_GID}" -s /bin/bash factory \
  && mkdir -p /workspace /home/factory/.ssh /home/factory/.hermes /home/factory/.config/herdr \
  && chown -R factory:factory /workspace /home/factory

COPY .factory/docker/bootstrap-workspace.sh /usr/local/bin/bootstrap-workspace.sh
COPY .factory/docker/entrypoint-hub.sh /usr/local/bin/entrypoint-hub.sh
RUN chmod +x /usr/local/bin/bootstrap-workspace.sh /usr/local/bin/entrypoint-hub.sh

USER factory
ENV HOME=/home/factory
ENV PATH="/home/factory/.local/bin:${PATH}"

RUN curl -fsSL https://herdr.dev/install.sh | sh \
  && herdr integration install hermes || true
# NOTE (Bootstrap Agent): Insert the human's exact Hermes CLI install command here before Phase 10 build

WORKDIR /workspace
EXPOSE 8787
ENTRYPOINT ["/usr/local/bin/entrypoint-hub.sh"]
```

Create `.factory/docker/entrypoint-hub.sh` (`chmod +x .factory/docker/entrypoint-hub.sh`).
Auto-writes `~/.hermes/profiles/architect/config.yaml` and `.env` using ONLY the dummy proxy key (`proxy-architect-only`) and `http://llm-proxy:4000`, syncs `/workspace` to `origin/staging`, installs `herdr --skill` + Architect skills, and runs the persistent headless **`herdr server`** as the container's main process so Herdr workspaces and tabs survive client detaches cleanly.

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Configure internal SSH client for reaching the 3 worker containers (port 2222)
mkdir -p "$HOME/.ssh" "$HOME/.config/herdr/bridge-state"
chmod 700 "$HOME/.ssh"
cat <<'EOF' > "$HOME/.ssh/config"
Host worker-gemini worker-qwen specialist-fable
  User factory
  Port 2222
  IdentityFile /run/factory-ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  ServerAliveInterval 30
  ServerAliveCountMax 3
EOF
chmod 600 "$HOME/.ssh/config"

# 2. Auto-sync Hermes Architect profile from compose.env (ZERO real API keys in container)
ARCH_MODEL="${ARCHITECT_MODEL:-glm-5.3}"
VIS_MODEL="${ARCHITECT_VISION_MODEL:-glm-5.3-flash}"
PROXY_TOK="${ARCHITECT_PROXY_TOKEN:-proxy-architect-only}"

mkdir -p "$HOME/.hermes/profiles/architect"
cat <<EOF > "$HOME/.hermes/profiles/architect/config.yaml"
# Auto-generated on boot from ~/.config/light-factory/compose.env
# Real API keys live ONLY inside the llm-proxy container (never accessible to Architect AI)
model:
  default: "${ARCH_MODEL}"
  provider: "custom"
  base_url: "http://llm-proxy:4000/glm"
auxiliary:
  vision:
    provider: "custom"
    model: "${VIS_MODEL}"
    base_url: "http://llm-proxy:4000/vision"
EOF

cat <<EOF > "$HOME/.hermes/profiles/architect/.env"
OPENAI_API_KEY=${PROXY_TOK}
EOF
cp "$HOME/.hermes/profiles/architect/.env" "$HOME/.hermes/.env"
chmod 600 "$HOME/.hermes/.env" "$HOME/.hermes/profiles/architect/.env"

# 3. Bootstrap isolated /workspace repo clone, pull latest staging, & sync Architect + Herdr skills
/usr/local/bin/bootstrap-workspace.sh
if [ -f /workspace/.factory/enter-role.sh ]; then
  # shellcheck disable=SC1091
  source /workspace/.factory/enter-role.sh architect
  [ -x /workspace/.factory/sync-hub.sh ] && /workspace/.factory/sync-hub.sh || true
fi
if [ -x /workspace/.factory/sync-skills.sh ]; then
  /workspace/.factory/sync-skills.sh architect
fi

echo "[herdr-hub] Starting headless Herdr server (Architect=${ARCH_MODEL}, Vision=${VIS_MODEL}, via llm-proxy — zero raw keys, execution-free)..."
exec herdr server
```

### 3.5 Create Worker Sandbox Image & Auto-Configured Entrypoint
Create `.factory/docker/Dockerfile.worker` (includes `postgresql-client` AND **Playwright Chromium OS dependencies** preinstalled as root so non-root `worker-gemini` and `worker-qwen` can run local Playwright Final-Wave E2E tests without root privileges; non-web repos without Playwright may comment out the `playwright install-deps` line to keep the image smaller):

```dockerfile
FROM node:22-bookworm

ARG FACTORY_UID=1000
ARG FACTORY_GID=1000

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git jq openssh-server postgresql-client python3 python3-pip python3-venv gnupg \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
     | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
     > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && npm install -g @anthropic-ai/claude-code \
  && npx --yes playwright install-deps chromium \
  && rm -rf /var/lib/apt/lists/*

RUN userdel -r node 2>/dev/null || true \
  && groupadd -f -g "${FACTORY_GID}" factory \
  && useradd -m -u "${FACTORY_UID}" -g "${FACTORY_GID}" -s /bin/bash factory \
  && mkdir -p /workspace /home/factory/.ssh /home/factory/.hermes /home/factory/.config /home/factory/.claude /home/factory/.gemini/antigravity/skills /home/factory/.cache/ms-playwright \
  && chown -R factory:factory /workspace /home/factory

COPY .factory/docker/bootstrap-workspace.sh /usr/local/bin/bootstrap-workspace.sh
COPY .factory/docker/entrypoint-worker.sh /usr/local/bin/entrypoint-worker.sh
RUN chmod +x /usr/local/bin/bootstrap-workspace.sh /usr/local/bin/entrypoint-worker.sh

USER factory
ENV HOME=/home/factory
ENV PATH="/home/factory/.local/bin:${PATH}"
ENV PLAYWRIGHT_BROWSERS_PATH=/home/factory/.cache/ms-playwright

# Pre-download Chromium browser binary as non-root factory user for local Final-Wave E2E runs
# (Non-web repos may remove this line along with install-deps above)
RUN npx --yes playwright install chromium || true

# NOTE (Bootstrap Agent): Confirm and insert the exact install commands before Phase 10 build:
# - Antigravity CLI (`agy`) for worker-gemini
# - Hermes CLI (`hermes`) for worker-qwen

WORKDIR /workspace
EXPOSE 2222
ENTRYPOINT ["/usr/local/bin/entrypoint-worker.sh"]
```

Create `.factory/docker/entrypoint-worker.sh` (`chmod +x .factory/docker/entrypoint-worker.sh`).
Persists `DATABASE_URL` and worker identity into `~/.worker-env.sh` (so internal SSH sessions from `herdr-hub` always inherit `DATABASE_URL`), syncs role-scoped progressive-disclosure skills, and configures Hermes/Claude Code.

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Persist worker runtime env (including isolated DATABASE_URL) for internal SSH sessions
cat <<EOF > "$HOME/.worker-env.sh"
export WORKER_NAME="${WORKER_NAME:-worker}"
export FACTORY_ROLE="${FACTORY_ROLE:-worker}"
export FACTORY_AUTH_ROOT="${FACTORY_AUTH_ROOT:-/run/factory-auth}"
export FACTORY_REPO="${FACTORY_REPO:-}"
export DATABASE_URL="${DATABASE_URL:-}"
export PLAYWRIGHT_BROWSERS_PATH="/home/factory/.cache/ms-playwright"
EOF
chmod 600 "$HOME/.worker-env.sh"

/usr/local/bin/bootstrap-workspace.sh

# 2. Sync progressive-disclosure skills for this worker role
if [ -x /workspace/.factory/sync-skills.sh ] && [ -n "${WORKER_NAME:-}" ]; then
  /workspace/.factory/sync-skills.sh "$WORKER_NAME"
fi

# 3. Auto-configure local GPU inference server & model for worker-qwen
if [ "${WORKER_NAME:-}" = "worker-qwen" ]; then
  QWEN_URL="${QWEN_INFERENCE_URL:-http://host.docker.internal:11434/v1}"
  QWEN_MOD="${QWEN_MODEL:-qwen3.8:27b}"
  QWEN_KEY="${QWEN_API_KEY:-local-not-needed}"

  mkdir -p "$HOME/.hermes/profiles/qwen"
  cat <<EOF > "$HOME/.hermes/profiles/qwen/config.yaml"
# Auto-generated on boot from ~/.config/light-factory/compose.env
model:
  default: "${QWEN_MOD}"
  provider: "custom"
  base_url: "${QWEN_URL}"
EOF
  cat <<EOF > "$HOME/.hermes/profiles/qwen/.env"
OPENAI_API_KEY=${QWEN_KEY}
EOF
  cp "$HOME/.hermes/profiles/qwen/.env" "$HOME/.hermes/.env"
  chmod 600 "$HOME/.hermes/.env" "$HOME/.hermes/profiles/qwen/.env"
  echo "[worker-qwen] Configured Hermes -> ${QWEN_MOD} @ ${QWEN_URL}"
fi

# 4. Configure Claude Code auth mode for specialist-fable (OAuth default OR zero-key llm-proxy)
if [ "${WORKER_NAME:-}" = "specialist-fable" ]; then
  if [ "${FABLE_AUTH_MODE:-oauth}" = "proxy" ]; then
    cat <<EOF >> "$HOME/.worker-env.sh"
export ANTHROPIC_BASE_URL="http://llm-proxy:4000/anthropic"
export ANTHROPIC_API_KEY="${FABLE_PROXY_TOKEN:-proxy-fable-only}"
EOF
    echo "[specialist-fable] Claude Code configured in ZERO-KEY PROXY mode via llm-proxy."
  else
    cat <<'EOF' >> "$HOME/.worker-env.sh"
unset ANTHROPIC_BASE_URL
unset ANTHROPIC_API_KEY
EOF
    echo "[specialist-fable] Claude Code configured in native OAuth mode (~/.claude volume)."
  fi
fi

# 5. Generate container-local non-root SSH host key inside /tmp
HOST_KEY="/tmp/ssh_host_ed25519_key"
[ -f "$HOST_KEY" ] || ssh-keygen -t ed25519 -N "" -f "$HOST_KEY" >/dev/null

cat <<EOF > /tmp/sshd_config
Port 2222
ListenAddress 0.0.0.0
HostKey ${HOST_KEY}
PidFile /tmp/sshd.pid
AuthorizedKeysFile /run/factory-ssh/authorized_keys
StrictModes no
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers factory
AllowTcpForwarding no
X11Forwarding no
PrintMotd no
Subsystem sftp internal-sftp
EOF

echo "[worker:${WORKER_NAME:-worker}] Starting non-root sshd on internal port 2222 (DB isolated)..."
exec /usr/sbin/sshd -D -e -f /tmp/sshd_config
```

### 3.6 Create Master Compose Stack (`docker-compose.yml` -> `herdr-software-factory`)
Create `docker-compose.yml` in `<repo-root>`.
Notice the **three-network isolation**:
- `llm-net`: connects ONLY `llm-proxy`, `herdr-hub`, and `specialist-fable` (`worker-gemini` and `worker-qwen` cannot reach `llm-proxy`).
- `db-net` (`internal: true`): connects ONLY `factory-postgres` and the 3 execution workers (`herdr-hub` stays execution-free and cannot reach Postgres).

```yaml
name: herdr-software-factory

x-security-hardening: &security-hardening
  cap_drop:
    - ALL
  security_opt:
    - no-new-privileges:true
  restart: unless-stopped

services:
  # 1. Isolated GitHub Token Minter — ONLY container allowed to see host .pem keys
  auth-minter:
    image: node:22-bookworm-slim
    container_name: herdr-factory-auth-minter
    <<: *security-hardening
    networks:
      - factory-net
    user: "${FACTORY_UID:-1000}:${FACTORY_GID:-1000}"
    command: ["node", "/opt/factory/token-refresher.mjs"]
    environment:
      FACTORY_APPS_ENV: /run/factory-config/apps.env
      FACTORY_AUTH_ROOT: /run/factory-auth
    volumes:
      - ./.factory/token-refresher.mjs:/opt/factory/token-refresher.mjs:ro
      - ${HOME}/.config/light-factory/apps.env:/run/factory-config/apps.env:ro
      - ${HOME}/.config/light-factory/keys:/run/factory-keys:ro
      - auth-architect:/run/factory-auth/architect
      - auth-worker:/run/factory-auth/worker
    healthcheck:
      test: ["CMD-SHELL", "test -s /run/factory-auth/architect/token && test -s /run/factory-auth/worker/token"]
      interval: 5s
      timeout: 3s
      retries: 12

  # 2. Isolated Zero-Key LLM Proxy — ONLY container allowed to see host llm-secrets.env
  llm-proxy:
    image: node:22-bookworm-slim
    container_name: herdr-factory-llm-proxy
    <<: *security-hardening
    networks:
      - llm-net
    extra_hosts:
      - "host.docker.internal:host-gateway"
    user: "${FACTORY_UID:-1000}:${FACTORY_GID:-1000}"
    command: ["node", "/opt/factory/llm-proxy.mjs"]
    environment:
      LLM_SECRETS_FILE: /run/factory-config/llm-secrets.env
      LLM_PROXY_PORT: "4000"
      ARCHITECT_MODEL: ${ARCHITECT_MODEL:-glm-5.3}
      ARCHITECT_VISION_MODEL: ${ARCHITECT_VISION_MODEL:-glm-5.3-flash}
      EXTRA_ALLOWED_MODELS: ${EXTRA_ALLOWED_MODELS:-}
      ARCHITECT_PROXY_TOKEN: ${ARCHITECT_PROXY_TOKEN:-proxy-architect-only}
      FABLE_PROXY_TOKEN: ${FABLE_PROXY_TOKEN:-proxy-fable-only}
    volumes:
      - ./.factory/llm-proxy.mjs:/opt/factory/llm-proxy.mjs:ro
      - ${HOME}/.config/light-factory/llm-secrets.env:/run/factory-config/llm-secrets.env:ro
    healthcheck:
      test: ["CMD-SHELL", "node -e 'fetch(\"http://127.0.0.1:4000/health\").then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))'"]
      interval: 5s
      timeout: 3s
      retries: 10

  # 3. Isolated Multi-Worker Postgres — 3 locked-down DBs strictly on internal db-net
  #    herdr-hub is NOT attached to db-net (keeps Architect hub execution-free)
  factory-postgres:
    image: ${POSTGRES_IMAGE:-postgres:16-alpine}
    container_name: herdr-factory-postgres
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - DAC_OVERRIDE
      - FOWNER
      - SETGID
      - SETUID
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped
    networks:
      - db-net
    environment:
      POSTGRES_USER: postgres
      POSTGRES_DB: postgres
      POSTGRES_PASSWORD: ${POSTGRES_ADMIN_PASSWORD}
      POSTGRES_GEMINI_PASSWORD: ${POSTGRES_GEMINI_PASSWORD}
      POSTGRES_QWEN_PASSWORD: ${POSTGRES_QWEN_PASSWORD}
      POSTGRES_FABLE_PASSWORD: ${POSTGRES_FABLE_PASSWORD}
    volumes:
      - ./.factory/postgres/init-dbs.sh:/docker-entrypoint-initdb.d/01-init-dbs.sh:ro
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d postgres"]
      interval: 5s
      timeout: 3s
      retries: 12
    mem_limit: 2g
    cpus: "2.0"

  # 4. Herdr Control Hub (Herdr Server + Webhook Bridge + Permanent GLM-5.3 Architect)
  #    Blind to host $HOME, .pem keys, REAL API keys, docker.sock, factory-postgres, & Fable auth
  herdr-hub:
    build:
      context: .
      dockerfile: .factory/docker/Dockerfile.hub
      args:
        FACTORY_UID: ${FACTORY_UID:-1000}
        FACTORY_GID: ${FACTORY_GID:-1000}
    container_name: herdr-factory-hub
    <<: *security-hardening
    networks:
      - factory-net
      - llm-net
    depends_on:
      auth-minter:
        condition: service_healthy
      llm-proxy:
        condition: service_healthy
    environment:
      FACTORY_ROLE: architect
      FACTORY_AUTH_ROOT: /run/factory-auth
      FACTORY_REPO: ${FACTORY_REPO}
      BRIDGE_ENV_FILE: /run/factory-config/bridge.env
      ARCHITECT_MODEL: ${ARCHITECT_MODEL:-glm-5.3}
      ARCHITECT_VISION_MODEL: ${ARCHITECT_VISION_MODEL:-glm-5.3-flash}
      ARCHITECT_PROXY_TOKEN: ${ARCHITECT_PROXY_TOKEN:-proxy-architect-only}
      FABLE_MODEL: ${FABLE_MODEL:-}
      # Optional fallback if restricted Linux container blocks foreground-group detection:
      # HERDR_PROCESS_DETECTION: child-groups
    ports:
      - "127.0.0.1:${WEBHOOK_PORT:-8787}:8787"
    volumes:
      - auth-architect:/run/factory-auth/architect:ro
      - ${HOME}/.config/light-factory/bridge.env:/run/factory-config/bridge.env:ro
      - ${HOME}/.config/light-factory/internal-ssh/id_ed25519:/run/factory-ssh/id_ed25519:ro
      - hub-workspace:/workspace
      - hub-hermes:/home/factory/.hermes
      - hub-herdr:/home/factory/.config/herdr

  # 5. Primary Coding & E2E Worker — Antigravity CLI (Gemini 3.8 Flash) + app_gemini DB
  worker-gemini:
    build:
      context: .
      dockerfile: .factory/docker/Dockerfile.worker
      args:
        FACTORY_UID: ${FACTORY_UID:-1000}
        FACTORY_GID: ${FACTORY_GID:-1000}
    container_name: herdr-factory-worker-gemini
    <<: *security-hardening
    networks:
      - factory-net
      - db-net
    depends_on:
      auth-minter:
        condition: service_healthy
      factory-postgres:
        condition: service_healthy
    environment:
      WORKER_NAME: worker-gemini
      FACTORY_ROLE: worker
      FACTORY_AUTH_ROOT: /run/factory-auth
      FACTORY_REPO: ${FACTORY_REPO}
      DATABASE_URL: "postgres://worker_gemini:${POSTGRES_GEMINI_PASSWORD}@factory-postgres:5432/app_gemini"
    volumes:
      - auth-worker:/run/factory-auth/worker:ro
      - ${HOME}/.config/light-factory/internal-ssh/authorized_keys:/run/factory-ssh/authorized_keys:ro
      - gemini-workspace:/workspace
      - gemini-auth:/home/factory/.config
      - gemini-dotgemini:/home/factory/.gemini
    mem_limit: 8g
    cpus: "4.0"

  # 6. Parallel & Overflow Worker — Local Qwen 3.8 27B (Hermes -> GPU host) + app_qwen DB
  worker-qwen:
    build:
      context: .
      dockerfile: .factory/docker/Dockerfile.worker
      args:
        FACTORY_UID: ${FACTORY_UID:-1000}
        FACTORY_GID: ${FACTORY_GID:-1000}
    container_name: herdr-factory-worker-qwen
    <<: *security-hardening
    networks:
      - factory-net
      - db-net
    depends_on:
      auth-minter:
        condition: service_healthy
      factory-postgres:
        condition: service_healthy
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      WORKER_NAME: worker-qwen
      FACTORY_ROLE: worker
      FACTORY_AUTH_ROOT: /run/factory-auth
      FACTORY_REPO: ${FACTORY_REPO}
      DATABASE_URL: "postgres://worker_qwen:${POSTGRES_QWEN_PASSWORD}@factory-postgres:5432/app_qwen"
      QWEN_INFERENCE_URL: ${QWEN_INFERENCE_URL:-http://host.docker.internal:11434/v1}
      QWEN_MODEL: ${QWEN_MODEL:-qwen3.8:27b}
      QWEN_API_KEY: ${QWEN_API_KEY:-local-not-needed}
    volumes:
      - auth-worker:/run/factory-auth/worker:ro
      - ${HOME}/.config/light-factory/internal-ssh/authorized_keys:/run/factory-ssh/authorized_keys:ro
      - qwen-workspace:/workspace
      - qwen-hermes:/home/factory/.hermes
    mem_limit: 8g
    cpus: "4.0"

  # 7. On-Demand Escalation Specialist — Claude Code (`claude`) (IDLE 95%) + app_fable DB
  specialist-fable:
    build:
      context: .
      dockerfile: .factory/docker/Dockerfile.worker
      args:
        FACTORY_UID: ${FACTORY_UID:-1000}
        FACTORY_GID: ${FACTORY_GID:-1000}
    container_name: herdr-factory-specialist-fable
    <<: *security-hardening
    networks:
      - factory-net
      - llm-net
      - db-net
    depends_on:
      auth-minter:
        condition: service_healthy
      llm-proxy:
        condition: service_healthy
      factory-postgres:
        condition: service_healthy
    environment:
      WORKER_NAME: specialist-fable
      FACTORY_ROLE: worker
      FACTORY_AUTH_ROOT: /run/factory-auth
      FACTORY_REPO: ${FACTORY_REPO}
      DATABASE_URL: "postgres://worker_fable:${POSTGRES_FABLE_PASSWORD}@factory-postgres:5432/app_fable"
      FABLE_MODEL: ${FABLE_MODEL:-}
      FABLE_AUTH_MODE: ${FABLE_AUTH_MODE:-oauth}
      FABLE_PROXY_TOKEN: ${FABLE_PROXY_TOKEN:-proxy-fable-only}
    volumes:
      - auth-worker:/run/factory-auth/worker:ro
      - ${HOME}/.config/light-factory/internal-ssh/authorized_keys:/run/factory-ssh/authorized_keys:ro
      - fable-workspace:/workspace
      - fable-auth:/home/factory/.claude
    mem_limit: 6g
    cpus: "2.0"

networks:
  factory-net:
    driver: bridge
  llm-net:
    driver: bridge
  db-net:
    driver: bridge
    internal: true

volumes:
  auth-architect:
  auth-worker:
  postgres-data:
  hub-workspace:
  hub-hermes:
  hub-herdr:
  gemini-workspace:
  gemini-auth:
  gemini-dotgemini:
  qwen-workspace:
  qwen-hermes:
  fable-workspace:
  fable-auth:
```

**Phase 3 Verification:** `docker compose --env-file ~/.config/light-factory/compose.env config -q` exits `0` (verified via `.factory/preflight.sh` in Phase 8.4 once `compose.env` is created), confirming valid Compose v2 syntax for all 7 containers, and `.factory/{sync-skills,sync-hub,fetch-evidence,prep-branch}.sh` are executable.

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
gh label create "blocked"         --color "D93F0B" --description "CI retry cap exceeded or agent needs human input" --force
gh label create "fable-escalated" --color "B60205" --description "Escalated once to specialist-fable (hard 1-pass token budget cap)" --force
```

### 4.3 Create `.github/CODEOWNERS` (Locks `master` to Human Approval)
Bootstrap Agent: populate `<YOUR_GITHUB_USERNAME>` automatically via `GH_OWNER_LOGIN=$(gh api user -q .login)`:

```text
# Only the human repository owner can satisfy Code Owner review on master
* @<YOUR_GITHUB_USERNAME>
```

### 4.4 Create Feature Request Issue Form (`.github/ISSUE_TEMPLATE/feature-request.yml`)
```yaml
name: Feature Request
description: Propose a new feature or rough idea (apply `plan` so the Architect breaks it into Sub-Issues before coding)
title: "[FEATURE] "
labels: []
body:
  - type: textarea
    id: problem
    attributes:
      label: Problem / Goal
      description: What user problem does this solve or what capability are we adding? Rough ideas are totally fine — apply the `plan` label to have the Architect spec out exact Sub-Issues first.
    validations:
      required: true
  - type: textarea
    id: behavior
    attributes:
      label: Desired Behavior & Acceptance Criteria
      description: Bullet list of what "done" looks like (even if high-level).
      placeholder: |
        - [ ] User can...
        - [ ] Edge case handled...
    validations:
      required: true
  - type: dropdown
    id: review_gate
    attributes:
      label: Extra Human Gate? (Optional)
      description: Protected paths (`migrations/`, `*.sql`, `auth/`, `.github/`, `.factory/`, `docker-compose*.yml`, `AGENTS.md`) are ALWAYS auto-gated by `human-gate-guard` and moved to `Awaiting Approval`. Select `human-gate` only if you also want manual approval on normal files.
      options:
        - Default (Routine files flow to staging; protected paths auto-gated)
        - Manual Override (Add `human-gate` label for my explicit approval before staging merge)
    validations:
      required: false
  - type: textarea
    id: notes
    attributes:
      label: Out of Scope / Extra Notes
      description: Anything the agents should explicitly avoid touching.
```

### 4.5 Create Atomic Task / Sub-Issue Spec Template (`.github/ISSUE_TEMPLATE/feature-spec.md`)
```markdown
---
name: Factory Task / Sub-Issue Spec
about: Atomic single-PR task (1 unique Sub-Issue = 1 Worker = 1 PR)
title: "[TASK] "
labels: []
---

## Objective
<!-- 1–2 sentences describing the exact slice to build, fix, or verify end-to-end -->

## Parent Epic & Wave
- **Parent Epic:** *(None if standalone, or `#<epic_num>`)*
- **Execution Wave:** `Wave 1 (Foundations)` / `Wave 2 (Parallel Build)` / `Final Wave (E2E Verification)`
- **Depends On:** *(None, or `#<sub_issue_num>` merged to `staging`)*

## Target Module / Files
- `path/to/module`

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Test Plan (Architect-Authored — Mandatory)
- **Happy Path:** <!-- Concrete scenario(s) & expected UI/API/Postgres outcome -->
- **Edge / Error Cases:** <!-- Invalid input, empty state, permission/constraint edge case -->
- **Verification Layer:** `Unit + API/DB Integration` *(build slices)* OR `Full-Journey Playwright E2E (real app + Postgres, zero API mocking)` *(Final Wave)*

## Routing & Guardrail Hints
- **Human Gate:** *(Auto-locked by `human-gate-guard` & moved to `Awaiting Approval` if touching `migrations/`, `*.sql`, `auth/`, `.github/`, `.factory/`, `docker-compose*.yml`, or `AGENTS.md`. Add `human-gate` label only if manual override is needed on other paths.)*
- **Suggested Worker:** `worker-gemini` (heavy/multi-file/backend/DB/integration, OR **Primary E2E Writer in fresh session**) OR `worker-qwen` (UI/unit/local, narrow 1–2 screen cross-model E2E in fresh session, or Antigravity quota overflow)
- **Session Mode:** `Standard` *(build slice)* OR `FRESH / STATELESS SESSION REQUIRED` *(Final-Wave E2E — reset chat context before starting)*
- **Relevant Skills:** `.agents/skills/modern-web-standards` / `.agents/skills/postgres-migrations` / `.agents/skills/e2e-testing`
- **Out of Scope:** <!-- Explicitly state what NOT to touch (especially files assigned to sibling Sub-Issues in the same wave) -->
```

### 4.6 Create PR Template (`.github/PULL_REQUEST_TEMPLATE.md`)
```markdown
## Linked Issue
Closes #

## Summary of Changes
-

## Worker Metadata
- **Built / Verified / Rescued By:** `**[Gemini]**` / `**[Qwen]**` / `**[Fable]**`
- **Local Verification (Inside Worker Container):**
  - [ ] Merged latest `origin/staging` + reset clean DB via `.factory/prep-branch.sh`
  - [ ] Every bullet in the Issue's `Test Plan` is covered (no `.skip`, `.only`, or weakened assertions)
  - [ ] Migrations & tests passed against isolated `$DATABASE_URL`
  - [ ] Lint & typecheck passed

## Evidence (Auto-populated by CI or Worker)
- Preview URL / Screenshots: *(See automated CI Evidence comment below)*
```

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

# 2. Gate master (Human Owner Only) — Neither Architect nor Workers/Fable can merge or push
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

# 3. Gate staging (Architect Review & Merge; Workers & Fable Hard-Blocked)
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

**Phase 4 Verification:** `gh api "/repos/${REPO_FULL}/rulesets" --jq '.[].name'` lists all 3 active rulesets (with Ruleset #1 requiring both `ci-and-evidence` and `human-gate-guard`), `.github/CODEOWNERS` contains the real GitHub username, and `gh label list` shows the 6 active labels (`plan`, `ready`, `in-progress`, `human-gate`, `blocked`, `fable-escalated`).

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
  --single-select-options "Architect,Gemini,Qwen,Fable"

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

**Phase 5 Verification:** `gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER"` lists `Status` (**7 columns**, including `Awaiting Approval`), `Priority`, and `Worker` (`Architect`, `Gemini`, `Qwen`, `Fable`), and `.factory/{board-sync,sub-issue,release-pr}.sh` are executable.

---

## Phase 6: Governance, Closed-Loop Memory & Progressive-Disclosure Skills

### 6.1 Create `AGENTS.md` in Repo Root
Keep `AGENTS.md` concise (<200 lines) so it fits cleanly inside Qwen's 54k context budget.

```markdown
# AGENTS.md — `herdr-software-factory` Operating Manual

## 1. Bot Identities & Signatures (MANDATORY)
Every container runs inside the sandboxed `herdr-software-factory` Docker stack with its own isolated `/workspace` clone, a 1-hour auto-rotating GitHub App token (`source /workspace/.factory/enter-role.sh <architect|worker>`), and zero access to raw upstream LLM API keys (proxied via `llm-proxy`).
Prefix every GitHub comment with your signature tag:
- Architect (`herdr-hub` / Hermes GLM-5.3 + Flash Vision / `factory-architect[bot]`): `**[Architect]**`
- Gemini Worker (`worker-gemini` / Antigravity Gemini 3.8 Flash / `factory-worker[bot]`): `**[Gemini]**`
- Qwen Worker (`worker-qwen` / Hermes Local Qwen 3.8 27B / `factory-worker[bot]`): `**[Qwen]**`
- Fable Specialist (`specialist-fable` / Claude Code `claude` / `factory-worker[bot]`): `**[Fable]**`

## 2. Branching, Database & Sandbox Boundaries (Hard-Enforced)
- Branches: `feature/issue-<N>-<slug>` -> `staging` -> `master`.
- Each worker container has its own isolated `/workspace` clone AND its own locked-down Postgres DB via `$DATABASE_URL` (`app_gemini`, `app_qwen`, `app_fable`). Never hardcode DB credentials or attempt to connect outside `$DATABASE_URL`.
- **`herdr-hub` (Architect) is execution-free:** It has no Postgres access and does not run app code or builds. Always run `/workspace/.factory/sync-hub.sh` before planning or committing learned rules so `/workspace` stays synced with `origin/staging`.
- Workers and Fable are server-side blocked from pushing to `staging`/`master` and cannot approve or merge PRs.
- Always run `.factory/prep-branch.sh <issue_num_or_branch> [slug]` inside `/workspace` before starting work (resets Git, wipes isolated Postgres `public` schema, syncs dependencies & skills). On exit code `2` (`MERGE_CONFLICT`), standard workers must run `git merge --abort` and escalate to the Architect for Fable.

## 3. Progressive-Disclosure Skills (Load On-Demand Only)
Domain skills live in `.agents/skills/<skill>/SKILL.md` (auto-linked into all agents) and role playbooks live in `.factory/role-skills/` (linked strictly to Architect or Fable, plus `herdr --skill` for Architect).
- **Do not load unrelated skills** (preserves Qwen's 54k context budget). Read a skill's `SKILL.md` **before writing code** only when your task touches that domain:
  - UI, HTML, CSS, accessibility, or frontend performance -> `.agents/skills/modern-web-standards/SKILL.md`
  - SQL, ORM schemas, migrations, or Postgres queries -> `.agents/skills/postgres-migrations/SKILL.md`
  - Full-journey Playwright E2E tests (Final Wave) -> `.agents/skills/e2e-testing/SKILL.md`
- Architect may add new shared skills under `.agents/skills/<name>/SKILL.md` on `staging`; containers pick them up automatically on next `.factory/prep-branch.sh` / `.factory/sync-hub.sh`.

## 4. Plan-First Epic Decomposition (`plan`), Test Plans & Final-Wave E2E (Architect Only)
**Golden Rule:** **1 unique Sub-Issue = 1 IDLE Worker Container = 1 PR (`Closes #<sub_issue>`).** Never forward a vague or multi-part feature straight to a worker, never bundle unrelated Sub-Issues onto one branch, and **always verify worker availability via BOTH `herdr agent list` (confirming `idle`/`done`, not `working`/`blocked`) AND `gh issue list --label in-progress --state open`** before dispatching so no busy or blocked worker is ever double-assigned.
- **When an Issue is labeled `plan`:**
  1. Run `/workspace/.factory/sync-hub.sh`, inspect the up-to-date codebase (`/workspace`), and read the Issue (`gh issue view <N>`).
  2. Break the goal into small, unambiguous, single-PR child Issues containing: exact target files, DB migration needs, Acceptance Criteria, an explicit **Architect-Authored Test Plan** (happy path + edge cases), relevant `.agents/skills/`, optional `human-gate` only if extra sign-off is needed outside auto-protected paths, and explicit Wave order with non-overlapping file scopes for parallel waves.
  3. **Final-Wave E2E Rule:** Whenever an Epic spans multiple layers (e.g., DB + API + UI) or adds a user-facing workflow, append a **Final Wave: End-to-End Verification** Sub-Issue that executes *after* all build waves merge to `staging`. Specify the exact end-to-end user journey and Postgres/UI persistence assertions in its `Test Plan`.
  4. Create each child Issue in `Backlog` (NO `ready` label yet) and attach them natively via `.factory/sub-issue.sh link <parent_num> <child_num>`.
  5. Remove `plan` (`gh issue edit <parent_num> --remove-label plan`), post a concise `**[Architect]**` Wave Blueprint + any clarifying questions on the parent Issue, and **STOP**—do not dispatch any workers until the human approves (applies `ready` or replies "go").
- **When an Issue is labeled `ready`:**
  - **If it has native Sub-Issues (`sub_issues_summary.total > 0`):** Swap `ready` -> `in-progress`, set parent board Status to `In Progress`, check `herdr agent list` + `in-progress` occupancy, and dispatch **ONLY Wave 1 unblocked Sub-Issues** (1 unique Sub-Issue per idle worker container; hold dependent waves in `Backlog`).
  - **If it is a standalone Issue:** Triage scope first. If truly atomic & crystal clear (1 focused PR), verify an idle worker via `herdr agent list` and dispatch immediately. If vague or multi-part, **do NOT guess**—decompose it into native Sub-Issues, remove `ready`, and pause for a quick human sanity check.
- **Wave Advancement & Rolling Release PR (On Sub-Issue PR Merge to `staging`):**
  1. Check `.factory/sub-issue.sh parent <sub_issue_num>` and `.factory/sub-issue.sh summary <parent_num>`.
  2. If `completed === total`: post a completion summary, close the parent Issue (`gh issue close <parent_num>` -> auto-moves to `Done`), and run `/workspace/.factory/release-pr.sh <parent_num>` to open or update the single rolling `staging -> master` Release PR (auto-surfaced in `Awaiting Approval` with formal Review Request for the human owner).
  3. Otherwise: check `herdr agent list` for idle workers and dispatch the next unblocked wave across idle containers (`worker-gemini` and `worker-qwen` in parallel on distinct non-overlapping Sub-Issues).

## 5. Model Routing, Native Herdr Inspection & Stateless E2E Verification (Architect Only)
- **Native Herdr Multi-Agent Control:** All 3 remote workers are wrapped with `HERDR_AGENT=` so `herdr agent list` shows live `idle` / `working` / `blocked` / `done` status for `worker-gemini`, `worker-qwen`, and `specialist-fable`. Never prompt a `working` or `blocked` worker with a new task; if a worker shows `blocked`, inspect its screen via `herdr agent read <worker> --source visible --lines 40` before acting or alerting the human.
- **Build Waves (Unit & Slice Integration Tests Stay With the Builder in the Same PR):**
  - **`worker-gemini`** (Antigravity, Gemini 3.8 Flash): Multi-file features, backend/API/DB migrations, auth, state sync, integration tests, and heavy edit-test-retry loops.
  - **`worker-qwen`** (local GPU via `host.docker.internal`, 54k context): UI components, styling, isolated bug fixes, unit tests, single-file refactors—**and immediate overflow** if `worker-gemini` hits Antigravity's rolling 5-hour quota (keep dispatched context focused on specific files).
- **Final-Wave E2E Verification (ALWAYS Fresh / Stateless Session + `.agents/skills/e2e-testing/SKILL.md`):**
  - Instruct the assigned worker to **reset/clear chat context** before starting so it verifies the combined `staging` feature as an independent black-box verifier rather than rubber-stamping its own shortcuts.
  - **Primary E2E Writer -> `worker-gemini`:** Default for multi-page flows, auth/session handoffs, file uploads, complex async state, or Playwright trace debugging.
  - **Selective Narrow E2E -> `worker-qwen`:** Use ONLY for focused **1–2 screen** flows (e.g., form submit -> Postgres persist -> reload check) when `worker-gemini` built the feature (true cross-model check) or during Antigravity quota overflow.
  - **NEVER** assign routine E2E writing to `specialist-fable` or `herdr-hub`.
- **Stall & Broken-Staging Recovery:**
  - On `[GITHUB EVENT: STAGING BROKEN]` (post-merge CI failed on `staging`): pause merging new PRs, inspect `gh run view <run_id> --log-failed`, identify the regression commit(s), and dispatch a hotfix PR to an idle worker immediately.
  - On `[GITHUB EVENT: STALL WATCHDOG]`: inspect `herdr agent list` and `herdr agent read <worker> --source recent-unwrapped --lines 80` to see if the worker is `blocked`, crashed, or silently hit Antigravity's quota—recover/nudge, overflow to `worker-qwen`, or label `blocked` and alert the human.
- Keep the 7-column Kanban board accurate via `.factory/board-sync.sh <issue_num|pr:num> <Field> "<Value>"` (`Priority`, `Status`, `Worker`).
- **Context Hygiene:** Persist major plans to `DECISIONS.md` and compact/clear the Architect session between epics to maximize GLM-5.3 prompt caching.

## 6. On-Demand Fable Escalation Lane (Claude Code — STRICT TOKEN BUDGET GUARD)
`specialist-fable` runs **Claude Code (`claude`)** on borrowed tokens inside its own isolated container. **NEVER** dispatch routine features, UI tweaks, routine E2E tests, or first-pass bug fixes to Fable. Only wake `specialist-fable` for these 3 triggers—and enforce a **hard cap of 1 Fable pass per PR** (tracked via `fable-escalated`):
1. **Merge Conflicts (Primary):** PR reports `CONFLICTING` / `DIRTY` against `staging`, or worker hits `prep-branch.sh` exit `2`:
   - Confirm PR does NOT already have `fable-escalated`.
   - Add `fable-escalated`, set board `Worker` to `Fable`, and dispatch `specialist-fable` with PR `#`, branch name, and Issue `#`.
   - `specialist-fable` runs `.factory/prep-branch.sh <branch>`, resolves conflicts cleanly, passes migrations/lint/typecheck/tests against its `$DATABASE_URL`, pushes, and posts a concise `**[Fable]**` summary.
2. **Blocked PR 1-Shot Rescue (After 3 CI Retries):** Only if PR is labeled `blocked` AND lacks `fable-escalated` (including rescuing a deeply flaky E2E test after 3 failures). Request human confirmation or invoke ONE capped diagnosis/fix pass. Never loop Fable if CI fails again.
3. **High-Stakes `human-gate` Audit (Manual Only):** Only when explicitly requested by the human owner.

## 7. Default-Flow `staging`, `Awaiting Approval` Queue & Hard `human-gate-guard`
- For UI-facing and E2E PRs, first download Playwright evidence locally via `/workspace/.factory/fetch-evidence.sh <run_id> <pr_num>`, then inspect the local PNG paths with Hermes `auxiliary.vision` (routed through `llm-proxy/vision`). Apply `.factory/role-skills/architect/pr-evidence-review/SKILL.md` (including the strict anti-test-tampering check) before approving.
- **Default-Flow to `staging` (No extra label needed):** When **both** `ci-and-evidence` AND `human-gate-guard` are green and `mergeable` is `MERGEABLE`, Architect reviews the diff, test coverage, & visual evidence. If clean:
  1. Formally approve: `gh pr review <N> --approve --body "**[Architect]** LGTM — approving and merging to staging."`
  2. Squash-merge to `staging`: `gh pr merge <N> --squash --delete-branch`
- **Hard Server-Locked `human-gate-guard` (`Awaiting Approval` Column):** Any bot PR targeting `master`, touching protected paths (`migrations/`, `*.sql`, `auth/`, `.github/`, `.factory/`, `docker-compose*.yml`, `AGENTS.md`, `.env*`), **or** carrying the optional `human-gate` label is **physically blocked by GitHub Ruleset #1** (evaluated from trusted `master` directly onto `pr.head.sha`), automatically badged `human-gate`, assigned to the human as a formal PR Reviewer, and moved to **`Awaiting Approval`** on the Project Board. Post structured review comments (`gh pr review <N> --comment`), then STOP—never attempt to bypass or strip `human-gate`, and leave both **Approve** and **Merge** strictly to the human owner.
- **`staging` -> `master` Rolling Release PR:** Architect opens/updates the single rolling Release PR via `.factory/release-pr.sh` (which places it in **`Awaiting Approval`** and requests human review), while approving and merging into `master` is strictly human-only (and **must** use **"Create a merge commit"**, never Squash, to keep `staging` and `master` aligned).

## 8. Worker Definition of Done (Before Opening/Updating a PR)
1. Run `.factory/prep-branch.sh` (merges latest `origin/staging`, resets isolated Postgres schema, refreshes deps/skills; escalate to Architect for Fable on exit `2`).
2. Cover every bullet in the Issue's `Test Plan` (never add `.skip()`, `.only()`, `waitForTimeout()`, mocked APIs in E2E, or weakened assertions).
3. Apply migrations and run lint, typecheck, and full relevant tests against isolated `$DATABASE_URL`; all must exit `0`.
4. Keep PR diffs strictly scoped to the single assigned Issue/Sub-Issue's Acceptance Criteria.
5. Push branch and open/update a PR targeting `staging` with `Closes #<issue>` in the body.

## 9. Self-Healing CI Cap (Max 3 Retries) & Closed-Loop Learning
- On failed `CI & PR Evidence` runs, inspect `gh run view <run_id> --log-failed`, fix root cause (never weaken, skip, or delete existing tests), and push. Hard cap: **3 automated retries** before moving to `Blocked`. (A red `human-gate-guard` commit status is an intentional wait-for-human lock, never a build failure.)
- Whenever the human owner rejects a PR or corrects a recurring pattern: dispatch the fix, run `/workspace/.factory/sync-hub.sh`, append a concise 1-line rule to **Section 10** below (and `DECISIONS.md` / relevant `SKILL.md`), and push to `staging`.

## 10. Learned Harness Rules
- *(Architect appends concrete, one-line lessons learned from PR reviews here.)*
```

### 6.2 Create `DECISIONS.md` in Repo Root
```markdown
# DECISIONS.md — Architecture & Factory Decision Log

> Maintained by the Architect (`**[Architect]**`). Always read this file on session start to restore system-wide architectural context.

## Format
### YYYY-MM-DD — [Short Decision Title]
- **Context:** Why this decision was needed.
- **Decision:** What was chosen.
- **Consequences / Guardrails:** Rules workers must follow going forward.

---

## Initial Entries

### Bootstrap — Sandboxed 7-Container `herdr-software-factory` Stack + Native Herdr Over Internal SSH
- **Context:** Neither the Architect AI nor YOLO workers should have access to host `$HOME`, personal SSH/GH keys, `/var/run/docker.sock`, raw LLM API keys, or cross-agent credentials—yet Herdr still needs full native `idle`/`working`/`blocked`/`done` detection and cross-agent dispatch across all 4 agents.
- **Decision:** Deploy a single Docker Compose project (`herdr-software-factory`) with 7 hardened sibling containers across 3 networks (`factory-net`, `llm-net`, internal `db-net`). Run `herdr server` inside `herdr-hub`, launch internal SSH tabs wrapped with Herdr's official `HERDR_AGENT=<kind>` hint (`antigravity-cli`, `hermes`, `claude`) + `herdr agent rename`, validate host mounts via `.factory/preflight.sh`, and expose proxied token/request telemetry on `llm-proxy` `GET /stats`.
- **Consequences / Guardrails:** Zero `docker.sock` risk; all 4 agents appear in one unified `herdr agent list` with live status rollups; recover all 5 tabs cleanly after reboots via `.factory/launch-panes.sh` and `.factory/architect-seed.md`.

### Bootstrap — Turn-Serialized Priority Wait-Queue, Comment Coalescing, Post-Merge `staging` CI & Watchdog
- **Context:** Overlapping prompts break Architect focus; RAM-only queues lose events on restart; two parallel Wave PRs can each pass independently yet clash logically once merged to `staging`; silent quota hits can leave an agent idle without opening a PR.
- **Decision:** Run `.factory/webhook-bridge.mjs` as a disk-persisted (`hub-herdr` volume) Priority Herdr Wait-Queue (`herdr agent wait architect --until idle --until done`), coalesce rapid same-thread human comments within 8s, auto-sync `herdr-hub`'s `/workspace` via `.factory/sync-hub.sh`, trigger `ci-evidence.yml` on `push` to `staging` (alerting the Architect immediately if `staging` breaks), and run a 15-minute watchdog for >45-minute silent worker stalls.
- **Consequences / Guardrails:** Zero idle token burn, zero mid-turn interruptions, crash-safe persistence, immediate broken-staging detection, and mandatory `herdr agent list` + `in-progress` checks before dispatching.

### Bootstrap — 7-Column `Awaiting Approval` Board + Trusted-Branch `human-gate-guard` (Manual Human Merge)
- **Context:** PR-branch `pull_request` workflows can be tampered with, `pull_request_review` runs on base SHA rather than `pr.head.sha`, and human-gated items (auto-gated paths + Release PRs) need a single unmistakable home on the Kanban board without letting bots merge sensitive PRs.
- **Decision:** Keep 6 active automation labels (`plan`, `ready`, `in-progress`, `human-gate`, `blocked`, `fable-escalated`). Run `human-gate-guard.yml` on `pull_request_target` + `pull_request_review` (trusted `master` copy only, zero PR checkout) posting Commit Status `human-gate-guard` onto `pr.head.sha` (enforced by Ruleset #1 with zero bypasses). Auto-badge locked PRs/Issues `human-gate`, request `HUMAN_REVIEWER`, and move them (plus rolling `staging -> master` Release PRs) into the dedicated **`Awaiting Approval`** column—keeping **Approve + Merge** strictly manual by the human owner.
- **Consequences / Guardrails:** Human username remains the official merger in GitHub audit logs for all gated and production PRs; routine PRs still flow to `staging` automatically.

### Bootstrap — Plan-First Epic Decomposition, Waves & Merge-Commit Rolling Release PR
- **Context:** Forwarding vague features straight to workers causes oversized diffs and conflicts; squash-merging `staging -> master` causes `staging` and `master` to diverge and conflict on every subsequent release.
- **Decision:** Decompose `plan` Issues into atomic native Sub-Issues (`.factory/sub-issue.sh`) across waves and pause for human approval before `ready`. Enforce **1 unique Sub-Issue = 1 Idle Worker = 1 PR** (squash-merged into `staging`). When an Epic closes, run `.factory/release-pr.sh` to open/update one rolling `staging -> master` Release PR in `Awaiting Approval`—always merged by the human using **"Create a merge commit"** (never Squash).
- **Consequences / Guardrails:** Squash `feature/* -> staging`; merge-commit `staging -> master`. Never attempt to merge `staging -> master` as a bot.

### Bootstrap — Layered Testing, Local Playwright Evidence & Stateless Final-Wave E2E
- **Context:** Multi-layer Epics need permanent full-journey Playwright E2E tests (UI -> API -> Postgres), workers need preinstalled Chromium OS deps to run Playwright locally as non-root, and the Architect needs local PNG files downloaded from authenticated GitHub Actions artifacts for Hermes Vision inspection.
- **Decision:** Require Architect-authored **Test Plans** in every Sub-Issue, append a **Final Wave: End-to-End Verification** Sub-Issue dispatched to a **fresh, stateless session** (default `worker-gemini`, narrow 1–2 screen cross-model `worker-qwen`, never Fable/hub for routine E2E), preinstall Playwright Chromium deps in `Dockerfile.worker`, and provide `.factory/fetch-evidence.sh` so the Architect downloads artifact PNGs locally before Vision review.
- **Consequences / Guardrails:** Enforce `.agents/skills/e2e-testing/SKILL.md` and strict anti-tampering audits in `pr-evidence-review`.

### Bootstrap — Isolated Per-Worker Postgres (Clean Schema Reset) & Execution-Free Hub
- **Context:** Parallel workers need real Postgres instances without cross-contamination or leftover tables from previous branches, while `herdr-hub` must stay execution-free.
- **Decision:** Run 1 `factory-postgres` container on internal `db-net` with 3 locked-down non-superuser DBs (`app_gemini`, `app_qwen`, `app_fable`), place superuser extensions (`pgcrypto`, `uuid-ossp`) in a separate `extensions` schema, and reset `public` cleanly inside `.factory/prep-branch.sh` between tasks. Keep `herdr-hub` off `db-net`.
- **Consequences / Guardrails:** Workers only use `$DATABASE_URL`; CI verifies migrations from an empty DB on every PR and every push to `staging`; `migrations/` and `*.sql` are hard-gated by `human-gate-guard`.

### Bootstrap — Progressive-Disclosure Skills (`.agents/skills/` & `.factory/role-skills/`)
- **Context:** Workers write the actual frontend, database, and E2E code, so restricting standards to reviewers causes rework—yet pasting full guides into permanent prompts blows through Qwen's 54k context window.
- **Decision:** Store shared domain skills in `.agents/skills/` (loaded on demand by all agents) and role-specific playbooks in `.factory/role-skills/{architect,fable}/` (plus `herdr --skill` for Architect), auto-linked per container via `.factory/sync-skills.sh`.
- **Consequences / Guardrails:** Add new domain standards to `.agents/skills/<name>/SKILL.md` with clear YAML frontmatter so agents load them only when relevant.

### Bootstrap — Zero-Trust Bot Authorization & Model Roster (Option B)
- **Context:** Parallel YOLO workers need hard server-side branch boundaries, Architect needs unthrottled cross-file judgment + vision, and borrowed Claude Code Fable tokens must be conserved.
- **Decision:** Separate GitHub Apps (`factory-architect[bot]` vs. `factory-worker[bot]`) + 3 stacked Rulesets + `CODEOWNERS`; permanent **GLM-5.3** Architect (+ `auxiliary.vision: glm-5.3-flash`); **Gemini 3.8 Flash** (`agy`) + **Local Qwen 3.8 27B** (`hermes`) workers; **Claude Code** `specialist-fable` capped at 1 pass per PR (`fable-escalated`).
- **Consequences / Guardrails:** Workers target `staging` with `Closes #<issue>`; compact Architect session between epics after logging decisions here.
```

### 6.3 Create Starter Progressive-Disclosure Skills
Create the following five `SKILL.md` files (official upstream skill packs—such as Chrome's Modern Web Guidance skill—can also be dropped directly into `.agents/skills/<skill-name>/SKILL.md` anytime, and `.factory/sync-skills.sh` will propagate them automatically).

**Skill 1 (Shared — All Agents): `.agents/skills/modern-web-standards/SKILL.md`**
```markdown
---
name: modern-web-standards
description: Chrome modern web platform guidance for UI, HTML, CSS, accessibility, and Core Web Vitals. Load before building or reviewing any frontend or browser-facing code.
---

# Modern Web Platform Standards (Chrome Baseline Guidance)

Apply these rules whenever creating or modifying HTML, CSS, client-side JS/TS, or UI components:

1. **Prefer Native Web Platform Primitives Over Heavy JS Libraries**
   - Use semantic HTML (`<main>`, `<nav>`, `<section>`, `<button>`, `<label>`, `<form>`). Never use clickable `<div>`/`<span>` where a `<button>` or `<a>` belongs.
   - Use native Baseline browser features before reaching for JS polyfills: `<dialog>` (modals), Popover API (`popover`), `<details>`/`<summary>`, native form validation, CSS Container Queries (`@container`), `:has()`, CSS Grid/Subgrid, and native CSS nesting.
2. **Core Web Vitals (LCP, INP, CLS)**
   - **CLS:** Always set explicit `width`/`height` or `aspect-ratio` on images, videos, and async containers to prevent layout shift.
   - **LCP:** Do not lazy-load above-the-fold hero images (`loading="eager"`, `fetchpriority="high"`); lazy-load below-the-fold media.
   - **INP:** Avoid long synchronous main-thread tasks on click/input handlers; keep state updates lean and avoid layout thrashing.
3. **Accessibility (WCAG AA Baseline)**
   - Every interactive control must be keyboard-operable with visible `:focus-visible` styling.
   - Provide explicit `<label>` elements, accurate ARIA attributes only when native semantics are insufficient, and sufficient color contrast.
   - Respect `@media (prefers-reduced-motion: reduce)` for animations and transitions.
4. **Progressive Enhancement & Responsive Design**
   - Test both desktop and mobile viewports in Playwright evidence captures; avoid horizontal overflow and fixed-pixel layouts that break on narrow screens.
```

**Skill 2 (Shared — All Agents): `.agents/skills/postgres-migrations/SKILL.md`**
```markdown
---
name: postgres-migrations
description: Safe Postgres schema design, migration hygiene, and isolated DATABASE_URL testing. Load before touching SQL, ORM schemas, migrations, or database queries.
---

# Postgres Schema & Migration Safety Standards

1. **Strict Environment Discipline**
   - Always connect strictly via `process.env.DATABASE_URL` / `$DATABASE_URL`. Never hardcode hostnames, usernames, or passwords.
   - `.factory/prep-branch.sh` resets your isolated `public` schema cleanly before each branch (extensions live safely in `extensions`). Verify migrations apply cleanly from empty DB matching GitHub Actions CI.
2. **Safe, Zero-Downtime Migration Practices**
   - Never edit already-merged migration files; always add a new forward migration.
   - Use parameterized queries exclusively (zero string interpolation in SQL).
   - Add explicit indexes for foreign keys and high-frequency `WHERE`/`ORDER BY` columns.
   - Prefer additive/expand-and-contract changes over destructive `DROP COLUMN`/`DROP TABLE` in a single release; include clear rollback notes in the PR summary.
3. **Automatic Server Gate**
   - Changes under `migrations/`, `prisma/`, `drizzle/`, `alembic/`, or `*.sql` automatically trigger `human-gate-guard` (moving the card to `Awaiting Approval` and blocking merge to `staging` until the human owner approves & merges). If a schema change lives outside those paths, also add the `human-gate` label explicitly.
```

**Skill 3 (Shared — All Agents): `.agents/skills/e2e-testing/SKILL.md`**
```markdown
---
name: e2e-testing
description: Deterministic Playwright End-to-End (E2E) testing standards against a live app and isolated Postgres DB. Load before writing or auditing Final-Wave E2E verification tests.
---

# Deterministic Playwright E2E Testing Standards

Apply these rules whenever writing or updating full-journey E2E tests (typically Final-Wave verification Sub-Issues in a **fresh, stateless session**):

1. **Real Stack, Zero Mocking**
   - Exercise the real running application from the browser through real backend endpoints into your isolated Postgres DB (`$DATABASE_URL`).
   - **NEVER** stub or intercept internal application API calls with `page.route(...)` to fake backend success. Verify persistence across a real `page.reload()` or follow-up query.
2. **Resilient Locators & Web-First Assertions**
   - Prefer user-facing semantic locators in order: `getByRole`, `getByLabel`, `getByPlaceholder`, `getByText`, then `getByTestId` (`data-testid`). Never rely on brittle CSS class chains or deep XPath selectors.
   - Use Playwright web-first auto-waiting assertions (`await expect(locator).toBeVisible()`, `toHaveText()`, `toHaveURL()`).
   - **STRICTLY BANNED:** `page.waitForTimeout(...)`, arbitrary `sleep()`, `.skip()`, `.only()`, or `continue-on-error` workarounds.
3. **Test Isolation & Shared Helpers**
   - Reuse shared auth/seeding helpers under `tests/e2e/helpers/` if they exist (or create clean, minimal helpers there when establishing the first E2E flow).
   - Every test must seed/namespace its own unique records and pass reliably whether run standalone or alongside the full repository E2E suite against a fresh empty CI database.
4. **Visual Evidence & Bug Discovery**
   - Capture clean desktop (and mobile where UI layout matters) screenshots into Playwright's test artifacts so the Architect can download them via `.factory/fetch-evidence.sh` and inspect them via Vision.
   - If your E2E test uncovers a real bug in the `staging` app code, fix small unambiguous wiring bugs only if within scope—otherwise document the exact failing trace on the Issue/PR and notify the Architect rather than weakening the test assertion.
```

**Skill 4 (Architect Only): `.factory/role-skills/architect/pr-evidence-review/SKILL.md`**
```markdown
---
name: pr-evidence-review
description: Architect-only PR review rubric for verifying diffs, test coverage, anti-tampering rules, CI Postgres tests, human-gate-guard status, and downloaded Playwright visual evidence before approving or escalating.
---

# Architect PR, Test Integrity & Visual Evidence Review Rubric

Before formally approving any worker PR (`gh pr review <N> --approve`):
1. **Scope Check:** Confirm `gh pr diff <N>` strictly matches the single assigned Issue/Sub-Issue's Acceptance Criteria and `Out of Scope` guardrails.
2. **Test Coverage & Anti-Tampering Audit (MANDATORY):**
   - Confirm every bullet in the Issue's `Test Plan` is genuinely exercised by tests in the PR.
   - **IMMEDIATELY REJECT** any PR that introduces `.skip(`, `.only(`, `test.fixme(`, `waitForTimeout(`, mocked internal APIs inside E2E tests, deleted existing tests, or weakened assertions—unless the Sub-Issue explicitly specifies removing that behavior.
3. **Server Gate Check (`human-gate-guard`):** Verify `human-gate-guard` is green. If `human-gate-guard` is failing (protected path or `human-gate` label awaiting human approval) OR the diff touches auth/secrets/migrations outside protected paths, ensure `human-gate` is applied, move the linked card to `Awaiting Approval`, post structured review comments (`gh pr review <N> --comment`), and STOP.
4. **CI & Local Visual Evidence Inspection:** Verify `ci-and-evidence` passed (including clean-room Postgres migrations, full regression suite, and Playwright tests). For UI/E2E changes, run `/workspace/.factory/fetch-evidence.sh <run_id> <pr_num>` to download Playwright PNG artifacts locally into `/tmp/pr-evidence/`, then inspect the listed local image paths with Hermes `auxiliary.vision` for layout shifts, contrast, responsiveness, and visual regressions.
5. **Conflict Check:** If `mergeStateStatus` is `DIRTY` / `CONFLICTING`, escalate immediately to `specialist-fable` (if not yet `fable-escalated`) instead of debugging manually.
```

**Skill 5 (Fable Only): `.factory/role-skills/fable/conflict-and-rescue/SKILL.md`**
```markdown
---
name: conflict-and-rescue
description: Specialist-Fable 1-pass playbook for resolving staging merge conflicts and triaging 3-strike blocked CI failures cleanly within budget.
---

# Fable 1-Pass Conflict Resolution & Rescue Playbook

You are invoked under a strict **1-pass budget cap** (`fable-escalated`). Maximize precision on the first attempt:
1. **Merge Conflicts:** Run `.factory/prep-branch.sh <branch>` inside `/workspace` (expect exit `2`). Inspect both sides of every conflict marker alongside the linked Issue (`gh issue view <N>`) and recent `staging` commits (`git log -n 5 origin/staging --oneline`) so neither branch's intent is dropped.
2. **Blocked CI / Flaky E2E Rescues:** Read the exact failing logs (`gh run view <run_id> --log-failed`), isolate root cause (never weaken assertions, add `.skip()`, or introduce `waitForTimeout()`), and reproduce locally against your isolated `$DATABASE_URL`.
3. **Clean Verification & Handoff:** Run migrations, lint, typecheck, and full tests locally until exit `0`. Push the branch and post ONE concise `**[Fable]**` summary explaining the root cause and exact resolution, then return to idle.
```

**Phase 6 Verification:** `AGENTS.md`, `DECISIONS.md`, `.agents/skills/{modern-web-standards,postgres-migrations,e2e-testing}/SKILL.md`, and `.factory/role-skills/{architect/pr-evidence-review,fable/conflict-and-rescue}/SKILL.md` all exist.

---

## Phase 7: CI Evidence Pipeline (PR + Post-Merge `staging`) & Trusted `human-gate-guard`

### 7.1 Create `.github/workflows/ci-evidence.yml`
Runs on **both** `pull_request` (to `staging`/`master`) **and** `push` (to `staging`) against a fresh, empty **Postgres 16** service container—catching cross-PR logical regressions immediately after two parallel Wave PRs merge into `staging`. PR-only artifact uploads and PR summary comments are safely gated to `github.event_name == 'pull_request'`.
*(Bootstrap Agent Note: Inspect the repository's existing stack and adapt `npm ci` / `db:migrate` / `lint` / `build` / Playwright commands to match the actual package manager and ORM.)*

```yaml
name: CI & PR Evidence

on:
  pull_request:
    branches: [staging, master]
  push:
    branches: [staging]

permissions:
  contents: read
  pull-requests: write

concurrency:
  group: ci-evidence-${{ github.event_name }}-${{ github.head_ref || github.ref_name }}
  cancel-in-progress: true

jobs:
  ci-and-evidence:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: ci_user
          POSTGRES_PASSWORD: ci_password
          POSTGRES_DB: app_ci
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 5s
          --health-timeout 3s
          --health-retries 10
    env:
      DATABASE_URL: postgres://ci_user:ci_password@localhost:5432/app_ci
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Run Database Migrations (Clean-Room Check)
        run: npm run db:migrate --if-present

      - name: Lint
        run: npm run lint --if-present

      - name: Typecheck
        run: npm run typecheck --if-present

      - name: Unit & Integration Tests (Full Suite)
        run: npm test

      - name: Build
        run: npm run build

      - name: Install Playwright & Run Full E2E Suite + Visual Evidence
        if: hashFiles('playwright.config.*') != ''
        run: |
          npx playwright install --with-deps chromium
          npx playwright test --reporter=list
        continue-on-error: false

      - name: Upload Playwright Screenshots & Report
        if: always() && github.event_name == 'pull_request' && hashFiles('playwright-report/index.html', 'test-results/**') != ''
        uses: actions/upload-artifact@v4
        with:
          name: pr-${{ github.event.pull_request.number }}-evidence
          path: |
            playwright-report/
            test-results/
          retention-days: 14

      - name: Post or Update PR Evidence Summary
        if: always() && github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const marker = "<!-- factory-ci-evidence -->";
            const prNumber = context.payload.pull_request.number;
            const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
            const status = "${{ job.status }}";
            const icon = status === "success" ? "✅" : "❌";

            const body = [
              marker,
              `### ${icon} Factory CI & Visual Evidence`,
              `- **Commit:** \`${context.payload.pull_request.head.sha.slice(0, 7)}\``,
              `- **CI Status:** \`${status}\` (Clean-room Postgres 16 + full regression/E2E suite verified)`,
              `- **Workflow Run & Artifacts (Playwright Screenshots/Report):** [Inspect Run #${context.runId}](${runUrl})`,
              `- **Preview URL:** *(Attach Vercel/Cloudflare/Staging preview URL here if configured)*`
            ].join("\n");

            const { data: comments } = await github.rest.issues.listComments({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: prNumber
            });

            const existing = comments.find(c => c.body && c.body.includes(marker));
            if (existing) {
              await github.rest.issues.updateComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                comment_id: existing.id,
                body
              });
            } else {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: prNumber,
                body
              });
            }
```

### 7.2 Create Tamper-Proof `.github/workflows/human-gate-guard.yml`
Uses **`pull_request_target` + `pull_request_review`** (always executes the trusted copy from `master`, **never** checks out PR code, uses no secrets) and publishes an explicit Commit Status (`context: "human-gate-guard"`) directly onto **`pr.head.sha`**. This closes **both** edge cases:
1. A PR branch cannot bypass the guard by editing `.github/workflows/human-gate-guard.yml`.
2. When you click **Approve**, `pull_request_review` posts `state: "success"` directly onto `pr.head.sha`, immediately unlocking Ruleset #1 so **you** can click **Merge** right away (never auto-merged by bots).

Bootstrap Agent: substitute `<YOUR_GITHUB_USERNAME>` automatically via `gh api user -q .login`:

```yaml
name: Human Gate Guard

on:
  pull_request_target:
    branches: [staging, master]
    types: [opened, synchronize, reopened, labeled, unlabeled]
  pull_request_review:
    types: [submitted, dismissed]

# Trusted default-branch workflow only: NEVER checks out PR code, uses zero secrets
permissions:
  contents: read
  pull-requests: read
  statuses: write

concurrency:
  group: human-gate-guard-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  evaluate-human-gate:
    if: github.event.pull_request.base.ref == 'staging' || github.event.pull_request.base.ref == 'master'
    runs-on: ubuntu-latest
    env:
      # Comma-separated GitHub username(s) authorized to unlock human-gate PRs (matches .github/CODEOWNERS)
      HUMAN_APPROVERS: "<YOUR_GITHUB_USERNAME>"
    steps:
      - name: Evaluate Protected Paths, Label & Human Approval -> Publish Commit Status on PR Head SHA
        uses: actions/github-script@v7
        with:
          script: |
            const pr = context.payload.pull_request;
            const prNumber = pr.number;
            const headSha = pr.head.sha;
            const author = (pr.user?.login || "").toLowerCase();
            const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;

            async function setGuardStatus(state, description) {
              // GitHub Commit Status description is strictly capped at 140 characters
              const safeDesc = String(description).replace(/\s+/g, " ").trim().slice(0, 140);
              await github.rest.repos.createCommitStatus({
                owner: context.repo.owner,
                repo: context.repo.repo,
                sha: headSha,
                state,
                context: "human-gate-guard",
                description: safeDesc,
                target_url: runUrl,
              });
              core.info(`[human-gate-guard] Published commit status on ${headSha.slice(0, 7)}: ${state} — ${safeDesc}`);
            }

            const approvers = (process.env.HUMAN_APPROVERS || "")
              .split(",")
              .map((s) => s.trim().toLowerCase())
              .filter(Boolean);

            if (approvers.length === 0 || approvers[0].includes("<your_github_username>")) {
              await setGuardStatus("failure", "HUMAN_APPROVERS is not configured in human-gate-guard.yml");
              core.setFailed("HUMAN_APPROVERS is not configured in .github/workflows/human-gate-guard.yml");
              return;
            }

            // Human-authored PRs (e.g., initial bootstrap or emergency PRs opened by you) satisfy human gate automatically
            if (approvers.includes(author)) {
              await setGuardStatus("success", `Cleared: PR #${prNumber} authored by human approver @${author}.`);
              return;
            }

            // Protected path patterns that ALWAYS require human approval on bot PRs
            const PROTECTED_PATTERNS = [
              /(^|\/)(migrations?|prisma|drizzle|alembic)(\/|$)/i,
              /\.sql$/i,
              /(^|\/)(auth|security|rbac|permissions?)(\/|$)/i,
              /^\.github\//,
              /^\.factory\//,
              /(^|\/)\.agents\//,
              /^docker-compose.*\.ya?ml$/i,
              /^AGENTS\.md$/,
              /(^|\/)\.env/i,
            ];

            const files = await github.paginate(github.rest.pulls.listFiles, {
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: prNumber,
              per_page: 100,
            });

            const protectedHits = files
              .map((f) => f.filename)
              .filter((name) => PROTECTED_PATTERNS.some((re) => re.test(name)));

            const labels = (pr.labels || []).map((l) => l.name);
            const hasHumanGateLabel = labels.includes("human-gate");
            const targetsMaster = pr.base.ref === "master";

            const reasons = [];
            if (targetsMaster) reasons.push("target=master");
            if (hasHumanGateLabel) reasons.push("label=human-gate");
            if (protectedHits.length > 0) {
              reasons.push(`protected paths: ${protectedHits.slice(0, 3).join(", ")}${protectedHits.length > 3 ? " (+more)" : ""}`);
            }

            // Routine staging PR: no protected paths, no manual human-gate label
            if (reasons.length === 0) {
              await setGuardStatus("success", "Cleared: routine paths only (Architect may review & merge to staging).");
              return;
            }

            // Gated PR: verify latest decisive review from an authorized human approves the CURRENT head SHA
            const reviews = await github.paginate(github.rest.pulls.listReviews, {
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: prNumber,
              per_page: 100,
            });

            const latestByHuman = new Map();
            for (const r of reviews) {
              const login = (r.user?.login || "").toLowerCase();
              if (!approvers.includes(login)) continue;
              if (r.state === "COMMENTED") continue;
              latestByHuman.set(login, r);
            }

            const validApproval = [...latestByHuman.values()].find(
              (r) => r.state === "APPROVED" && r.commit_id === headSha
            );

            if (validApproval) {
              await setGuardStatus(
                "success",
                `Unlocked by @${validApproval.user.login} approval on commit ${headSha.slice(0, 7)}.`
              );
              return;
            }

            // Lock PR head SHA via Commit Status `failure` (job itself exits cleanly to avoid noisy Actions failure emails)
            await setGuardStatus(
              "failure",
              `Awaiting @${approvers.join("/@")} approval (${reasons.join("; ")})`
            );
            core.notice(
              `🔒 PR #${prNumber} (${headSha.slice(0, 7)}) locked by human-gate-guard. Reasons: ${reasons.join(" | ")}. Click Approve in GitHub Reviews to unlock.`
            );
```

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

```javascript
#!/usr/bin/env node
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const envCandidates = [
  process.env.BRIDGE_ENV_FILE,
  "/run/factory-config/bridge.env",
  path.resolve(".factory/.env"),
].filter(Boolean);

for (const envPath of envCandidates) {
  if (fs.existsSync(envPath)) {
    for (const line of fs.readFileSync(envPath, "utf8").split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const idx = trimmed.indexOf("=");
      if (idx > 0) {
        const key = trimmed.slice(0, idx).trim();
        const val = trimmed.slice(idx + 1).trim().replace(/^["']|["']$/g, "");
        if (!process.env[key]) process.env[key] = val;
      }
    }
    break;
  }
}

function detectHumanReviewer() {
  if (process.env.HUMAN_REVIEWER) return process.env.HUMAN_REVIEWER.replace(/^@/, "").trim();
  try {
    const codeowners = fs.readFileSync("/workspace/.github/CODEOWNERS", "utf8");
    const m = codeowners.match(/@([A-Za-z0-9-]+)/);
    return m ? m[1] : "";
  } catch {
    return "";
  }
}

const PORT = Number(process.env.WEBHOOK_PORT || 8787);
const BIND_HOST = process.env.WEBHOOK_BIND_HOST || "0.0.0.0";
const SECRET = process.env.GITHUB_WEBHOOK_SECRET || "";
const ARCHITECT_PANE = process.env.ARCHITECT_PANE || "architect";
const FABLE_PANE = process.env.FABLE_PANE || "specialist-fable";
const MAX_CI_RETRIES = Number(process.env.MAX_CI_RETRIES || 3);
const CI_WORKFLOW_NAME = process.env.CI_WORKFLOW_NAME || "CI & PR Evidence";
const PROJECT_NUMBER = process.env.PROJECT_NUMBER || "";
const REPO_FULL = process.env.FACTORY_REPO || "";
const HUMAN_REVIEWER = detectHumanReviewer();

// Upgraded Priority Wait-Queue, Coalescer & Stall Watchdog settings
const STATE_DIR = path.resolve(
  process.env.BRIDGE_STATE_DIR || "/home/factory/.config/herdr/bridge-state"
);
const RETRY_STATE_FILE = path.join(STATE_DIR, "retry-state.json");
const QUEUE_STATE_FILE = path.join(STATE_DIR, "architect-queue.json");
const COMMENT_COALESCE_MS = Number(process.env.COMMENT_COALESCE_MS || 8_000);
const ARCHITECT_WAIT_TIMEOUT_MS = Number(process.env.ARCHITECT_WAIT_TIMEOUT_MS || 300_000);
const ARCHITECT_IDLE_POLL_MS = Number(process.env.ARCHITECT_IDLE_POLL_MS || 5_000);
const STALL_WATCHDOG_INTERVAL_MS = Number(process.env.STALL_WATCHDOG_INTERVAL_MS || 900_000); // 15 min
const STALL_THRESHOLD_MS = Number(process.env.STALL_THRESHOLD_MS || 2_700_000); // 45 min

const PRIORITY = {
  HUMAN_COMMENT: 10, // Highest: jumps ahead of queued background events
  CI_URGENT: 20,     // Broken staging, CI failures, blocked escalations, merge conflicts
  REVIEW_WAVE: 30,   // Passing CI reviews, wave advancement, stall alerts
  PLAN_READY: 40,    // New plan/ready dispatches
};

const BOARD_SYNC_SCRIPT = path.resolve("/workspace/.factory/board-sync.sh");
const SUB_ISSUE_SCRIPT = path.resolve("/workspace/.factory/sub-issue.sh");
const SYNC_HUB_SCRIPT = path.resolve("/workspace/.factory/sync-hub.sh");
const FACTORY_GH = path.resolve("/workspace/.factory/bin/gh");

const ARCHITECT_EXEC_ENV = {
  ...process.env,
  FACTORY_ROLE: "architect",
};

const AGENT_SIGNATURES = [
  "**[Architect]**",
  "**[Gemini]**",
  "**[Qwen]**",
  "**[Fable]**",
  "<!-- factory-ci-evidence -->",
];

if (!SECRET) {
  console.error("[bridge] ERROR: GITHUB_WEBHOOK_SECRET is required in bridge.env");
  process.exit(1);
}

fs.mkdirSync(STATE_DIR, { recursive: true });

function writeJsonAtomic(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmp = `${filePath}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
  fs.renameSync(tmp, filePath);
}

function loadRetryState() {
  try {
    const parsed = JSON.parse(fs.readFileSync(RETRY_STATE_FILE, "utf8"));
    return {
      prRetries: parsed?.prRetries || {},
      stallAlerts: parsed?.stallAlerts || {},
    };
  } catch {
    return { prRetries: {}, stallAlerts: {} };
  }
}

function saveRetryState(state) {
  writeJsonAtomic(RETRY_STATE_FILE, state);
}

function loadQueueFromDisk() {
  try {
    const parsed = JSON.parse(fs.readFileSync(QUEUE_STATE_FILE, "utf8"));
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveQueueToDisk() {
  writeJsonAtomic(QUEUE_STATE_FILE, queue);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function verifySignature(rawBody, sigHeader) {
  if (!sigHeader || !sigHeader.startsWith("sha256=")) return false;
  const expected = "sha256=" + crypto.createHmac("sha256", SECRET).update(rawBody).digest("hex");
  const a = Buffer.from(sigHeader);
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function isAgentOrBotComment(body = "", sender = {}) {
  const login = String(sender?.login || "").toLowerCase();
  if (sender?.type === "Bot" || login.endsWith("[bot]")) return true;
  const trimmed = body.trim();
  return AGENT_SIGNATURES.some((sig) => trimmed.includes(sig));
}

function extractLinkedIssue(body = "", headBranch = "") {
  const bodyMatch = String(body || "").match(/(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)/i);
  if (bodyMatch) return Number(bodyMatch[1]);
  const branchMatch = String(headBranch || "").match(/issue-(\d+)/i);
  return branchMatch ? Number(branchMatch[1]) : null;
}

async function ghAsArchitect(args, timeout = 20_000) {
  return execFileAsync(FACTORY_GH, args, { env: ARCHITECT_EXEC_ENV, timeout });
}

async function syncHubWorkspace() {
  if (!fs.existsSync(SYNC_HUB_SCRIPT)) return;
  try {
    await execFileAsync(SYNC_HUB_SCRIPT, [], { env: ARCHITECT_EXEC_ENV, timeout: 25_000 });
  } catch (err) {
    console.warn("[bridge] Non-fatal sync-hub warning:", err.message);
  }
}

// targetRef: issue number (e.g. 42) OR "pr:42"
async function syncBoardField(targetRef, fieldName, value) {
  if (!PROJECT_NUMBER || !targetRef) return;
  try {
    await execFileAsync(BOARD_SYNC_SCRIPT, [String(targetRef), fieldName, value], {
      env: ARCHITECT_EXEC_ENV,
      timeout: 20_000,
    });
  } catch (err) {
    console.warn(`[bridge] Non-fatal board sync warning for ${targetRef}:`, err.message);
  }
}

async function surfaceAwaitingApproval(prNumber, linkedIssue, isReleasePr = false) {
  try {
    await ghAsArchitect(["pr", "edit", String(prNumber), "--add-label", "human-gate"]).catch(() => {});
    if (HUMAN_REVIEWER) {
      await ghAsArchitect(["pr", "edit", String(prNumber), "--add-reviewer", HUMAN_REVIEWER]).catch(() => {});
    }
    if (linkedIssue) {
      await ghAsArchitect(["issue", "edit", String(linkedIssue), "--add-label", "human-gate"]).catch(() => {});
      await syncBoardField(linkedIssue, "Status", "Awaiting Approval");
    }
    if (isReleasePr || !linkedIssue) {
      await syncBoardField(`pr:${prNumber}`, "Status", "Awaiting Approval");
    }
  } catch (err) {
    console.warn(`[bridge] Non-fatal Awaiting Approval sync warning for PR #${prNumber}:`, err.message);
  }
}

async function getParentEpic(issueNumber) {
  if (!issueNumber || !fs.existsSync(SUB_ISSUE_SCRIPT)) return null;
  try {
    const { stdout } = await execFileAsync(SUB_ISSUE_SCRIPT, ["parent", String(issueNumber)], {
      env: ARCHITECT_EXEC_ENV,
      timeout: 15_000,
    });
    const parsed = JSON.parse(stdout.trim() || "null");
    return parsed && parsed.number ? parsed : null;
  } catch {
    return null;
  }
}

async function getSubIssueSummary(issueNumber) {
  if (!issueNumber || !fs.existsSync(SUB_ISSUE_SCRIPT)) {
    return { total: 0, completed: 0, percent_completed: 0 };
  }
  try {
    const { stdout } = await execFileAsync(SUB_ISSUE_SCRIPT, ["summary", String(issueNumber)], {
      env: ARCHITECT_EXEC_ENV,
      timeout: 15_000,
    });
    return JSON.parse(stdout.trim() || '{"total":0,"completed":0,"percent_completed":0}');
  } catch {
    return { total: 0, completed: 0, percent_completed: 0 };
  }
}

async function inspectPrMeta(prNumber, headBranch = "") {
  try {
    const { stdout } = await ghAsArchitect([
      "pr",
      "view",
      String(prNumber),
      "--json",
      "body,labels,mergeable,mergeStateStatus,headRefName,baseRefName,statusCheckRollup",
    ]);
    const pr = JSON.parse(stdout);
    const labels = (pr.labels || []).map((l) => l.name);
    const checks = pr.statusCheckRollup || [];
    const gateCheck = checks.find((c) => (c.name || c.context) === "human-gate-guard");
    const gateState = gateCheck
      ? String(gateCheck.conclusion || gateCheck.state || gateCheck.status || "").toUpperCase()
      : "UNKNOWN";
    const humanGateBlocked = gateCheck ? gateState !== "SUCCESS" : false;

    return {
      linkedIssue: extractLinkedIssue(pr.body, pr.headRefName || headBranch),
      labels,
      hasFableEscalated: labels.includes("fable-escalated"),
      hasHumanGateLabel: labels.includes("human-gate"),
      humanGateBlocked,
      isConflicting: pr.mergeable === "CONFLICTING" || pr.mergeStateStatus === "DIRTY",
      headRefName: pr.headRefName || headBranch,
      baseRefName: pr.baseRefName || "",
    };
  } catch {
    return {
      linkedIssue: extractLinkedIssue("", headBranch),
      labels: [],
      hasFableEscalated: false,
      hasHumanGateLabel: false,
      humanGateBlocked: false,
      isConflicting: false,
      headRefName: headBranch,
      baseRefName: "",
    };
  }
}

// === Disk-Persisted Priority Queue + 8s Same-Thread Human Comment Coalescer ===
const queue = loadQueueFromDisk();
const pendingComments = new Map(); // threadKey -> { isPR, num, comments: [...], timer }
let processing = false;
let currentItemSummary = null;

function sortQueue() {
  queue.sort((a, b) => a.priority - b.priority || a.createdAt - b.createdAt);
}

function buildHumanCommentPrompt({ isPR, num, comments }) {
  const kind = isPR ? `PR #${num}` : `Issue #${num}`;
  const header =
    comments.length > 1
      ? `[GITHUB EVENT: HUMAN COMMENTS (${comments.length} bundled on ${kind})]`
      : `[GITHUB EVENT: HUMAN COMMENT] ${kind}`;

  const rendered = comments
    .map((c, idx) => {
      const fileCtx = c.path ? ` (File: ${c.path})` : "";
      const prefix = comments.length > 1 ? `Comment ${idx + 1} by @${c.user}${fileCtx}:` : `By @${c.user}${fileCtx}:`;
      return `${prefix}\n"""\n${c.body}\n"""`;
    })
    .join("\n\n");

  return [
    header,
    rendered,
    `Action required:`,
    `1. Inspect context via \`gh ${isPR ? "pr" : "issue"} view ${num}\`${isPR ? ` and \`gh pr diff ${num}\`` : ""}.`,
    `2. If this approves or adjusts a Wave Blueprint, update Sub-Issues or dispatch Wave 1 accordingly (check BOTH \`herdr agent list\` and \`gh issue list --label in-progress\` first so no working/blocked worker is double-assigned). If code changes are needed on a PR, dispatch to the responsible idle worker (\`worker-gemini\` or \`worker-qwen\`).`,
    `3. If this corrects a recurring pattern or architectural rule, run \`/workspace/.factory/sync-hub.sh\`, update AGENTS.md (Section 10), DECISIONS.md, or the relevant \`.agents/skills/\` file, and push to \`staging\`.`,
    `4. Reply on GitHub prefixed with \`**[Architect]**\`.`,
  ].join("\n");
}

function enqueueArchitectPrompt(promptText, opts = {}) {
  const item = {
    id: crypto.randomUUID(),
    priority: opts.priority ?? PRIORITY.PLAN_READY,
    kind: opts.kind || "event",
    threadKey: opts.threadKey || null,
    createdAt: Date.now(),
    prompt: promptText,
    meta: opts.meta || null,
  };
  queue.push(item);
  sortQueue();
  saveQueueToDisk();
  console.log(
    `[bridge] Enqueued ${item.kind} (priority=${item.priority}, thread=${item.threadKey || "none"}, queueDepth=${queue.length})`
  );
  if (!processing) drainQueue();
}

function flushHumanCommentThread(threadKey) {
  const bucket = pendingComments.get(threadKey);
  if (!bucket) return;
  clearTimeout(bucket.timer);
  pendingComments.delete(threadKey);

  const existingQueued = queue.find(
    (item) => item.kind === "human_comment" && item.threadKey === threadKey
  );
  if (existingQueued && existingQueued.meta?.comments) {
    existingQueued.meta.comments.push(...bucket.comments);
    existingQueued.prompt = buildHumanCommentPrompt(existingQueued.meta);
    saveQueueToDisk();
    console.log(
      `[bridge] Coalesced ${bucket.comments.length} follow-up comment(s) into queued thread ${threadKey} (total=${existingQueued.meta.comments.length}).`
    );
    if (!processing) drainQueue();
    return;
  }

  const meta = { isPR: bucket.isPR, num: bucket.num, comments: bucket.comments };
  enqueueArchitectPrompt(buildHumanCommentPrompt(meta), {
    priority: PRIORITY.HUMAN_COMMENT,
    kind: "human_comment",
    threadKey,
    meta,
  });
}

function bufferHumanComment({ isPR, num, user, body, filePath }) {
  const threadKey = `${isPR ? "pr" : "issue"}:${num}`;
  const entry = {
    user: user || "human",
    path: filePath || "",
    body: String(body || ""),
    receivedAt: Date.now(),
  };

  let bucket = pendingComments.get(threadKey);
  if (!bucket) {
    bucket = { isPR, num, comments: [], timer: null };
    pendingComments.set(threadKey, bucket);
  }
  bucket.comments.push(entry);

  if (bucket.timer) clearTimeout(bucket.timer);
  bucket.timer = setTimeout(() => flushHumanCommentThread(threadKey), COMMENT_COALESCE_MS);
  console.log(
    `[bridge] Buffered human comment on ${threadKey} (${bucket.comments.length} in ${COMMENT_COALESCE_MS}ms coalesce window).`
  );
}

async function waitForArchitectIdle() {
  await execFileAsync(
    "herdr",
    [
      "agent",
      "wait",
      ARCHITECT_PANE,
      "--until",
      "idle",
      "--until",
      "done",
      "--timeout",
      String(ARCHITECT_WAIT_TIMEOUT_MS),
    ],
    { timeout: ARCHITECT_WAIT_TIMEOUT_MS + 5_000 }
  );
}

async function sendAndWaitArchitectTurn(promptText) {
  await execFileAsync(
    "herdr",
    [
      "agent",
      "prompt",
      ARCHITECT_PANE,
      promptText,
      "--wait",
      "--until",
      "idle",
      "--until",
      "done",
      "--timeout",
      String(ARCHITECT_WAIT_TIMEOUT_MS),
    ],
    { timeout: ARCHITECT_WAIT_TIMEOUT_MS + 5_000 }
  );
  return { delivered: true };
}

async function drainQueue() {
  if (processing) return;
  processing = true;

  try {
    while (queue.length > 0) {
      sortQueue();
      const next = queue[0];
      currentItemSummary = `${next.kind}${next.threadKey ? ` (${next.threadKey})` : ""}`;

      try {
        console.log(
          `[bridge] Waiting for "${ARCHITECT_PANE}" to be idle/done before dispatching ${currentItemSummary} (queued=${queue.length})...`
        );
        await waitForArchitectIdle();
      } catch (err) {
        console.warn(
          `[bridge] Architect "${ARCHITECT_PANE}" still busy/blocked/unavailable (${err.stderr?.trim() || err.message}); keeping queue persisted and retrying in ${ARCHITECT_IDLE_POLL_MS}ms.`
        );
        await sleep(ARCHITECT_IDLE_POLL_MS);
        continue;
      }

      sortQueue();
      const item = queue.shift();
      saveQueueToDisk();
      currentItemSummary = `${item.kind}${item.threadKey ? ` (${item.threadKey})` : ""}`;

      const startedAt = Date.now();
      try {
        console.log(
          `[bridge] Dispatching ${currentItemSummary} (priority=${item.priority}) to "${ARCHITECT_PANE}"...`
        );
        await sendAndWaitArchitectTurn(item.prompt);
        console.log(
          `[bridge] Completed turn for ${currentItemSummary} in ${Math.round((Date.now() - startedAt) / 1000)}s (remaining=${queue.length}).`
        );
      } catch (err) {
        const elapsed = Date.now() - startedAt;
        const errMsg = String(err.stderr || err.message || "");
        if (/agent_blocked/i.test(errMsg)) {
          console.warn(
            `[bridge] Architect "${ARCHITECT_PANE}" is blocked on a prompt; re-queuing ${currentItemSummary} safely and retrying in ${ARCHITECT_IDLE_POLL_MS}ms.`
          );
          queue.unshift(item);
          sortQueue();
          saveQueueToDisk();
          await sleep(ARCHITECT_IDLE_POLL_MS);
        } else if (err.killed || elapsed >= ARCHITECT_WAIT_TIMEOUT_MS - 1_000) {
          console.warn(
            `[bridge] Turn for ${currentItemSummary} exceeded ${ARCHITECT_WAIT_TIMEOUT_MS}ms wait timeout; will wait for idle before next item.`
          );
        } else {
          console.error(
            `[bridge] Fast dispatch failure for ${currentItemSummary}; re-queuing safely:`,
            errMsg
          );
          queue.unshift(item);
          sortQueue();
          saveQueueToDisk();
          await sleep(ARCHITECT_IDLE_POLL_MS);
        }
      }
    }
  } finally {
    currentItemSummary = null;
    processing = false;
    if (queue.length > 0) drainQueue();
  }
}

// === Lightweight Worker Stall Watchdog (Belt-and-Suspenders Alongside Live Herdr States) ===
async function runStallWatchdog() {
  try {
    const { stdout: issuesOut } = await ghAsArchitect([
      "issue",
      "list",
      "--label",
      "in-progress",
      "--state",
      "open",
      "--limit",
      "30",
      "--json",
      "number,title,updatedAt,labels",
    ]);
    const inProgressIssues = JSON.parse(issuesOut || "[]");
    if (inProgressIssues.length === 0) return;

    const { stdout: prsOut } = await ghAsArchitect([
      "pr",
      "list",
      "--state",
      "open",
      "--limit",
      "30",
      "--json",
      "number,headRefName,body,updatedAt",
    ]);
    const openPrs = JSON.parse(prsOut || "[]");

    const now = Date.now();
    const state = loadRetryState();
    let stateChanged = false;

    for (const issue of inProgressIssues) {
      const labels = (issue.labels || []).map((l) => l.name);
      if (labels.includes("blocked")) continue;

      // Skip parent Epics (they stay in-progress across multiple waves)
      const summary = await getSubIssueSummary(issue.number);
      if (summary.total > 0) continue;

      const linkedPr = openPrs.find(
        (pr) => extractLinkedIssue(pr.body, pr.headRefName) === issue.number
      );
      const lastActivityMs = Math.max(
        Date.parse(issue.updatedAt || 0) || 0,
        linkedPr ? Date.parse(linkedPr.updatedAt || 0) || 0 : 0
      );

      if (!lastActivityMs || now - lastActivityMs < STALL_THRESHOLD_MS) continue;

      const alertKey = String(issue.number);
      const marker = String(lastActivityMs);
      if (state.stallAlerts[alertKey] === marker) continue;

      state.stallAlerts[alertKey] = marker;
      stateChanged = true;

      const idleMins = Math.round((now - lastActivityMs) / 60_000);
      enqueueArchitectPrompt(
        [
          `[GITHUB EVENT: STALL WATCHDOG] Issue #${issue.number} ("${issue.title}") has been \`in-progress\` with no Issue/PR activity for ~${idleMins} minutes${linkedPr ? ` (PR #${linkedPr.number} open)` : " (no PR opened yet)"}.`,
          `Action required (per AGENTS.md Section 5):`,
          `1. Run \`herdr agent list\` and \`herdr agent read <worker> --source recent-unwrapped --lines 80\` on \`worker-gemini\` / \`worker-qwen\` to see whether the worker is \`blocked\`, crashed, or silently hit Antigravity's rolling 5-hour quota.`,
          `2. Nudge/recover the worker, overflow the Sub-Issue to \`worker-qwen\` if \`worker-gemini\` is quota-limited, OR label Issue #${issue.number} \`blocked\` and post a concise \`**[Architect]**\` update for the human owner.`,
        ].join("\n"),
        { priority: PRIORITY.REVIEW_WAVE, kind: "worker_stall", threadKey: `issue:${issue.number}` }
      );
    }

    if (stateChanged) saveRetryState(state);
  } catch (err) {
    console.warn("[bridge] Stall watchdog non-fatal error:", err.message);
  }
}

async function addBlockedLabel(prNumber, runId, linkedIssue) {
  try {
    await ghAsArchitect(["pr", "edit", String(prNumber), "--add-label", "blocked"]);
    if (linkedIssue) {
      await ghAsArchitect(["issue", "edit", String(linkedIssue), "--add-label", "blocked"]).catch(
        () => {}
      );
      await syncBoardField(linkedIssue, "Status", "Blocked");
    }
    await ghAsArchitect([
      "pr",
      "comment",
      String(prNumber),
      "--body",
      `**[Architect]** Automated CI self-heal cap (${MAX_CI_RETRIES} attempts) reached on run #${runId}. Labeled \`blocked\` and moved board card to \`Blocked\` — escalating for Architect / optional 1-shot Fable / human intervention.`,
    ]);
  } catch (err) {
    console.error("[bridge] Failed to mark PR blocked via gh:", err.stderr || err.message);
  }
}

async function handleEvent(event, payload) {
  // 1a. Issue labeled "plan" -> Sync hub /workspace, decompose into native Sub-Issues & STOP
  if (event === "issues" && payload.action === "labeled" && payload.label?.name === "plan") {
    const issue = payload.issue;
    await syncHubWorkspace();
    await syncBoardField(issue.number, "Status", "Backlog");

    enqueueArchitectPrompt(
      [
        `[GITHUB EVENT: PLAN REQUEST] Issue #${issue.number}: "${issue.title}"`,
        `Action required (DO NOT DISPATCH ANY WORKERS YET — per AGENTS.md Section 4 & 5):`,
        `1. \`/workspace\` was just synced to \`origin/staging\`. Run \`gh issue view ${issue.number}\` and inspect the relevant codebase files in \`/workspace\`.`,
        `2. Break this feature into small, unambiguous, single-PR child Issues (exact target files, DB migrations if needed, Acceptance Criteria, an explicit **Test Plan**, relevant \`.agents/skills/\`, optional \`human-gate\` only if extra human review is needed outside auto-protected paths, and explicit Wave order with non-overlapping file scopes for parallel waves).`,
        `3. If this Epic spans multiple layers (e.g., DB + API + UI) or adds a user-facing workflow, append a **Final Wave: End-to-End Verification** Sub-Issue (runs AFTER build waves merge to \`staging\`, in a fresh/stateless session, defaulting to \`worker-gemini\` or \`worker-qwen\` only for narrow 1-2 screen flows).`,
        `4. Create each child Issue in Backlog (NO \`ready\` label yet) and attach it via \`/workspace/.factory/sub-issue.sh link ${issue.number} <child_num>\`.`,
        `5. Remove the \`plan\` label: \`gh issue edit ${issue.number} --remove-label plan\`.`,
        `6. Post a concise \`**[Architect]**\` Wave Blueprint + any clarifying questions on Issue #${issue.number}, then STOP and wait for the human owner to review and apply \`ready\`.`,
      ].join("\n"),
      { priority: PRIORITY.PLAN_READY, kind: "plan_request", threadKey: `issue:${issue.number}` }
    );
    return;
  }

  // 1b. Issue labeled "ready" -> Dispatch Wave 1 (if native Epic) OR triage & dispatch atomic task (1:1 idle worker)
  if (event === "issues" && payload.action === "labeled" && payload.label?.name === "ready") {
    const issue = payload.issue;
    const labelNames = (issue.labels || []).map((l) => l.name);
    await syncHubWorkspace();
    const summary = await getSubIssueSummary(issue.number);
    const isEpic = summary.total > 0;
    await syncBoardField(issue.number, "Status", "Ready");

    if (isEpic) {
      enqueueArchitectPrompt(
        [
          `[GITHUB EVENT: EPIC APPROVED — DISPATCH WAVE 1] Parent Issue #${issue.number}: "${issue.title}" (${summary.completed}/${summary.total} Sub-Issues done)`,
          `Action required (per AGENTS.md Section 4 — 1 unique Sub-Issue = 1 IDLE Worker = 1 PR):`,
          `1. Check BOTH \`herdr agent list\` (confirm \`idle\`/\`done\`, not \`working\`/\`blocked\`) AND \`gh issue list --label in-progress --state open\` so no busy worker container is double-assigned.`,
          `2. Swap parent label \`ready\` -> \`in-progress\` and set board Status to \`In Progress\`.`,
          `3. Inspect Sub-Issues via \`/workspace/.factory/sub-issue.sh list ${issue.number}\` and read the Wave Blueprint on Issue #${issue.number}.`,
          `4. Dispatch ONLY unblocked Wave 1 Sub-Issues across idle routine workers (\`worker-gemini\` / \`worker-qwen\`, NEVER \`${FABLE_PANE}\`) — strictly 1 unique Sub-Issue per idle worker container. Hold dependent waves (including Final-Wave E2E) in \`Backlog\`.`,
          `5. For each dispatched Sub-Issue, add \`in-progress\` and sync its Kanban card (\`Status="In Progress"\`, \`Worker="Gemini"|"Qwen"\`).`,
        ].join("\n"),
        { priority: PRIORITY.PLAN_READY, kind: "epic_ready", threadKey: `issue:${issue.number}` }
      );
    } else {
      const parentEpic = await getParentEpic(issue.number);
      const parentCtx = parentEpic
        ? `Sub-Issue of Parent Issue #${parentEpic.number} ("${parentEpic.title}")`
        : `Standalone Issue (not linked to an Epic)`;

      enqueueArchitectPrompt(
        [
          `[GITHUB EVENT: ISSUE READY] Issue #${issue.number}: "${issue.title}" (${parentCtx})`,
          `Labels: ${labelNames.join(", ")}`,
          `Action required:`,
          `1. Run \`gh issue view ${issue.number}\` to inspect the spec.`,
          `2. Scope Triage (AGENTS.md Section 4): If this is a standalone vague/multi-part feature that should NOT be built in a single PR, DO NOT forward blindly — decompose into native Sub-Issues (including Test Plans + Final-Wave E2E if multi-layer) via \`.factory/sub-issue.sh\`, remove \`ready\`, post the Wave Blueprint, and pause for human approval.`,
          `3. If atomic and crystal clear: check BOTH \`herdr agent list\` AND \`gh issue list --label in-progress --state open\` to pick 1 IDLE routine worker (\`worker-gemini\` or \`worker-qwen\`, NEVER \`${FABLE_PANE}\`), swap \`ready\` -> \`in-progress\`, note relevant \`.agents/skills/\`, update the Project Board (\`Status="In Progress"\`, \`Worker="Gemini"|"Qwen"\`), and dispatch via \`herdr agent prompt\`.`,
        ].join("\n"),
        { priority: PRIORITY.PLAN_READY, kind: "issue_ready", threadKey: `issue:${issue.number}` }
      );
    }
    return;
  }

  // 2. Human comment on Issue or PR -> 8s same-thread coalescer + highest-priority queue
  if (
    (event === "issue_comment" || event === "pull_request_review_comment") &&
    payload.action === "created"
  ) {
    const comment = payload.comment;
    if (isAgentOrBotComment(comment?.body, comment?.user)) {
      console.log("[bridge] Ignored agent/bot comment (anti-loop guard).");
      return;
    }

    const num = payload.issue?.number || payload.pull_request?.number;
    const isPR = Boolean(payload.pull_request || payload.issue?.pull_request);
    bufferHumanComment({
      isPR,
      num,
      user: comment.user?.login,
      body: comment.body,
      filePath: comment.path || "",
    });
    return;
  }

  // 3. PR Merged into staging -> Sync hub /workspace, auto-advance Parent Epic to next Wave, OR close Epic & open/update rolling Release PR
  if (
    event === "pull_request" &&
    payload.action === "closed" &&
    payload.pull_request?.merged === true &&
    payload.pull_request?.base?.ref === "staging"
  ) {
    const pr = payload.pull_request;
    await syncHubWorkspace();
    const linkedIssue = extractLinkedIssue(pr.body, pr.head?.ref);
    if (!linkedIssue) return;

    await syncBoardField(linkedIssue, "Status", "Done");
    const parentEpic = await getParentEpic(linkedIssue);
    if (!parentEpic) return;

    const summary = await getSubIssueSummary(parentEpic.number);
    enqueueArchitectPrompt(
      [
        `[GITHUB EVENT: SUB-ISSUE MERGED TO STAGING — WAVE CHECK] PR #${pr.number} (Sub-Issue #${linkedIssue}) merged into \`staging\`.`,
        `Parent Issue #${parentEpic.number} ("${parentEpic.title}") progress: ${summary.completed}/${summary.total} Sub-Issues completed (${summary.percent_completed}%).`,
        `Action required (per AGENTS.md Section 4 & 5):`,
        `1. Run \`/workspace/.factory/sub-issue.sh list ${parentEpic.number}\` and \`/workspace/.factory/sub-issue.sh summary ${parentEpic.number}\`.`,
        `2. If all Sub-Issues are closed (\`completed === total\`): post a \`**[Architect]**\` completion summary on Issue #${parentEpic.number}, close it (\`gh issue close ${parentEpic.number}\`), and run \`/workspace/.factory/release-pr.sh ${parentEpic.number}\` to open or update the rolling \`staging -> master\` Release PR in \`Awaiting Approval\`.`,
        `3. Otherwise: check \`herdr agent list\` and \`gh issue list --label in-progress --state open\` for idle workers and dispatch the next unblocked Wave strictly 1 unique Sub-Issue per idle routine worker (\`worker-gemini\` / \`worker-qwen\`), updating their labels & Kanban cards. If dispatching a Final-Wave E2E Sub-Issue, route to \`worker-gemini\` by default (or \`worker-qwen\` only for narrow 1-2 screen cross-model flows) and explicitly instruct the worker to start a **fresh/stateless session** and load \`.agents/skills/e2e-testing/SKILL.md\`.`,
      ].join("\n"),
      { priority: PRIORITY.REVIEW_WAVE, kind: "wave_check", threadKey: `issue:${parentEpic.number}` }
    );
    return;
  }

  // 4. GitHub Actions CI Completed -> Post-Merge `staging` Regression Guard, Self-Heal Loop, Conflict Escalation, OR Review/Awaiting Approval
  //    Strictly filters for CI_WORKFLOW_NAME so intentional `Human Gate Guard` runs never trigger CI retries.
  if (event === "workflow_run" && payload.action === "completed") {
    const run = payload.workflow_run;
    if (run.name !== CI_WORKFLOW_NAME) {
      console.log(`[bridge] Ignored non-CI workflow "${run.name}" (${run.conclusion}).`);
      return;
    }

    // 4a. Post-merge CI on `staging` (`push`) -> catch logical regressions between parallel Wave PRs immediately
    if (run.event === "push" && run.head_branch === "staging") {
      if (run.conclusion === "failure") {
        await syncHubWorkspace();
        enqueueArchitectPrompt(
          [
            `[GITHUB EVENT: STAGING BROKEN — POST-MERGE CI FAILED] "${run.name}" run #${run.id} FAILED on \`staging\` (commit \`${String(run.head_sha || "").slice(0, 7)}\`).`,
            `Action required (per AGENTS.md Section 5):`,
            `1. PAUSE merging any new PRs into \`staging\` until \`staging\` is green again.`,
            `2. Inspect \`gh run view ${run.id} --log-failed\` and recent \`git log -n 5 origin/staging --oneline\` to identify which merged PRs clashed.`,
            `3. Check \`herdr agent list\` and dispatch a focused hotfix branch/PR (targeting \`staging\`) to an idle routine worker (\`worker-gemini\` or \`worker-qwen\`), or alert the human owner if a revert or decision is needed.`,
          ].join("\n"),
          { priority: PRIORITY.CI_URGENT, kind: "staging_broken", threadKey: "branch:staging" }
        );
      } else {
        console.log(`[bridge] Post-merge CI on staging (${String(run.head_sha || "").slice(0, 7)}) concluded: ${run.conclusion}.`);
      }
      return;
    }

    const prs = run.pull_requests || [];
    if (prs.length === 0) return;

    const prNumber = prs[0].number;
    const prMeta = await inspectPrMeta(prNumber, run.head_branch);
    const state = loadRetryState();
    const key = String(prNumber);

    // 4b. Rolling staging -> master Release PR passing CI: ensure surfaced in `Awaiting Approval` & wait quietly for human
    if (prMeta.baseRefName === "master" && run.conclusion === "success") {
      await surfaceAwaitingApproval(prNumber, null, true);
      console.log(
        `[bridge] Release PR #${prNumber} (${prMeta.headRefName} -> master) passed CI; surfaced in Awaiting Approval for human owner.`
      );
      return;
    }

    if (run.conclusion === "failure") {
      if (prMeta.hasFableEscalated) {
        console.log(`[bridge] PR #${prNumber} failed CI after fable-escalated pass. Stopping for human.`);
        await addBlockedLabel(prNumber, run.id, prMeta.linkedIssue);
        enqueueArchitectPrompt(
          [
            `[GITHUB EVENT: CI FAILED AFTER FABLE PASS — STOP] PR #${prNumber} failed CI run #${run.id} and already has \`fable-escalated\`.`,
            `Per AGENTS.md Section 6, DO NOT re-invoke \`${FABLE_PANE}\`. Inspect \`gh run view ${run.id} --log-failed\`, post a concise summary, and wait for the human owner.`,
          ].join("\n"),
          { priority: PRIORITY.CI_URGENT, kind: "ci_fable_stop", threadKey: `pr:${prNumber}` }
        );
        return;
      }

      const currentCount = (state.prRetries[key] || 0) + 1;
      state.prRetries[key] = currentCount;
      saveRetryState(state);

      if (currentCount > MAX_CI_RETRIES) {
        console.log(`[bridge] PR #${prNumber} exceeded max CI retries (${MAX_CI_RETRIES}). Escalating.`);
        await addBlockedLabel(prNumber, run.id, prMeta.linkedIssue);
        enqueueArchitectPrompt(
          [
            `[GITHUB EVENT: CI ESCALATION — BLOCKED] PR #${prNumber} failed CI run #${run.id} (Attempt ${currentCount}/${MAX_CI_RETRIES}).`,
            `The PR and Project Board card have been set to \`Blocked\`.`,
            `Action required:`,
            `1. Inspect \`gh run view ${run.id} --log-failed\` to diagnose root cause.`,
            `2. Per AGENTS.md Section 6, either wait for human guidance OR (if clearly solvable in one pass) label \`fable-escalated\`, set board Worker to \`Fable\`, and dispatch ONE capped rescue pass to \`${FABLE_PANE}\`.`,
          ].join("\n"),
          { priority: PRIORITY.CI_URGENT, kind: "ci_blocked", threadKey: `pr:${prNumber}` }
        );
      } else {
        enqueueArchitectPrompt(
          [
            `[GITHUB EVENT: CI FAILED — SELF-HEAL ${currentCount}/${MAX_CI_RETRIES}] PR #${prNumber} (branch: ${prMeta.headRefName}) failed CI run #${run.id}.`,
            `Action required:`,
            `1. Run \`gh run view ${run.id} --log-failed\` to inspect the failure.`,
            `2. Check \`herdr agent list\` and dispatch the exact error + fix instructions to the routine worker assigned to PR #${prNumber} (or overflow to \`worker-qwen\` if \`worker-gemini\` is quota-limited) so it fixes root cause (never weakening/skipping tests) and pushes.`,
          ].join("\n"),
          { priority: PRIORITY.CI_URGENT, kind: "ci_self_heal", threadKey: `pr:${prNumber}` }
        );
      }
      return;
    }

    if (run.conclusion === "success") {
      if (state.prRetries[key]) {
        delete state.prRetries[key];
        saveRetryState(state);
      }

      if (prMeta.isConflicting) {
        if (prMeta.linkedIssue) {
          await syncBoardField(prMeta.linkedIssue, "Status", "In Review");
        }
        const conflictStep = prMeta.hasFableEscalated
          ? `PR #${prNumber} already used \`fable-escalated\` and still has conflicts — mark \`blocked\` and wait for human input.`
          : `DO NOT debug the merge conflict yourself. Label PR #${prNumber} \`fable-escalated\`, set board Worker to \`Fable\`, and dispatch \`${FABLE_PANE}\` via \`herdr agent prompt\` to resolve conflicts on branch \`${prMeta.headRefName}\` against \`origin/staging\`, pass local tests, and push.`;

        enqueueArchitectPrompt(
          [
            `[GITHUB EVENT: MERGE CONFLICT DETECTED] PR #${prNumber} (branch: ${prMeta.headRefName}) passed CI run #${run.id} but has merge conflicts against \`staging\`.`,
            `Action required: ${conflictStep}`,
          ].join("\n"),
          { priority: PRIORITY.CI_URGENT, kind: "merge_conflict", threadKey: `pr:${prNumber}` }
        );
        return;
      }

      if (prMeta.humanGateBlocked || prMeta.hasHumanGateLabel) {
        // Auto-badge purple `human-gate`, request formal human review, & move card directly to `Awaiting Approval`
        await surfaceAwaitingApproval(prNumber, prMeta.linkedIssue, prMeta.baseRefName === "master");

        enqueueArchitectPrompt(
          [
            `[GITHUB EVENT: CI PASSED — MOVED TO AWAITING APPROVAL (HUMAN GATE GUARD)] PR #${prNumber} passed "${run.name}" (run #${run.id}), is badged \`human-gate\`, has requested human review, and is now in the Kanban \`Awaiting Approval\` column.`,
            `Action required:`,
            `1. Inspect diff, test integrity, & visual evidence via \`gh pr view ${prNumber} --comments\` and \`gh pr diff ${prNumber}\`. For UI/E2E PRs, run \`/workspace/.factory/fetch-evidence.sh ${run.id} ${prNumber}\` and inspect the downloaded PNG paths with Hermes vision (apply \`pr-evidence-review\` skill).`,
            `2. Post structured review comments (\`gh pr review ${prNumber} --comment --body "**[Architect]** ..."\`) summarizing safety, test coverage, migration/auth checks, and visual evidence.`,
            `3. STOP — do NOT attempt to approve or merge. Wait for the human owner to click Approve (unlocking \`human-gate-guard\`) and Merge manually.`,
          ].join("\n"),
          { priority: PRIORITY.REVIEW_WAVE, kind: "ci_human_gate", threadKey: `pr:${prNumber}` }
        );
        return;
      }

      if (prMeta.linkedIssue) {
        await syncBoardField(prMeta.linkedIssue, "Status", "In Review");
      }

      enqueueArchitectPrompt(
        [
          `[GITHUB EVENT: CI & HUMAN-GATE-GUARD PASSED] PR #${prNumber} passed "${run.name}" (run #${run.id}) with no protected-path or \`human-gate\` lock.`,
          `Action required:`,
          `1. Review diff, Test Plan coverage, anti-tampering rules, & visual evidence via \`gh pr view ${prNumber} --comments\` and \`gh pr diff ${prNumber}\`. For UI/E2E PRs, run \`/workspace/.factory/fetch-evidence.sh ${run.id} ${prNumber}\` and inspect the downloaded local PNG paths with Hermes vision (apply \`pr-evidence-review\` skill).`,
          `2. If mergeable status is \`CONFLICTING\` / \`DIRTY\` (and not yet \`fable-escalated\`), escalate to \`${FABLE_PANE}\` per AGENTS.md Section 6.`,
          `3. If the diff unexpectedly touches sensitive security/schema logic outside protected paths, add \`human-gate\`, move the linked card to \`Awaiting Approval\`, comment, and STOP. If tests were skipped/weakened, request changes from the worker. Otherwise, if clean: formally approve (\`gh pr review ${prNumber} --approve --body "**[Architect]** LGTM — merging to staging."\`) and squash-merge (\`gh pr merge ${prNumber} --squash --delete-branch\`).`,
        ].join("\n"),
        { priority: PRIORITY.REVIEW_WAVE, kind: "ci_passed", threadKey: `pr:${prNumber}` }
      );
    }
  }
}

// Persist any buffered debounce comments before shutdown so restarts never lose events
function flushAllBeforeExit(signal) {
  console.log(`[bridge] Received ${signal} — flushing ${pendingComments.size} buffered comment thread(s) to disk...`);
  for (const threadKey of [...pendingComments.keys()]) {
    flushHumanCommentThread(threadKey);
  }
  saveQueueToDisk();
  process.exit(0);
}
process.on("SIGINT", () => flushAllBeforeExit("SIGINT"));
process.on("SIGTERM", () => flushAllBeforeExit("SIGTERM"));

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(
      JSON.stringify({
        ok: true,
        stack: "herdr-software-factory",
        repo: REPO_FULL || "auto",
        architectPane: ARCHITECT_PANE,
        fablePane: FABLE_PANE,
        humanReviewer: HUMAN_REVIEWER || "unset",
        projectBoard: PROJECT_NUMBER || "disabled",
        processing,
        activeTurn: currentItemSummary,
        queued: queue.length,
        coalescingThreads: pendingComments.size,
        stallThresholdMins: Math.round(STALL_THRESHOLD_MS / 60_000),
        stateDir: STATE_DIR,
      })
    );
    return;
  }

  if (req.method !== "POST" || req.url !== "/webhook") {
    res.writeHead(404);
    res.end("Not Found");
    return;
  }

  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const rawBody = Buffer.concat(chunks);
    const sig = req.headers["x-hub-signature-256"];

    if (!verifySignature(rawBody, sig)) {
      console.warn("[bridge] Rejected request with invalid HMAC signature.");
      res.writeHead(401);
      res.end("Invalid signature");
      return;
    }

    const event = req.headers["x-github-event"];
    let payload;
    try {
      payload = JSON.parse(rawBody.toString("utf8"));
    } catch {
      res.writeHead(400);
      res.end("Invalid JSON");
      return;
    }

    res.writeHead(202, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ received: event }));

    handleEvent(event, payload).catch((err) => {
      console.error("[bridge] Error handling event:", err);
    });
  });
});

server.listen(PORT, BIND_HOST, () => {
  console.log(
    `[bridge] Listening on http://${BIND_HOST}:${PORT}/webhook (Architect: "${ARCHITECT_PANE}", Fable: "${FABLE_PANE}", Reviewer: @${HUMAN_REVIEWER || "unset"}, Project: #${PROJECT_NUMBER || "none"}, RecoveredQueue: ${queue.length}, Coalesce: ${COMMENT_COALESCE_MS}ms, Watchdog: ${Math.round(STALL_WATCHDOG_INTERVAL_MS / 60_000)}m)`
  );
  if (queue.length > 0) {
    console.log(`[bridge] Resuming ${queue.length} persisted queue item(s) from ${QUEUE_STATE_FILE}...`);
    drainQueue();
  }
  if (STALL_WATCHDOG_INTERVAL_MS > 0) {
    setInterval(runStallWatchdog, STALL_WATCHDOG_INTERVAL_MS);
  }
});
```

### 8.2 Create 1-Command Native Herdr Launcher & Seed Prompt (`.factory/architect-seed.md` & `.factory/launch-panes.sh`)
Store the Architect seed prompt in Git and launch all 5 native Herdr tabs cleanly inside the running `herdr server` using verified Herdr v0.9.5 commands (`workspace create`, `tab create`, `pane run`, `agent start`, `agent rename`, and per-command `HERDR_AGENT=` hints—never nested inside `tmux`). Re-running `.factory/launch-panes.sh` after detaching simply reattaches to the live Herdr UI without duplicating tabs.

**File 1: `.factory/architect-seed.md`**
```markdown
You are the persistent Architect (`factory-architect[bot]`) inside the execution-free `herdr-software-factory` hub.

1. Run `/workspace/.factory/sync-hub.sh` and read `AGENTS.md` and `DECISIONS.md` now.
2. Run `herdr agent list` to verify live native Herdr status (`idle`/`working`/`blocked`/`done`) for `worker-gemini`, `worker-qwen`, and the on-demand Claude Code escalation agent `specialist-fable` (refer to your installed `herdr` skill for native Herdr commands).
3. Follow `AGENTS.md` strictly:
   - Never forward vague or multi-part Issues straight to workers: decompose `plan` requests into native Sub-Issues via `.factory/sub-issue.sh` (including a concrete `Test Plan` in every Sub-Issue and a Final-Wave E2E Verification Sub-Issue for multi-layer features), remove `plan`, and pause for human approval before dispatching Wave 1.
   - Before every dispatch, verify worker availability via BOTH `herdr agent list` (confirm `idle`/`done`, never `working`/`blocked`) AND `gh issue list --label in-progress --state open` (strictly 1 unique Sub-Issue per idle worker container per PR).
   - If `[GITHUB EVENT: STAGING BROKEN]` arrives, pause merging new PRs into `staging`, inspect the failing post-merge run, and dispatch a hotfix immediately.
   - If any worker shows `blocked` in `herdr agent list` or triggers `[GITHUB EVENT: STALL WATCHDOG]`, inspect its terminal output via `herdr agent read <worker> --source visible --lines 40` before intervening or alerting the human.
   - Dispatch Final-Wave E2E Sub-Issues in a **fresh, stateless session** (defaulting to `worker-gemini`, or `worker-qwen` only for narrow 1-2 screen cross-model flows) using `.agents/skills/e2e-testing/SKILL.md`.
   - For UI/E2E PR reviews, download Playwright screenshots locally via `/workspace/.factory/fetch-evidence.sh <run_id> <pr_num>` before inspecting them with Hermes `auxiliary.vision`, and enforce strict anti-test-tampering audits via `pr-evidence-review`.
   - When an Epic closes on `staging`, run `.factory/release-pr.sh <epic_num>` to open/update the single rolling `staging -> master` Release PR in `Awaiting Approval`.
   - Respect `human-gate-guard` server locks (leaving `Awaiting Approval` PRs for manual human Approve & Merge) and reserve `specialist-fable` strictly for merge conflicts, 1-shot blocked rescues, and manual human-gate audits.

Wait for live instructions from me or incoming `[GITHUB EVENT]` webhook prompts.
```

**File 2: `.factory/launch-panes.sh`** (`chmod +x .factory/launch-panes.sh`)
```bash
#!/usr/bin/env bash
# 1-command native Herdr workspace launcher & re-attacher inside `herdr-hub`
# Uses HERDR_AGENT=<kind> on SSH wrappers so all 4 agents show native idle/working/blocked/done status!
# Usage (from host): docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh
set -euo pipefail

source /workspace/.factory/enter-role.sh architect
/workspace/.factory/sync-hub.sh || true

# Wait briefly for headless `herdr server` (container PID 1) to accept API calls
for _ in $(seq 1 20); do
  herdr api snapshot >/dev/null 2>&1 && break
  sleep 0.5
done

# If the `factory` workspace already exists (e.g. reattaching after ctrl+b q), attach directly without duplicating tabs
EXISTING_WS="$(herdr api snapshot | jq -r '.result.workspaces[]? | select(.label == "factory") | .workspace_id' | head -n1 || true)"
if [ -n "$EXISTING_WS" ]; then
  echo "[launch-panes] Workspace 'factory' (${EXISTING_WS}) already running — attaching to Herdr UI..."
  exec herdr
fi

echo "[launch-panes] Bootstrapping native Herdr workspace 'factory' with 5 tabs..."

# 1. Create workspace + root tab for `bridge` (ordinary terminal process, not an AI agent)
WS_JSON="$(herdr workspace create --cwd /workspace --label factory --focus)"
WS_ID="$(echo "$WS_JSON" | jq -r '.result.workspace.workspace_id')"
BRIDGE_TAB="$(echo "$WS_JSON" | jq -r '.result.tab.tab_id')"
BRIDGE_PANE="$(echo "$WS_JSON" | jq -r '.result.root_pane.pane_id')"
herdr tab rename "$BRIDGE_TAB" bridge >/dev/null
herdr pane rename "$BRIDGE_PANE" bridge >/dev/null
herdr pane run "$BRIDGE_PANE" "node /workspace/.factory/webhook-bridge.mjs" >/dev/null

# 2. Tab: `architect` — native local Hermes agent via `herdr agent start`
ARCH_TAB="$(herdr tab create --workspace "$WS_ID" --cwd /workspace --label architect --focus)"
ARCH_PANE="$(echo "$ARCH_TAB" | jq -r '.result.root_pane.pane_id')"
herdr pane rename "$ARCH_PANE" architect >/dev/null
herdr agent start architect --kind hermes --pane "$ARCH_PANE" -- --profile architect >/dev/null

# Helper to launch an SSH-sandboxed remote worker tab with Herdr's official HERDR_AGENT=<kind> wrapper hint
launch_ssh_agent_tab() {
  local name="$1"
  local kind="$2"
  local remote_cmd="$3"

  local tab_json pane_id
  tab_json="$(herdr tab create --workspace "$WS_ID" --cwd /workspace --label "$name" --no-focus)"
  pane_id="$(echo "$tab_json" | jq -r '.result.root_pane.pane_id')"
  herdr pane rename "$pane_id" "$name" >/dev/null
  # Set HERDR_AGENT strictly on the foreground ssh wrapper (never globally) so Herdr applies the screen manifest
  herdr pane run "$pane_id" "HERDR_AGENT=${kind} ssh -t ${name} '${remote_cmd}'" >/dev/null

  # Wait briefly for SSH + CLI boot so Herdr detects the agent, then assign stable unique name
  for _ in $(seq 1 20); do
    if herdr agent rename "$pane_id" "$name" >/dev/null 2>&1; then
      echo "[launch-panes] Registered native Herdr agent '${name}' (${kind}) on pane ${pane_id}."
      return 0
    fi
    sleep 1
  done
  echo "[launch-panes] Note: '${name}' (${pane_id}) still booting over SSH — run 'herdr agent rename ${pane_id} ${name}' once its prompt appears."
}

# 3. Tab: `worker-gemini` — Antigravity CLI over internal SSH (`HERDR_AGENT=antigravity-cli`)
launch_ssh_agent_tab "worker-gemini" "antigravity-cli" "agy"

# 4. Tab: `worker-qwen` — Local Qwen Hermes over internal SSH (`HERDR_AGENT=hermes`)
launch_ssh_agent_tab "worker-qwen" "hermes" "hermes --profile qwen"

# 5. Tab: `specialist-fable` — On-Demand Claude Code over internal SSH (`HERDR_AGENT=claude`)
FABLE_CMD="claude"
[ -n "${FABLE_MODEL:-}" ] && FABLE_CMD="claude --model \"${FABLE_MODEL}\""
launch_ssh_agent_tab "specialist-fable" "claude" "$FABLE_CMD"

# Seed the Architect once it settles to idle
echo "[launch-panes] Waiting for 'architect' to reach idle and sending /workspace/.factory/architect-seed.md..."
if herdr agent wait architect --until idle --until done --timeout 30000 >/dev/null 2>&1; then
  herdr agent prompt architect "$(cat /workspace/.factory/architect-seed.md)" >/dev/null || true
else
  echo "[launch-panes] Tip: Once architect settles, run: herdr agent prompt architect \"\$(cat /workspace/.factory/architect-seed.md)\""
fi

echo "[launch-panes] Native Herdr agents active:"
herdr agent list || true
exec herdr
```

### 8.3 Create `bridge.env` & Single-File Model/Inference/Postgres Control (`compose.env`)
Run on the host. **`compose.env` is your single control panel** for models, vision models, local GPU inference URLs, Postgres passwords, and Claude Code auth mode:

```bash
REPO_FULL=$(gh repo view --json nameWithOwner -q .nameWithOwner)
GH_OWNER_LOGIN=$(gh api user -q .login)
SECRET=$(openssl rand -hex 32)
ARCH_PROXY_TOK="proxy-arch-$(openssl rand -hex 12)"
FABLE_PROXY_TOK="proxy-fable-$(openssl rand -hex 12)"

PG_ADMIN_PW=$(openssl rand -hex 16)
PG_GEMINI_PW=$(openssl rand -hex 16)
PG_QWEN_PW=$(openssl rand -hex 16)
PG_FABLE_PW=$(openssl rand -hex 16)

PROJECT_OWNER="${PROJECT_OWNER:-@me}"
PROJECT_NUMBER="${PROJECT_NUMBER:-$(gh project list --owner "$PROJECT_OWNER" --format json -q '.projects[] | select(.title | contains("Light Factory")) | .number' 2>/dev/null | head -n1 || true)}"

cat <<EOF > ~/.config/light-factory/bridge.env
WEBHOOK_PORT=8787
GITHUB_WEBHOOK_SECRET=${SECRET}
HUMAN_REVIEWER=${GH_OWNER_LOGIN}
ARCHITECT_PANE=architect
FABLE_PANE=specialist-fable
MAX_CI_RETRIES=3
CI_WORKFLOW_NAME=CI & PR Evidence
BRIDGE_STATE_DIR=/home/factory/.config/herdr/bridge-state
COMMENT_COALESCE_MS=8000
ARCHITECT_WAIT_TIMEOUT_MS=300000
ARCHITECT_IDLE_POLL_MS=5000
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
# Switch to pgvector/pgvector:pg16 if your app uses vector embeddings
POSTGRES_IMAGE=postgres:16-alpine
POSTGRES_ADMIN_PASSWORD=${PG_ADMIN_PW}
POSTGRES_GEMINI_PASSWORD=${PG_GEMINI_PW}
POSTGRES_QWEN_PASSWORD=${PG_QWEN_PW}
POSTGRES_FABLE_PASSWORD=${PG_FABLE_PW}

# === Architect (Hermes via zero-key llm-proxy) ===
# Edit model names here; edit upstream URL & API key in ~/.config/light-factory/llm-secrets.env
ARCHITECT_MODEL=glm-5.3
ARCHITECT_VISION_MODEL=glm-5.3-flash
EXTRA_ALLOWED_MODELS=
ARCHITECT_PROXY_TOKEN=${ARCH_PROXY_TOK}

# === Worker Qwen (Hermes -> Local GPU Inference Server) ===
# Examples: Ollama=http://host.docker.internal:11434/v1 | vLLM/llama.cpp=http://host.docker.internal:8000/v1
QWEN_INFERENCE_URL=http://host.docker.internal:11434/v1
QWEN_MODEL=qwen3.8:27b
QWEN_API_KEY=local-not-needed

# === Specialist Fable (Claude Code) ===
# FABLE_AUTH_MODE: "oauth" (for `claude login` inside specialist-fable) OR "proxy" (if using ANTHROPIC_API_KEY in llm-secrets.env)
FABLE_AUTH_MODE=oauth
FABLE_MODEL=
FABLE_PROXY_TOKEN=${FABLE_PROXY_TOK}
EOF
chmod 600 ~/.config/light-factory/compose.env

echo "Generated bridge.env (HUMAN_REVIEWER=${GH_OWNER_LOGIN}) & compose.env — instruct human to copy GITHUB_WEBHOOK_SECRET from ~/.config/light-factory/bridge.env for Phase 9."
```

> **Quick-Swap Cheat Sheet (Anytime Later):**
> - **Change Architect model or Vision model:** Edit `ARCHITECT_MODEL` / `ARCHITECT_VISION_MODEL` in `~/.config/light-factory/compose.env` (and `GLM_UPSTREAM_URL` / `VISION_UPSTREAM_URL` / keys in `llm-secrets.env` if changing providers) -> run `./.factory/preflight.sh && docker compose --env-file ~/.config/light-factory/compose.env up -d --force-recreate llm-proxy herdr-hub` -> recover all 5 tabs in 1 command via `docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh`.
> - **Change Local Qwen server or model:** Edit `QWEN_INFERENCE_URL` / `QWEN_MODEL` in `~/.config/light-factory/compose.env` -> run `docker compose --env-file ~/.config/light-factory/compose.env up -d --force-recreate worker-qwen`.
> - **Add a new domain skill (e.g., Chrome official web skill, framework guide):** Drop `<skill-name>/SKILL.md` into `.agents/skills/` and push to `staging`; every container picks it up automatically via `.factory/sync-skills.sh`.

### 8.4 Create Host Preflight Script (`.factory/preflight.sh`)
Create `.factory/preflight.sh` (`chmod +x .factory/preflight.sh`).
Prevents the classic Docker bind-mount trap where starting Compose before a host secret file exists silently creates an empty **directory** at that path—and validates `docker compose config` before launching containers.

```bash
#!/usr/bin/env bash
# Host preflight validator — run before `docker compose up`
set -euo pipefail

CONFIG_DIR="${HOME}/.config/light-factory"
REQUIRED_FILES=(
  "${CONFIG_DIR}/apps.env"
  "${CONFIG_DIR}/llm-secrets.env"
  "${CONFIG_DIR}/bridge.env"
  "${CONFIG_DIR}/compose.env"
  "${CONFIG_DIR}/keys/architect.pem"
  "${CONFIG_DIR}/keys/worker.pem"
  "${CONFIG_DIR}/internal-ssh/id_ed25519"
  "${CONFIG_DIR}/internal-ssh/authorized_keys"
)

FAIL=0
echo "[preflight] Checking host secret vault in ${CONFIG_DIR}..."

for f in "${REQUIRED_FILES[@]}"; do
  if [ -d "$f" ]; then
    echo "  ❌ ${f} is a DIRECTORY (likely auto-created by Docker!). Remove with 'rm -rf \"${f}\"' and create the file." >&2
    FAIL=1
  elif [ ! -f "$f" ] || [ ! -s "$f" ]; then
    echo "  ❌ Missing or empty required file: ${f}" >&2
    FAIL=1
  else
    echo "  ✅ ${f}"
  fi
done

for cfg in "${CONFIG_DIR}/apps.env" "${CONFIG_DIR}/llm-secrets.env"; do
  if [ -f "$cfg" ] && grep -q '<paste_' "$cfg"; then
    echo "  ❌ Placeholder '<paste_...>' still present in ${cfg}" >&2
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "[preflight] FAILED — fix the items above before running docker compose up." >&2
  exit 1
fi

echo "[preflight] Validating docker-compose.yml syntax with compose.env..."
docker compose --env-file "${CONFIG_DIR}/compose.env" config -q
echo "[preflight] ✅ All host files, secrets, and Compose configuration verified!"
```

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
>      - `Workflow runs` *(handles PR `CI & PR Evidence`, post-merge `staging` regression alerts, `Awaiting Approval` surfacing & Fable conflict escalation)*
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
You will see one unified project **`herdr-software-factory`** with 7 healthy running containers (`auth-minter`, `llm-proxy`, `factory-postgres`, `herdr-hub`, `worker-gemini`, `worker-qwen`, `specialist-fable`).
- **`herdr-hub`** boots directly into headless `herdr server`, auto-configuring Hermes, `herdr --skill`, and all Architect skills—while **`worker-qwen`**, **`factory-postgres`**, and **Playwright Chromium** auto-configure on boot!

### 10.2 One-Time OAuth Logins (Subscription CLIs Only)
> **[HUMAN ACTION REQUIRED]**
> Complete one-time interactive OAuth logins strictly inside the two subscription-based containers (credentials persist inside their private Docker volumes and never touch your host `$HOME`):
>
1. **Gemini Worker (`worker-gemini` -> `gemini-auth` volume — Antigravity Gemini 3.8 Flash):**
```bash
docker compose exec -it worker-gemini bash
agy login   # Complete Google AI Pro OAuth flow; persists in gemini-auth volume
exit
```
2. **Fable Specialist (`specialist-fable` -> `fable-auth` volume — Claude Code):**
   - **If `FABLE_AUTH_MODE=oauth` (default — friend's Claude Code login):**
```bash
docker compose exec -it specialist-fable bash
claude login   # Persists strictly inside fable-auth (/home/factory/.claude)
exit
```
   - **If `FABLE_AUTH_MODE=proxy` (friend's Anthropic API key in `llm-secrets.env`):** No login needed—Claude Code automatically routes through `http://llm-proxy:4000/anthropic` with a dummy key!

### 10.3 Launch the Native 5-Tab Herdr Workspace (1-Command Recovery & Handoff)

> **[HUMAN ACTION REQUIRED — Factory Handoff]**
> Run the 1-command launcher on your GPU host (or over SSH from your laptop/phone):

```bash
docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh
```
>
> This automatically creates the native Herdr `factory` workspace with 5 tabs (`bridge`, `architect`, `worker-gemini`, `worker-qwen`, `specialist-fable`), attaches per-command `HERDR_AGENT=` hints to all 3 SSH workers, seeds `architect` from `/workspace/.factory/architect-seed.md`, and opens the live Herdr UI.
>
> * **Detach anytime without stopping agents:** Press `ctrl+b q` (all 5 tabs and `herdr server` keep running in the background inside `herdr-hub`).
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

# 3. Verify all 4 agents appear natively in Herdr with live states (idle/working/blocked/done)
docker compose exec herdr-hub herdr agent list
```

---

## Phase 11: End-to-End Verification & Smoke Tests

Run these 8 verification checks before handing the factory real production Epics.

### Test 0 — Preflight, Zero-Trust Isolation, Postgres Isolation & Skills Check
1. **Host Preflight:** Run `./.factory/preflight.sh` on the host — must exit `0` with all 8 secret/config files green.
2. **Zero Raw Secrets & Zero `docker.sock`:**
   ```bash
   docker compose exec herdr-hub bash -lc 'test ! -e /var/run/docker.sock && test ! -e /run/factory-keys && ! env | grep -qiE "GLM_API_KEY|ANTHROPIC_API_KEY"'
   docker compose exec worker-gemini bash -lc 'test ! -e /run/factory-auth/architect && ! curl -s --max-time 2 http://llm-proxy:4000/health'
   ```
   *(Both commands must exit `0`: `herdr-hub` has no `docker.sock` or real API keys; `worker-gemini` cannot read Architect tokens or reach `llm-proxy`.)*
3. **Database & Execution-Free Hub Isolation:**
   ```bash
   # herdr-hub must NOT be able to reach factory-postgres (no db-net route)
   docker compose exec herdr-hub bash -lc '! getent hosts factory-postgres'
   # worker-gemini CAN connect to app_gemini and reset public schema, but CANNOT connect to app_qwen
   docker compose exec worker-gemini bash -lc 'psql "$DATABASE_URL" -c "SELECT current_database(), current_user;" && ! psql "${DATABASE_URL%app_gemini}app_qwen" -c "SELECT 1;"'
   ```
4. **Skills Synced Properly:** Confirm `herdr-hub` has `.agents/skills/*`, `pr-evidence-review`, AND `herdr/SKILL.md` in `~/.hermes/skills/`; confirm `worker-qwen` has ONLY shared `.agents/skills/*` (`modern-web-standards`, `postgres-migrations`, `e2e-testing`).

### Test 1 — Native Herdr Visibility Over Internal SSH (`HERDR_AGENT=`)
1. Inside `herdr-hub`, run `herdr agent list`.
2. Confirm all 4 agents (`architect`, `worker-gemini`, `worker-qwen`, `specialist-fable`) appear with real-time states (`idle` / `done` / `working` / `blocked`) rather than plain dumb terminals.
3. Confirm `specialist-fable` remains completely idle.

### Test 2 — Plan-First Epic Decomposition (`plan` -> Sub-Issues + Test Plans -> Pause)
1. Open a multi-part test Feature Request Issue on GitHub and apply the **`plan`** label.
2. Verify `webhook-bridge` syncs `/workspace` via `.factory/sync-hub.sh`, enqueues `plan_request`, and wakes `architect`.
3. Verify the Architect:
   * Creates atomic child Issues (each with an explicit **Test Plan** and a **Final-Wave E2E Verification** Sub-Issue if multi-layer).
   * Links them natively via `.factory/sub-issue.sh link` (Sub-Issues progress bar appears on the parent Issue).
   * Removes `plan`, posts a `**[Architect]**` Wave Blueprint, and **STOPS** without dispatching any worker.

### Test 3 — Routine Build Wave -> Local Evidence -> Auto-Merge to `staging` + Post-Merge `staging` CI
1. Apply **`ready`** to the approved Epic (or a tiny routine standalone Issue touching non-protected files).
2. Verify the Architect checks `herdr agent list` + `in-progress` occupancy, swaps `ready` -> `in-progress`, updates the Kanban board (`In Progress` + `Worker`), and dispatches **1 unique Sub-Issue** to an idle worker (`worker-gemini` or `worker-qwen`).
3. Verify the worker runs `.factory/prep-branch.sh` (clean Postgres schema reset), implements the slice + tests, and opens a PR targeting `staging` with `Closes #<sub_issue>`.
4. Verify `CI & PR Evidence` passes against clean-room Postgres 16 AND `human-gate-guard` publishes green Commit Status on `pr.head.sha`.
5. For UI/E2E PRs, confirm the Architect runs `.factory/fetch-evidence.sh <run_id> <pr_num>` and inspects downloaded PNGs with Hermes Vision (`llm-proxy` `/stats` shows `/glm` and `/vision` token counts incrementing).
6. Verify the Architect approves and squash-merges to `staging`, **post-merge `CI & PR Evidence` runs automatically on `push` to `staging`**, and the Sub-Issue moves to `Done`.

### Test 4 — Turn-Serialized Priority Wait-Queue & 8-Second Comment Coalescer
1. Post **2 rapid comments** (2–3 seconds apart) on the **same** open Issue or PR. Confirm `bridge` logs show them bundled into **1** combined `[GITHUB EVENT: HUMAN COMMENTS (2 bundled...)]` prompt instead of waking the Architect twice.
2. While the Architect is actively `working` on Issue A, post a comment on Issue B. Confirm `bridge` persists Issue B to `architect-queue.json`, waits for `herdr agent wait architect --until idle --until done`, and dispatches Issue B **strictly after** Issue A finishes (with `HUMAN_COMMENT` jumping ahead of any lower-priority queued background events).

### Test 5 — `Awaiting Approval` Board Column & Tamper-Proof `human-gate-guard`
1. Open a small test PR from `factory-worker[bot]` touching a protected path (e.g., `migrations/test.sql` or `auth/README.md`) **without** manually adding `human-gate`.
2. Verify:
   * `human-gate-guard` runs from trusted `master` and posts a red `failure` Commit Status directly onto `pr.head.sha`.
   * `webhook-bridge` automatically adds the purple **`human-gate`** label to the PR & linked Issue, formally requests **you** as a PR Reviewer, and moves the card to **`Awaiting Approval`** on the Project Board.
   * The Architect posts structured `**[Architect]**` review comments and **STOPS** (and any bot merge attempt is physically rejected by GitHub Ruleset #1).
3. Click **Approve** in the GitHub PR UI. Verify `human-gate-guard` flips to **green `success`** on `pr.head.sha` within ~10 seconds—then **you** click **Squash and merge** manually (keeping your GitHub username as official merger).

### Test 6 — Final-Wave Stateless E2E Verification & Rolling `staging -> master` Release PR
1. After all build waves of a multi-layer Epic merge to `staging`, confirm the Architect dispatches the **Final-Wave E2E Verification** Sub-Issue to a **fresh, stateless session** (default `worker-gemini`, or `worker-qwen` only for narrow 1–2 screen flows) using `.agents/skills/e2e-testing/SKILL.md`.
2. Confirm the worker runs Playwright locally against its isolated `$DATABASE_URL` (using preinstalled Chromium deps), passes CI, and merges to `staging`.
3. Once `completed === total` Sub-Issues, verify the Architect closes the parent Epic and runs `.factory/release-pr.sh <epic_num>`, opening/updating **one** rolling `staging -> master` Release PR that:
   * Carries the purple `human-gate` label,
   * Formally requests **you** as Reviewer,
   * Appears directly in the Kanban **`Awaiting Approval`** column.
4. Click **Approve** on the Release PR, wait ~10s for `human-gate-guard` to flip green, and merge using **"Create a merge commit"** (**never Squash**) so `staging` and `master` stay cleanly aligned. Confirm the Release PR card auto-moves to **`Done`**.

### Test 7 — On-Demand Fable Escalation Cap (`fable-escalated`)
1. Confirm `specialist-fable` was **never** woken during Tests 2–6.
2. *(Optional drill)* Force a merge conflict against `staging` on a throwaway PR: verify `bridge` detects `CONFLICTING`/`DIRTY`, Architect adds `fable-escalated` + sets board `Worker: Fable`, dispatches `specialist-fable` once, Fable resolves cleanly and pushes, and if CI fails again afterward, `bridge` stops and marks `blocked` without looping Fable.

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
* **Check Proxied API Spend (`GLM-5.3`, `GLM-5.3-Flash Vision`, optional Fable proxy):**
  ```bash
  docker compose exec herdr-hub curl -s http://llm-proxy:4000/stats | jq .
  ```
* **Check Live Queue & Watchdog Status:**
  ```bash
  curl -s http://127.0.0.1:8787/health | jq .
  ```
* **Compact Architect Between Epics:** After shipping an Epic, ask the Architect to log key decisions in `DECISIONS.md` and compact/reset its chat session to keep GLM-5.3 prompt caching fast and cheap.
* **Hot-Swap Models Anytime:** Edit `~/.config/light-factory/compose.env` (and `llm-secrets.env` if changing providers), run `./.factory/preflight.sh`, recreate `llm-proxy` / `herdr-hub` (or `worker-qwen`), and run `launch-panes.sh`.
