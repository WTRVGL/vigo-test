# VIGO — Virtual Private Server GitOps

VIGO is a ready‑to‑use template for running apps on one or more VPS hosts using Docker Compose, Traefik (automatic TLS via Let’s Encrypt), and a pull‑based GitOps loop. Secrets are committed encrypted with SOPS (age), and a systemd timer reconciles hosts every minute.

## Deployment Overview (fill for your VPS)

Keep a quick, human‑readable summary of what this repository currently deploys. Avoid secrets; this is operational state you’re OK to share with your team.

- Hostname: vigo-test
- Public IPv4: 172.235.173.202  |  Public IPv6: fe80::2000:5eff:fe28:165f
- Proxy: Traefik v3.1 on network `proxy_default` (ACME resolver `le`)
- ACME email: set in `env/global.env` (`TRAEFIK_ACME_EMAIL`, encrypted)
 - Domains: 
   - `exolan.be` (apex A/AAAA) and `www.exolan.be` (CNAME → apex)
   - `leugens.be` (apex A/AAAA) and `www.leugens.be` (CNAME → apex)
 - See Active Stacks below for per‑app routes and images
- Last converge: <timestamp or note from gitops logs>

Update tips (run on VPS):

```bash
# Basic host info
hostname -f || hostname
curl -4s https://ifconfig.co || curl -4s https://api.ipify.org
curl -6s https://ifconfig.co || true

# Traefik + stacks status
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
docker logs --since=1h traefik | tail -n 100

# ACME status (look for successful cert issuance)
docker logs traefik 2>&1 | rg -i "acme|certificate|lego" | tail -n 50
```

DNS checklist:

- `A` record for apex → your VPS IPv4; add `AAAA` only if IPv6 80/443 are reachable.
- `CNAME` for `www` → apex (preferred) or duplicate `A/AAAA` to the same IPs.
- If using a CDN/proxy, disable proxying until certificates are issued (or use DNS‑01).

## Active Stacks

- exolan
  - Domains: `exolan.be` (primary), `www.exolan.be` (redirects to apex)
  - Image: `ghcr.io/wtrvgl/exolan/web:v0.1.1`
  - Service/port: `web` → 80 (via Traefik)
  - Networks: `proxy_default`

- leugens
  - Domains:
    - Web: `${LEUGENS_WEB_HOST}` (set in `env/leugens.env`, encrypted)
    - WWW: `www.leugens.be` (redirects to apex)
    - API: `${LEUGENS_API_HOST}` and also `Host(${LEUGENS_WEB_HOST}) && PathPrefix(/api)`
  - Images: `${LEUGENS_WEB_IMAGE}`, `${LEUGENS_API_IMAGE}`, `postgres:16-alpine`
  - Services/ports: `web` → 80, `api` → 8080, `postgres` → 5432 (internal)
  - Networks: `proxy_default` (edge), `app` (private)
  - Volumes: `flags`, `pgdata` (name `${LEUGENS_PGDATA_VOLUME:-leugens_pgdata}`)

## Quick Start
- Prefer the single‑page, copy/paste guide: [Zero to Live](docs/00-zero-to-live.md)
- Summary:
  - Laptop: install `age` + `sops`, generate an age key, set `.sops.yaml` to your public key, create and encrypt `env/global.env` with `TRAEFIK_ACME_EMAIL`, push to YOUR private infra repo.
  - VPS: install Docker (official repo, includes compose), install `age`/`sops`, clone YOUR repo via SSH deploy key or HTTPS+PAT, place the age PRIVATE key at `/root/.config/sops/age/keys.txt`, enable the GitOps timer, run first converge.

## Local vs VPS
- Local (your laptop):
  - Install `age` + `sops`, generate an age key, configure `.sops.yaml`, create and encrypt `env/*.env`.
  - Optional: run `ops/preflight-local.sh` for sanity checks. You do not need to run the stacks locally.
- VPS (remote server):
  - Install packages, clone your infra repo to `/srv/vigo` (not this template), place the age PRIVATE key at `/root/.config/sops/age/keys.txt`.
  - Log in to your container registry as root (`docker login ...`).
  - Enable the GitOps timer; it pulls and applies every ~60s.

See: [Local Setup](docs/02-setup-local.md) and [Bootstrap VPS](docs/03-bootstrap-vps.md).

## End‑to‑End Setup
1) Read the short overview: [Overview](docs/00-overview.md)
2) Local setup: generate age keys, configure `.sops.yaml`, create and encrypt envs: [Local Setup](docs/02-setup-local.md)
3) Commit and push this infra repo to your own remote (usually private).
4) Bootstrap a VPS (Ubuntu/Debian), clone YOUR infra repo (not this template), log in to your private registry (e.g., GHCR), enable the GitOps timer: [Bootstrap VPS](docs/03-bootstrap-vps.md)
5) Validate Traefik and stacks are up; browse your domain; check logs: [Operate](docs/04-operate.md)
6) Add a new app stack using the template and encrypted envs: [Add a New App](docs/howto-new-app.md)
7) Wire CI/CD to publish immutable `:sha-<commit>` tags: [CI/CD Reference](docs/05-ci-cd.md)
8) If anything misbehaves, see: [Troubleshooting](docs/06-troubleshooting.md) and [Private Registry Setup](docs/registry.md)

## Documentation
- [Zero to Live](docs/00-zero-to-live.md) — End‑to‑end copy/paste setup
- [Overview](docs/00-overview.md) — What this repo is and how it works
- [Core Concepts](docs/01-concepts.md) — SOPS/age, Traefik, ACME, GitOps model
- [Local Setup](docs/02-setup-local.md) — Generate keys, configure `.sops.yaml`, encrypt envs
- [Bootstrap VPS](docs/03-bootstrap-vps.md) — Prepare a VPS, private registry auth, enable timer
  - bootstrap.sh is optional; the doc shows manual steps.
- [Operate](docs/04-operate.md) — Day‑2 ops, promote/rollback, updates
- [CI/CD Reference](docs/05-ci-cd.md) — CI templates for Node and ASP.NET Core
- [Branch Strategy](docs/08-branching.md) — Trunk‑based and staging→prod options
- [Troubleshooting](docs/06-troubleshooting.md) — Common failures and fixes
  - Includes SOPS key discovery (`no identity matched`), sudo/root gotchas
- [Security](docs/07-security.md) — Key management, backups, permissions
- [Add a New App](docs/howto-new-app.md) — Step‑by‑step for a new stack
- [Sample Apps](docs/sample-apps.md) — Deployable stacks using published images (whoami, nginx demo)
  - The template ships with two default stacks (`stacks/whoami`, `stacks/echoserver`). Extra examples live under `examples/`.
- [Traefik + ACME](docs/traefik-acme.md) — Let’s Encrypt deep dive
- [Private Registry Setup](docs/registry.md) — GHCR, GitLab, others

## Templates
- [Node Dockerfile](templates/apps/node/Dockerfile) — Production Node container (multi‑stage)
- [ASP.NET Core Dockerfile](templates/apps/dotnet/Dockerfile) — Production ASP.NET Core container
- [GitHub Actions (Node)](templates/ci/github-actions-node.yml) — Build + push to GHCR
- [GitHub Actions (ASP.NET Core)](templates/ci/github-actions-dotnet.yml) — Build + push to GHCR
- [GitLab CI (Node)](templates/ci/gitlab-ci-node.yml) — Build + push to GitLab Registry
- [GitLab CI (ASP.NET Core)](templates/ci/gitlab-ci-dotnet.yml) — Build + push to GitLab Registry
- [Compose Stack Template](templates/stacks/_template/docker-compose.yml) — Compose + Traefik labels template

## Repository Structure
- `ops/` — Shell + systemd timer to pull/apply
- `proxy/` — Traefik docker‑compose
- `stacks/` — App stacks to deploy (now minimal: whoami, echoserver)
- `templates/stacks/` — Stack compose template(s)
- `examples/` — Additional sample stacks (not deployed by default)
- `env/` — Encrypted runtime `.env` files (SOPS/age)
- `hosts/<hostname>/` — Optional per‑host overlays

## Private Images
- Use `docker login` on each VPS as `root` for your registry (e.g., GHCR).
- See [Private Registry Setup](docs/registry.md) for exact commands and token scopes.

## Preflight Checks
- Local: `bash ops/preflight-local.sh` — verifies tools, `.sops.yaml` key, and env encryption.
- VPS: `sudo journalctl -u gitops-pull.service -f` — watch reconcile logs; `docker ps` — Traefik/stacks up.

## How It Works
1) Commit infra changes to `main`.
2) A systemd timer on each VPS pulls the repo and overlays host config.
3) SOPS decrypts envs into the runtime directory.
4) Traefik and stacks start with `docker compose up -d`.

## Notes
- Pin images to immutable `:sha-<GIT_SHA_SHORT>` tags (safer rollbacks/promotions).
- DNS must point app hostnames to the VPS IP; expose ports 80/443.
- Compose label variables resolve from `$RUNTIME_DIR/.env`, built from decrypted `env/*.env` during deploy.
- Two direct demo stacks ship enabled by default: `whoami-direct` on port 8081 and `echoserver-direct` on port 8082 for instant smoke tests without DNS.
