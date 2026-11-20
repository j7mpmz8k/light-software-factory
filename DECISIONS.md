# Architectural Decision Records (ADR)

## 001 - Multi-Agent Zero-Trust Docker Architecture
- **Status:** Accepted
- **Decision:** Run 8 sibling containers across 3 private Docker networks with zero `docker.sock` mounts and zero raw keys in AI containers.

## 002 - Turn-Serialized Priority Queue & 8-Second Comment Coalescer
- **Status:** Accepted
- **Decision:** Process incoming GitHub events sequentially, debouncing rapid human feedback.

## 003 - Dedicated human-gate-guard on Trusted Default Branch
- **Status:** Accepted
- **Decision:** Execute release gating strictly from `master` using `pull_request_target`.
