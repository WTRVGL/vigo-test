# VIGO — Concepts

Start here for first-time setup: docs/00-zero-to-live.md

SOPS + age
- age is a simple public/private key encryption tool. You generate one keypair.
- SOPS uses age to encrypt files (e.g., `.env`) so you can store them in git safely.
- Only holders of the private key can decrypt on their machines/servers.
- In this repo, `.sops.yaml` enforces that `env/*.env` files are always encrypted when committed.

Traefik + ACME (Let’s Encrypt)
- Traefik is a reverse proxy configured via container labels.
- It can automatically obtain and renew TLS certificates from Let’s Encrypt using the ACME protocol.
- `TRAEFIK_ACME_EMAIL` is the account email used with Let’s Encrypt for renewal notices/recovery.
- Requirements: public DNS A/AAAA records to your VPS, and ports 80/443 open. This template uses the TLS-ALPN challenge.

GitOps pull (timer-only)
- Each VPS runs a systemd timer (`ops/systemd/*`) that executes `ops/deploy.sh` every minute.
- `deploy.sh` pulls the repo, overlays host-specific files (if any), decrypts envs, and runs docker compose.
- This keeps the host converged to what’s in git.

Compose env and variable interpolation
- Decrypted `env/*.env` files are merged into `/srv/runtime/.env` so Compose labels and arguments can reference `${VARS}`.
- Each service also lists `env_file:` so variables are present inside containers at runtime.

Private images
- Your apps should publish images to a private registry (e.g., GHCR, GitLab Registry).
- Each VPS must authenticate (`docker login`) so pulls succeed during reconcile.

Immutable image tags
- App CI should publish immutable tags like `:sha-<GIT_SHA_SHORT>`.
- Infra pins to those tags (in `stacks/<app>/docker-compose.yml`). Promotion/rollback is just changing the tag in git.
