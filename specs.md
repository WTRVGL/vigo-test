# VIGO — Single‑VPS GitOps (Timer‑Only)

A lean, **Kubernetes‑free GitOps** workflow for one or more VPS hosts using only:

* **Docker + Compose** as runtime
* **Traefik** reverse proxy (labels‑based routing, auto‑TLS)
* **SOPS (age)** for encrypted runtime secrets committed to git
* **systemd timer** for pull‑based reconcile every minute (no dashboards, no custom API)

> You push to the **infra repo** → the VPS **pulls & applies**. App repos only **build & push** images.

---

## 1) Design Principles

* **Single source of truth:** this infra repo declares everything that runs.
* **Pull‑based reconcile:** a systemd timer executes a shell script to converge actual state.
* **Immutable deployments:** pin images by git **SHA tags**; promotion happens by changing tags here.
* **Simple networking:** Traefik routes per app using container **labels**; no manual Nginx files.
* **Secure by default:** secrets live encrypted in git via SOPS; Traefik gets TLS via Let’s Encrypt.
* **Multi‑VPS ready:** per‑host overlays live under `hosts/<hostname>/...`.

---

## 2) Repo Layout

```
vigo/
├─ README.md
├─ .sops.yaml
├─ ops/
│  ├─ bootstrap.sh
│  ├─ functions.sh
│  ├─ deploy.sh
│  └─ systemd/
│     ├─ gitops-pull.service
│     └─ gitops-pull.timer
├─ proxy/
│  ├─ docker-compose.yml
│  └─ acme/            # created on host; acme.json chmod 600
├─ stacks/
│  ├─ whoami/
│  │  └─ docker-compose.yml
│  ├─ echoserver/
│  │  └─ docker-compose.yml
│  ├─ whoami-direct/
│  │  └─ docker-compose.yml
│  └─ echoserver-direct/
│     └─ docker-compose.yml
├─ env/
│  ├─ global.env
│  ├─ whoami.env        # encrypted with SOPS (age)
│  └─ echoserver.env    # encrypted with SOPS (age)
└─ hosts/
   ├─ README.md
   └─ <hostname>/      # per‑host overrides (optional)
      ├─ proxy/docker-compose.yml
      ├─ stacks/.../docker-compose.yml
      └─ env/*.env
```

> If a `hosts/<hostname>/...` tree exists matching the VPS `$(hostname)`, those files **overlay** the root during reconcile.

---

## 3) Versioning & Tag Policy (Required)

Each **application repo** publishes **immutable SHA tags** + a moving branch tag:

* `ghcr.io/yourorg/app:sha-<GITHUB_SHA_SHORT>` **(immutable)**
* `ghcr.io/yourorg/app:branch-main` **(mutable, for smoke)**
* Optional releases: `ghcr.io/yourorg/app:vX.Y.Z`

**Infra pins to immutable `:sha-…`** in `stacks/<app>/docker-compose.yml`.
Promotion = change the tag in this repo and push. Rollback = revert that commit.

---

## 4) Traefik — Labels‑Based Routing & Subdomains

`proxy/docker-compose.yml`

```yaml
version: "3.9"
services:
  traefik:
    image: traefik:v3.1
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.le.acme.tlschallenge=true
      - --certificatesresolvers.le.acme.email=${TRAEFIK_ACME_EMAIL}
      - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
    ports: ["80:80", "443:443"]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./acme/acme.json:/letsencrypt/acme.json
    restart: unless-stopped
networks:
  default:
    name: proxy_default
```

**Per‑app routing** (example `stacks/whoami/docker-compose.yml`):

```yaml
version: "3.9"
services:
  web:
    image: ghcr.io/yourorg/whoami:sha-<commit>
    env_file:
      - ../../env/global.env
      - ../../env/whoami.env
    labels:
      - traefik.enable=true
      - traefik.http.routers.whoami.rule=Host(`${WHOAMI_HOST}`)
      - traefik.http.routers.whoami.entrypoints=websecure
      - traefik.http.routers.whoami.tls.certresolver=le
      - traefik.http.services.whoami.loadbalancer.server.port=${WHOAMI_INTERNAL_PORT}
    restart: unless-stopped
networks:
  default:
    external: true
    name: proxy_default
```

`env/whoami.env` (commit **encrypted**):

```env
WHOAMI_HOST=whoami.example.com
WHOAMI_INTERNAL_PORT=80
```

Add wildcard DNS `*.example.com -> VPS_IP` (or per‑host A/AAAA records). Add more apps by copying this pattern.

---

## 5) Secrets & Config — SOPS (age)

* **Encrypt all runtime env files:** `env/*.env` are forced encrypted via `.sops.yaml`.
* Generate keys locally: `age-keygen -o age.txt` → put **public key** in `.sops.yaml`, **private key** on the VPS at `/root/.config/sops/age/keys.txt`.
* Edit secrets with SOPS: `sops -e -i env/<app>.env`.
* During reconcile, secrets decrypt into `/srv/runtime/env/*.env` and are mounted via `env_file`.

`.sops.yaml`

```yaml
creation_rules:
  - path_regex: env/.*\.env$
    age: ["age1YOUR_PUBLIC_KEY_HERE"]
```

---

## 6) Reconcile Engine (systemd timer + shell)

`ops/functions.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
msg(){ echo -e "[gitops] $*"; }
overlay(){ rsync -a --delete --exclude ".git" "$1/" "$2/"; }
# Decrypt envs from $1 -> $2
decrypt_envs(){ mkdir -p "$2"; while IFS= read -r -d '' f; do rel=${f#"$1/"}; mkdir -p "$(dirname "$2/$rel")"; sops -d "$f" > "$2/$rel"; done < <(find "$1" -type f -name '*.env' -print0); }
```

`ops/deploy.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO_DIR=/srv/vigo
RUNTIME_DIR=/srv/runtime
HOSTNAME=$(hostname)
REMOTE_BRANCH=${REMOTE_BRANCH:-main}
. "$REPO_DIR/ops/functions.sh"
cd "$REPO_DIR"
msg "Fetch $REMOTE_BRANCH..."; git fetch --quiet origin "$REMOTE_BRANCH" || true
LOCAL=$(git rev-parse HEAD); REMOTE=$(git rev-parse "origin/$REMOTE_BRANCH" || echo "$LOCAL")
[[ "$LOCAL" == "$REMOTE" ]] || git reset --hard "origin/$REMOTE_BRANCH"
msg "Prepare runtime..."; mkdir -p "$RUNTIME_DIR"
overlay "$REPO_DIR" "$RUNTIME_DIR"
if [[ -d "$REPO_DIR/hosts/$HOSTNAME" ]]; then msg "Host overlay: $HOSTNAME"; overlay "$REPO_DIR/hosts/$HOSTNAME" "$RUNTIME_DIR"; fi
mkdir -p "$RUNTIME_DIR/proxy/acme"; [[ -f "$RUNTIME_DIR/proxy/acme/acme.json" ]] || touch "$RUNTIME_DIR/proxy/acme/acme.json"; chmod 600 "$RUNTIME_DIR/proxy/acme/acme.json"
if command -v sops >/dev/null 2>&1; then msg "Decrypt envs"; decrypt_envs "$REPO_DIR/env" "$RUNTIME_DIR/env"; fi
msg "Proxy up"; docker compose -f "$RUNTIME_DIR/proxy/docker-compose.yml" --project-directory "$RUNTIME_DIR" up -d
for stack in "$RUNTIME_DIR"/stacks/*; do [[ -f "$stack/docker-compose.yml" ]] || continue; msg "Stack: $(basename "$stack")"; docker compose -f "$stack/docker-compose.yml" --project-directory "$RUNTIME_DIR" up -d; done
msg "Done"
```

`ops/systemd/gitops-pull.service`

```ini
[Unit]
Description=GitOps pull and apply
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
User=root
WorkingDirectory=/srv/vigo
ExecStart=/bin/bash /srv/vigo/ops/deploy.sh
```

`ops/systemd/gitops-pull.timer`

```ini
[Unit]
Description=Run GitOps pull every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
Unit=gitops-pull.service

[Install]
WantedBy=timers.target
```

---

## 7) Bootstrap a New VPS

```bash
# DNS: point *.example.com (or specific hosts) to the VPS IP
sudo apt update && sudo apt -y install git docker.io docker-compose-plugin age sops rsync
sudo mkdir -p /srv /srv/runtime
cd /srv && sudo git clone <YOUR_INFRA_REPO_URL> vigo
# Add AGE private key
sudo mkdir -p /root/.config/sops/age && sudo chmod 700 /root/.config/sops/age
sudo bash -lc 'cat > /root/.config/sops/age/keys.txt <<EOF
AGE-SECRET-KEY-1XXXXXXXX...
EOF'
sudo chmod 600 /root/.config/sops/age/keys.txt
# Enable timer
cd /srv/vigo
sudo cp ops/systemd/* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now gitops-pull.timer
# First run
sudo bash ops/deploy.sh
```

---

## 8) Application Repo — CI Template

Add to **each app repo** to push images on commit:

```yaml
name: docker-ci
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    permissions: { contents: read, packages: write }
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: calc tags
        id: t
        run: echo "sha=$(git rev-parse --short HEAD)" >> $GITHUB_OUTPUT
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ghcr.io/yourorg/yourapp:sha-${{ steps.t.outputs.sha }}
            ghcr.io/yourorg/yourapp:branch-${{ github.ref_name }}
```

**Infra pin example**:

```yaml
image: ghcr.io/yourorg/yourapp:sha-abc1234
```

Update the tag in `stacks/<app>/docker-compose.yml` to deploy.

---

## 9) Operations Runbook

* **Add a new app**: copy `stacks/sampleapp`, add `env/<app>.env` → `sops -e -i env/<app>.env` → commit/push.
* **Promote**: change image tag to new `:sha-…`, commit/push.
* **Rollback**: `git revert` the change or set the tag back to prior `:sha-…`.
* **Rotate secret**: edit with SOPS, commit/push; service restarts on next reconcile.
* **Blue/Green (optional)**: run `web_v1` and `web_v2` services; switch Traefik router label to target `service=web_v2`, then remove the old.
* **Health**: add `uptime-kuma` and/or `loki+promtail` later as separate stacks.

---

## 10) Security Hardening

* Traefik **only** mounts docker.sock **read‑only**. Do not mount it anywhere else.
* Disable Traefik dashboard, or protect with Basic Auth + IP allowlist if enabled.
* SOPS private key readable **only** by root (`chmod 600`).
* System firewall: allow 80/443; SSH via keys; optionally restrict SSH source IPs.
* Prefer **pinned SHA tags** (no `:latest`).
* Use a password manager or SOPS for all `.env` secrets; never commit plaintext.

---

## 11) Multi‑VPS Scaling

* Repeat the bootstrap on another VPS (unique hostname).
* Create `hosts/<hostname>/...` overrides for per‑host domains, tags, or env.
* Same infra repo, many hosts; each reconciles independently via the timer.

---

## 12) Acceptance Criteria

* [ ] Traefik serves apps at their hostnames with valid TLS.
* [ ] Infra timer reconciles at 60s cadence; manual `bash ops/deploy.sh` works.
* [ ] At least one app pinned to `:sha-…` deployed and routable.
* [ ] `env/*.env` committed **encrypted**; decryption succeeds on VPS.
* [ ] Rollback verified by reverting an infra commit.
* [ ] No control plane / webhook service exposed; surface area minimized.

---

## 13) FAQ

**Q: Where do app‑specific config & secrets live?**
A: In this repo: `stacks/<app>/docker-compose.yml` + `env/<app>.env` (encrypted). Build‑time secrets stay in the app repos/CI.

**Q: Do we need containers?**
A: Yes for this pattern—clean isolation, predictable deploys, simple Traefik routing.

**Q: Can we trigger deploys instantly?**
A: By design this spec avoids a long‑lived API. Rely on the 60s timer or run `systemctl start gitops-pull.service` over SSH/Tailscale when you need an immediate converge.
