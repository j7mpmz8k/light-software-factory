# Light Software Factory — Setup & Quickstart Guide

This guide walks you through setting up and launching the **7-container Light Software Factory (A1 + B2)** on a Linux server or GPU host.

---

## 1. Prerequisites

Before starting, ensure your host machine has:
* **Linux OS** (Ubuntu 22.04+, Debian 12+, Arch, Fedora, etc.)
* **Docker & Docker Compose v2** (`docker compose version` >= 2.20) or rootless Podman with Compose v2
* **Git** and **GitHub CLI (`gh`)** (`gh auth login`)
* **Google AI Ultra 5x** account (for `worker-agy` running Antigravity CLI)
* **GLM-5.3 API key** (for `herdr-hub` Architect/Orchestrator + `worker-glm` backup)
* *(Optional for free local worker)*: **GPU with Ollama or vLLM** serving `qwen3.8:27b` on port 11434 or 8000.

---

## 2. Step 1: Initialize Host Vault & Internal SSH Keys

Clone this repository and run the host initialization helper:

```bash
git clone https://github.com/<your-username>/<your-repo-name>.git
cd <your-repo-name>
chmod +x .factory/*.sh .factory/bin/gh .factory/postgres/*.sh .factory/docker/*.sh

# Initializes ~/.config/light-factory and generates internal SSH keys
./.factory/init-host.sh
```

This creates:
- `~/.config/light-factory/keys/`
- `~/.config/light-factory/internal-ssh/id_ed25519` (dedicated internal SSH key for `herdr-hub` -> worker containers)
- `~/.config/light-factory/internal-ssh/authorized_keys`

---

## 3. Step 2: Register Two Private GitHub Apps

The factory uses two private GitHub Apps so agent actions are role-isolated and audited under bot identities:

1. **Architect App (`factory-architect`):**
   - Repository permissions: `Issues: Read & Write`, `Pull Requests: Read & Write`, `Contents: Read & Write`.
   - Generates `.pem` private key -> save as `~/.config/light-factory/keys/architect.pem` (`chmod 600`).
   - Note the **App ID**, **Installation ID**, and **Slug**.

2. **Worker App (`factory-worker`):**
   - Repository permissions: `Contents: Read & Write` (pushes code to `feature/*` branches), `Pull Requests: Read & Write`.
   - Generates `.pem` private key -> save as `~/.config/light-factory/keys/worker.pem` (`chmod 600`).
   - Note the **App ID**, **Installation ID**, and **Slug**.

---

## 4. Step 3: Populate Configuration Files

Reference the provided templates in `.factory/templates/` to create your 4 configuration files:

```bash
# 1. GitHub App credentials
cp .factory/templates/apps.example ~/.config/light-factory/apps.env

# 2. GLM-5.3 API key & hourly spend caps (mounted ONLY into llm-proxy)
cp .factory/templates/llm-secrets.example ~/.config/light-factory/llm-secrets.env

# 3. Master Compose environment (models, Postgres passwords for app_agy/app_qwen/app_glm, repo name)
cp .factory/templates/compose.example ~/.config/light-factory/compose.env

# 4. Webhook Bridge settings
cp .factory/templates/bridge.example ~/.config/light-factory/bridge.env
```

Open each file in an editor and fill in your values. Also update `HUMAN_APPROVERS` in `.github/workflows/human-gate-guard.yml` with your GitHub username.

---

## 5. Step 4: Run Preflight Check

Validate that all secrets, keys, and Docker Compose configurations are correct:

```bash
./.factory/preflight.sh
```

You should see all green checkmarks (`✅`).

---

## 6. Step 5: Start the 7 Factory Containers

Launch all 7 containers in the background:

```bash
docker compose --env-file ~/.config/light-factory/compose.env up -d
```

Verify that all 7 services (`auth-minter`, `llm-proxy`, `factory-postgres`, `herdr-hub`, `worker-agy`, `worker-qwen`, `worker-glm`) are healthy:
```bash
docker compose ps
```

### One-Time Antigravity Login (Only 1 Container!)
Authenticate your AI Ultra 5x account once inside `worker-agy` (persists in the `agy-auth` / `agy-dotgemini` Docker volumes). Passing `-e SSH_CONNECTION=1` triggers Antigravity's copy-paste remote URL login flow inside headless Docker:
```bash
docker compose exec -it -e SSH_CONNECTION=1 worker-agy agy
# Copy the printed OAuth URL into your browser, paste back the code, then type /exit
# (Recommend keeping "Use AI Credits" OFF so overflow uses cheaper worker-glm)
```

---

## 7. Step 6: Connect to the Live Herdr Workspace

`herdr-hub` automatically bootstraps `webhook-bridge` (port `8787`) and all 6 tabs in the background on `docker compose up -d` (and after host reboots). To attach interactively and watch live agent output from your server or laptop:

```bash
docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh
```

This launches the unified 6-tab terminal interface:
- **`[bridge]`**: Incoming GitHub webhook queue, 8s coalescer, 15m watchdog, and 3-strike circuit breaker.
- **`[architect]`**: Chief Architect on GLM-5.3 (persistent planning & specs).
- **`[orchestrator]`**: Factory Orchestrator on GLM-5.3 + Vision (ephemeral `/clear` wave routing, dynamic `--model` dispatch, PR diff/screenshot review).
- **`[worker-agy]`**: Primary multi-model Antigravity builder & combined Senior/Specialist (switches dynamically between Carbon, Neon, Hydrogen, and Opus 5.5).
- **`[worker-qwen]`**: Free local GPU builder running Qwen 27B.
- **`[worker-glm]`**: Cheap GLM-5.3 API backup & overflow builder.

*(Press `ctrl+b q` anytime to detach cleanly and leave the agents running in the background).*

---

## 8. Step 7: Connect GitHub Webhooks

The bridge listens on port `8787` (`http://127.0.0.1:8787/webhook`).

To forward webhooks from GitHub to your server:
- **Option A (Cloudflare Tunnel - Recommended):** Run `cloudflared tunnel` routing a public HTTPS URL to `http://localhost:8787`.
- **Option B (Smee.io / Tailscale Funnel):** Forward payloads directly to port `8787`.

In your GitHub repository settings under **Webhooks**, set:
- **Payload URL:** `https://your-tunnel-url/webhook`
- **Content type:** `application/json`
- **Secret:** The same secret set in `bridge.env`
- **Events:** Select *Issues*, *Issue comments*, *Pull requests*, *Pull request reviews*, and *Workflow runs*.

---

## 9. Day-to-Day Operations: How to Build

1. Open a GitHub Issue describing what you want to build and apply the label **`plan`**.
2. Review the Architect's Strawman blueprint and reply **`LGTM`** (or adjust requirements).
3. Apply the label **`ready`** to hand off to the Orchestrator.
4. The Orchestrator dispatches **Wave 0** (`worker-agy --model gemini-4-carbon-high`) for the Golden E2E Acceptance Test, then runs Wave 1+ parallel builds across `worker-agy`, `worker-qwen`, and `worker-glm`.
5. Check your Kanban board's **`Awaiting Approval`** column for any PRs requiring human review (database migrations, auth/security, or factory config).
6. When an Epic completes, merge the rolling `staging -> master` Release PR with **"Create a merge commit"** to ship to production!
