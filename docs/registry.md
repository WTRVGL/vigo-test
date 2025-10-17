# VIGO — Private Registry Setup

Start here for first-time setup: docs/00-zero-to-live.md

GitHub Container Registry (GHCR)

Create a PAT (pull-only)
- Classic PAT (recommended for GHCR)
  1) GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token
  2) Scopes: check `read:packages` (required). If pulls still fail for private org repos, also add `repo` (Read) as some orgs require repo membership verification.
  3) Set an expiration, generate the token, copy it safely
  4) If your org enforces SSO: on the token page, click “Configure SSO”, then “Authorize” for the org
- Fine‑grained PAT (alternative)
  - Not all orgs expose a “Packages: Read” permission for fine‑grained tokens yet. If you don’t see it, use a classic PAT instead.

Login on the VPS (as root)
- Interactive (simple)
  ```bash
  docker login ghcr.io -u <your-github-username>
  # When prompted for Password:, paste your PAT and press Enter
  ```
- One‑liner (no prompt)
  ```bash
  echo 'YOUR_PAT' | docker login ghcr.io -u <your-github-username> --password-stdin
  ```
- From a file (safer than typing)
  ```bash
  printf '%s' 'YOUR_PAT' > /root/ghcr.pat && chmod 600 /root/ghcr.pat
  docker login ghcr.io -u <your-github-username> --password-stdin < /root/ghcr.pat
  shred -u /root/ghcr.pat
  ```

Test pull (replace OWNER/IMAGE:TAG)
```bash
docker pull ghcr.io/OWNER/IMAGE:TAG
```

Notes
- The GitOps service runs as root; store creds under root so pulls work: `/root/.docker/config.json`.
- If login fails with 403 and your org uses SSO, the token likely isn’t authorized for the org; go back to the token page and “Configure SSO”.
- If pulls for private images still fail, re‑issue the token adding `repo` (Read) scope (classic PAT) to satisfy org policies.
- Avoid `docker login -p TOKEN` (shows in history and process list). Prefer `--password-stdin`.
- Prefer one read‑only PAT per VPS; rotate regularly.

GitLab Container Registry
```bash
docker login registry.gitlab.com -u <USERNAME> -p <PERSONAL_ACCESS_TOKEN>
```

ECR / Others
- Ensure the VPS has a long‑lived pull credential or a scheduled refresher (e.g., `aws ecr get-login-password | docker login ...`).

Best practices
- Use read‑only tokens per VPS; rotate regularly.
- Store credentials under root so the systemd service (runs as root) can pull.
