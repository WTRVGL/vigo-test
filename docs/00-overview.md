# VIGO — Overview

Start here for first-time setup: docs/00-zero-to-live.md

Goal
- VIGO is a template repo to run many small apps on one or more VPS hosts using Docker Compose, Traefik, and GitOps pull.
- Secrets committed safely via SOPS (age). No central control plane.

Core Components
- Docker + Compose: runtime for apps and the reverse proxy.
- Traefik: reverse proxy with labels-based routing and automatic TLS via Let’s Encrypt.
- SOPS (age): encrypt `.env` config files committed to git.
- systemd timer: the VPS pulls and reconciles state every minute.

Flow
1) You push infra changes to this repo (compose files, image tags, env files).
2) Each VPS runs a timer that pulls `origin/<branch>` (default `main`, configurable via `REMOTE_BRANCH`), decrypts envs, and runs `docker compose up -d` for proxy and stacks.
3) Traefik routes traffic using labels from your app services.

Why this design
- Simple and observable. Everything is plain files + logs.
- Rollbacks/promotions by changing pinned image tags in git.
- Secure-by-default: secrets encrypted at rest, TLS certs automated.
