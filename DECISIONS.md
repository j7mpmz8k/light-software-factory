# Architectural Decision Records (ADR)

## 001 - Multi-Agent Zero-Trust Docker Architecture
- **Status:** Accepted (Updated to 7-Container A1 + B2 Stack)
- **Decision:** Run 7 sibling containers (`auth-minter`, `llm-proxy`, `factory-postgres`, `herdr-hub`, `worker-agy`, `worker-qwen`, `worker-glm`) across 3 private Docker networks (`factory-net`, `llm-net`, internal `db-net`) with zero `docker.sock` mounts, zero Herdr socket mounts in workers, and zero raw API keys in AI containers.

## 002 - Per-Pane Turn-Serialized Priority Queue & 8-Second Comment Coalescer
- **Status:** Accepted
- **Decision:** Process incoming GitHub events sequentially per control-plane tab (`architect` and `orchestrator` drain concurrently without blocking each other), debounce rapid human feedback over 8 seconds, deduplicate webhook deliveries via `x-github-delivery`, and fail closed when `GITHUB_WEBHOOK_SECRET` is unset.

## 003 - Dedicated `human-gate-guard` on Trusted Default Branch (`main` / `master`)
- **Status:** Accepted
- **Decision:** Execute release and protected-path gating strictly from the trusted default branch (`main` or `master`) using `pull_request_target`, defaulting `HUMAN_APPROVERS` to `vars.HUMAN_APPROVERS || github.repository_owner`.

## 004 - Dynamic Multi-Model `worker-agy` + GLM-5.3 Control Plane & Backup
- **Status:** Accepted
- **Decision:** Run both `architect` and `orchestrator` on always-on GLM-5.3 (+ GLM-5.3-Flash Vision) so failover never stalls when Antigravity throttles. Consolidate Wave 0 E2E (`gemini-4-carbon-high`), routine coding (`gemini-4-hydrogen-high`), complex coding (`gemini-4-neon-high`), and 1-pass rescues (`claude-opus-5-5-high`) into one dynamically switched `worker-agy` container alongside `worker-qwen` (free local GPU) and `worker-glm` (cheap GLM-5.3 backup with isolated hourly spend cap).
