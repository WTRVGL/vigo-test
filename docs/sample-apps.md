# VIGO — Real Sample Apps (Published Images)

Start here for first-time setup: docs/00-zero-to-live.md

These stacks use public images you can deploy immediately, no CI required. Create the env files, encrypt with SOPS, commit, and deploy.

Note: The template now ships only two default stacks in `stacks/` (whoami, echoserver). Additional samples (grafana, direct bindings, sampleapp) live under `examples/` and are not deployed by default. Move a folder back into `stacks/` to enable it.

Prerequisites
- You’ve completed Local Setup (docs/02-setup-local.md) and can encrypt/decrypt `env/*.env`.
- Traefik is deployed from `proxy/` and has DNS pointing to your VPS.

1) Traefik Whoami
- Stack file: `stacks/whoami/docker-compose.yml`
- Create env: `env/whoami.env`
  ```env
  WHOAMI_HOST=whoami.example.com
  WHOAMI_INTERNAL_PORT=80
  ```
- Encrypt and commit:
  ```bash
  sops -e -i env/whoami.env
  git add stacks/whoami/docker-compose.yml env/whoami.env
  git commit -m "Add whoami sample app"
  git push
  ```
- After deploy, browse: `https://whoami.example.com`.

2) Echo Server (ealen/echo-server)
- Stack file: `stacks/echoserver/docker-compose.yml`
- Create env: `env/echoserver.env`
  ```env
  ECHOSERVER_HOST=echo.example.com
  ECHOSERVER_INTERNAL_PORT=80
  ```
- Encrypt and commit:
  ```bash
  sops -e -i env/echoserver.env
  git add stacks/echoserver/docker-compose.yml env/echoserver.env
  git commit -m "Add echo server sample app"
  git push
  ```
- After deploy, browse: `https://echo.example.com`.

3) Grafana (real dashboard)
- Stack file: `examples/grafana/docker-compose.yml` (move to `stacks/` to enable)
- Create env: `env/grafana.env`
  ```env
  GRAFANA_HOST=grafana.example.com
  GRAFANA_INTERNAL_PORT=3000
  GF_SECURITY_ADMIN_USER=admin
  GF_SECURITY_ADMIN_PASSWORD=change-me
  ```
- Encrypt and commit:
  ```bash
  sops -e -i env/grafana.env
  git add examples/grafana/docker-compose.yml env/grafana.env
  git commit -m "Add grafana sample app"
  git push
  ```
- After deploy, browse: `https://grafana.example.com`.

Notes
- Whoami and echo-server are tiny public images on port 80. Grafana uses port 3000 and persists data in a named volume.
- Traefik handles TLS via Let’s Encrypt using `env/global.env`’s `TRAEFIK_ACME_EMAIL`.
- You can copy these stacks as a starting point for your own apps.
