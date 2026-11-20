# Light Software Factory — Setup & Quickstart Guide

This guide walks you through setting up and launching the Light Software Factory on a Linux server or GPU host.

---

## 1. Prerequisites

Before starting, ensure your host machine has:
* **Linux OS** (Ubuntu 22.04+, Debian 12+, Arch, Fedora, etc.)
* **Docker & Docker Compose v2** (`docker compose version` $\ge 2.20$)
* **Git** and **GitHub CLI (`gh`)** (`gh auth login`)
* *(Optional for local worker)*: **GPU with Ollama or vLLM** serving `qwen3.8:27b` on port 11434 or 8000.

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

The factory uses two private GitHub Apps so that agent actions are role-isolated and audited under bot identities:

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

# 2. LLM API keys (mounted ONLY into llm-proxy, never exposed to AI containers)
cp .factory/templates/llm-secrets.example ~/.config/light-factory/llm-secrets.env

# 3. Master Compose environment (models, passwords, repo name)
cp .factory/templates/compose.example ~/.config/light-factory/compose.env

# 4. Webhook Bridge settings
cp .factory/templates/bridge.example ~/.config/light-factory/bridge.env
```

Open each file in an editor and fill in your values (API keys, passwords, and GitHub repository name).

---

## 5. Step 4: Run Preflight Check

Validate that all secrets, keys, and Docker Compose configurations are correct:

```bash
./.factory/preflight.sh
```

You should see all green checkmarks (`✅`). If anything is missing or misnamed, the script will point directly to the issue.

---

## 6. Step 5: Start the Factory Containers

Launch all 8 containers in the background:

```bash
docker compose --env-file ~/.config/light-factory/compose.env up -d
```

Verify that all services are healthy:
```bash
docker compose ps
```

---

## 7. Step 6: Connect to the Live Herdr Workspace

From your server (or via SSH from your laptop):

```bash
docker compose exec -it herdr-hub /workspace/.factory/launch-panes.sh
```

This launches the unified 6-tab terminal interface:
- **`[bridge]`**: Incoming GitHub webhook queue and event stream.
- **`[architect]`**: Hermes Architect planning and reviewing code diffs.
- **`[worker-gemini]`**: Gemini builder running on Antigravity CLI.
- **`[worker-qwen]`**: Local GPU builder running on Qwen.
- **`[senior-worker]`**: Frontier API relief builder running on Hermes.
- **`[specialist-fable]`**: Claude Code rescue specialist.

*(Press `ctrl+b q` anytime to detach cleanly and leave the agents running in the background).*

---

## 8. Step 7: Connect GitHub Webhooks

The bridge listens on port `8787` (`http://127.0.0.1:8787/events`).

To forward webhooks from GitHub to your server:
- **Option A (Cloudflare Tunnel - Recommended):** Run `cloudflared tunnel` routing a public HTTPS URL to `http://localhost:8787`.
- **Option B (Smee.io / Tailscale Funnel):** Use Smee or Tailscale to forward payloads directly to port `8787`.

In your GitHub repository settings under **Webhooks**, set:
- **Payload URL:** `https://your-tunnel-url/events`
- **Content type:** `application/json`
- **Secret:** The same secret set in `bridge.env`
- **Events:** Select *Issues*, *Issue comments*, *Pull requests*, *Pull request reviews*, and *Workflow runs*.

---

## 9. Day-to-Day Operations: How to Build

1. Open a GitHub Issue describing what you want to build and apply the label **`plan`**.
2. The Architect breaks it down into Sub-Issues and posts a **Wave Blueprint**.
3. Review the blueprint. When ready, apply the label **`ready`**.
4. Workers pick up sub-issues, build features, run tests, and open PRs against `staging`.
5. Check your Kanban board's **`Awaiting Approval`** column for any PRs requiring human review (e.g. database migrations or security files).
6. When an Epic is complete, the rolling `staging -> master` Release PR is generated automatically. Merge it with **"Create a merge commit"** to ship to production!
