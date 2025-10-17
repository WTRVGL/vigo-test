# VIGO — Branch Strategy

Start here for first-time setup: docs/00-zero-to-live.md

This guide proposes practical branching strategies for both the infra repo (VIGO) and your application repos. Choose the simplest that fits: trunk‑based by default; add a staging branch only if you truly run a separate staging VPS.

## 1) Default: Trunk‑Based (Recommended)

Use a single protected `main` branch for production. All changes land via pull requests.

Infra repo (this repo)
- Feature branches: `feat/...`, `fix/...`, `docs/...` → open PRs to `main`.
- Protect `main`: required review, status checks, no direct pushes.
- Merge strategy: squash or rebase‑merge for a clean history.
- Deployment: merging to `main` updates production within ~60s (systemd timer).
- Rollback: `git revert` the commit that changed image tags or config; push to `main`.

App repos
- Feature branches → PR to `main`.
- CI builds images on every push; publish tags:
  - `:sha-<GIT_SHA_SHORT>` immutable (pin this in VIGO).
  - `:branch-<branch>` mutable (for branch‑based smoke if you use a staging host).
- On merge to `main`, CI publishes the `:sha-...` tag used by infra.

Pros
- Simple mental model; minimal moving parts.
- Promotion = merge to `main`; rollback = revert.

## 2) Two‑Environment: Staging → Prod (Optional)

Use this only if you have a separate staging VPS.

Branches
- `staging`: points to what runs on staging VPS.
- `main`: points to what runs on production VPS.

Deployment wiring (two options)
- Option A (separate repos): clone the same repo twice on different hosts; staging host tracks `staging`, prod tracks `main`.
- Option B (one repo, configurable branch): ops/deploy.sh supports `REMOTE_BRANCH` (default `main`). Set it via a systemd override on the staging host. Example override:
  - File: `/etc/systemd/system/gitops-pull.service.d/override.conf`
  - Contents:
    ```ini
    [Service]
    Environment=REMOTE_BRANCH=staging
    ```
  - No code changes required; VIGO already honors `REMOTE_BRANCH` in ops/deploy.sh for `git fetch`/`reset`.

Promotion
- Merge PR from `staging` → `main`.
- Staging pins the same immutable app tags as prod; the only difference is which branch the host pulls.

Pros
- Safe pre‑prod verification on a real host.
- Clear, auditable promotion via git history.

## 3) Staging Without Branches: Mutable Tags (Alternate)

If you don’t want multi‑branch infra, run a staging host that uses mutable tags for app images:
- In `stacks/<app>/docker-compose.yml` on the staging host overlay, set `image: ...:branch-main`.
- Production continues to pin `:sha-...` in the base repo.
- This uses host overlays in `hosts/<staging-host>/stacks/.../docker-compose.yml`.

Pros
- No infra branching; staging always tracks latest branch builds.
- Production remains deterministic via `:sha-...`.

## 4) Tagging & Releases (Infra Repo)

- Tag infra commits that change production, e.g., `prod-YYYYMMDD-HHMM` or `release-vX.Y`.
- Optional GitHub/GitLab releases for audit/change logs.

## 5) Policy Checklist

- Protect `main`; require PR reviews.
- Never pin mutable tags in production; always use `:sha-...`.
- Keep feature branches short‑lived; merge fast.
- Document rollbacks: link the revert commit in your incident notes.
- For multi‑VPS fleets, use `hosts/<hostname>/...` overlays for per‑host differences.

## 6) CI Signals / Checks

- App repos: CI must fail if image push fails; publish `:sha-...` on merges to `main`.
- Infra repo: add a CI job to run `docker compose -f proxy/docker-compose.yml config` and each stack’s `docker compose config` (lint/syntax only). Optionally lint labels.
- Optionally a SOPS check to ensure `env/*.env` remain encrypted.

## 7) Example Workflows

Feature → Prod (trunk‑based)
- Dev creates `feat/new-banner` in app repo → PR → merge to `main` → CI publishes `:sha-deadbee`.
- Infra PR edits `stacks/app/docker-compose.yml` to `image: ...:sha-deadbee` → merge to `main`.
- VPS reconciles, new version live.

Staging → Prod (two‑branch)
- Dev merges to app `main` → CI publishes `:sha-cafef00` and `:branch-main`.
- Infra merges to `staging` pinning `:sha-cafef00`; staging VPS pulls `staging`.
- If good, PR `staging` → `main` and merge; prod VPS pulls `main`.
