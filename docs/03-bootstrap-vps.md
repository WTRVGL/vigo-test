# VIGO — Bootstrap a VPS (Ubuntu/Debian)

Start here for first-time setup: docs/00-zero-to-live.md

Note: The bootstrap script (`ops/bootstrap.sh`) is optional. This doc and the Zero‑to‑Live guide cover the same steps manually.

Requirements
- Public DNS for your apps points to this VPS
- Ports 80/443 reachable from the Internet
- A private registry account/token with pull access

1) Install dependencies (Docker Engine + compose plugin, age, sops)
- Check distro info (supported: Ubuntu/Debian):
  ```bash
  cat /etc/os-release
  ```
- Install prerequisites:
  ```bash
  sudo apt-get update && sudo apt-get install -y git ca-certificates curl gnupg rsync
  ```
- Install Docker from the official repo (ensures `docker compose` works):
  ```bash
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(. /etc/os-release; echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker
  ```
- Install `age` and `sops` (sops from release; age via apt or release):
  ```bash
  # sops (auto-detect arch, install from GitHub release)
  SOPS_VER=v3.11.0
  ARCH=$(dpkg --print-architecture)
  case "$ARCH" in amd64) SUF=amd64;; arm64) SUF=arm64;; *) echo "unsupported arch: $ARCH"; exit 1;; esac
  curl -fsSL "https://github.com/getsops/sops/releases/download/$SOPS_VER/sops-$SOPS_VER.linux.$SUF" | sudo tee /usr/local/bin/sops >/dev/null
  sudo chmod +x /usr/local/bin/sops

  # age (try apt, fallback to release)
  sudo apt-get install -y age || true
  if ! command -v age >/dev/null; then
    AGE_VER=v1.1.1
    case "$ARCH" in amd64) AGE_TAR="age-$AGE_VER-linux-amd64.tar.gz";; arm64) AGE_TAR="age-$AGE_VER-linux-arm64.tar.gz";; esac
    curl -fsSL "https://github.com/FiloSottile/age/releases/download/$AGE_VER/$AGE_TAR" \
      | sudo tar -xz -C /usr/local/bin --strip-components=1 age/age age/age-keygen
  fi
  ```
  - Verify:
    ```bash
    docker --version && docker compose version && age --version && sops --version
    ```

2) Clone your private infra repo (not the template)
```bash
sudo mkdir -p /srv /srv/runtime
cd /srv
```
SSH (recommended, using a deploy key)
- On the VPS as root, generate a key and add the public key to your GitHub repo as a read-only Deploy Key:
  ```bash
  sudo ssh-keygen -t ed25519 -C "vigo-deploy" -f /root/.ssh/id_ed25519 -N ""
  sudo sh -c 'ssh-keyscan github.com >> /root/.ssh/known_hosts'
  sudo chmod 700 /root/.ssh
  sudo chmod 600 /root/.ssh/id_ed25519 /root/.ssh/known_hosts
  cat /root/.ssh/id_ed25519.pub   # paste this into GitHub → Repo → Settings → Deploy keys
  ```
- Then clone via SSH:
  ```bash
  # Ensure this key is used and only this key is offered
  export GIT_SSH_COMMAND='ssh -o IdentitiesOnly=yes -i /root/.ssh/id_ed25519'
  sudo -E git clone git@github.com:<org>/<repo>.git vigo
  ```
Troubleshooting “Permission denied (publickey)”
- Confirm you added the VPS public key under the repo’s Settings → Deploy keys (not under your user’s keys). Deploy keys are per‑repo and must be unique per repo on GitHub.
- Some orgs enforce SSO for user keys/tokens. Deploy keys are repo‑scoped and usually bypass SSO; if you used a user key instead, authorize it for the org in GitHub → Settings → SSH and GPG keys → Configure SSO.
- Verify the key is actually used and has repo access:
  ```bash
  export GIT_SSH_COMMAND='ssh -v -o IdentitiesOnly=yes -i /root/.ssh/id_ed25519'
  git ls-remote git@github.com:<org>/<repo>.git HEAD
  ```
  If it still fails, re‑check the exact repo name and that the deploy key was added to THAT repo and marked “Allow read access”.

HTTPS with a repo-scoped Personal Access Token (PAT)
- Create a PAT with minimal scope (repo:read). Then:
  ```bash
  export GITHUB_USER=<your-username>
  export GITHUB_PAT=<your-token>
  sudo -E git clone https://$GITHUB_USER:$GITHUB_PAT@github.com/<org>/<repo>.git vigo
  ```
Notes for PATs
- Prefer a Fine‑grained PAT scoped to that single repo with “Repository contents: Read” (and Metadata: Read). If your org requires SSO, click “Configure SSO” on the token and authorize it for the org.
- Remove the token from shell history after cloning: `unset GITHUB_PAT`.
Notes
- Do not clone this template repo; clone the infra repo where your encrypted `env/*.env` live.
- If you use the bootstrap script instead, set `INFRA_REPO_URL` to an SSH URL (deploy key) or an HTTPS URL embedding a PAT.

3) SOPS age key (private)
```bash
sudo install -d -m 700 /root/.config/sops/age
sudo install -m 600 /dev/stdin /root/.config/sops/age/keys.txt <<'EOF'
AGE-SECRET-KEY-1XXXX...  # paste from your local age.txt
EOF
```
Notes
- The GitOps service and all deploy scripts run as `root`. Put your private key at `/root/.config/sops/age/keys.txt` so `sops` can find it without environment variables.
- If you run `sudo sops ...` interactively, your user’s env vars are not preserved unless you use `sudo -E`. Either copy the key for root as above, or run: `sudo SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt sops -d ...`.
- Verify the key matches recipients: `age-keygen -y /root/.config/sops/age/keys.txt` should print an `age1...` that appears in your file’s `sops:` recipients.

4) Private registry login (GHCR example)
```bash
sudo docker login ghcr.io -u <GITHUB_USERNAME> -p <PAT_WITH_read:packages>
```
Notes
- Use a read-only PAT with only `read:packages` (and `repo` if your GHCR requires it).
- For GitLab: `sudo docker login registry.gitlab.com -u <username> -p <PAT>`.

Docker user and service
- The GitOps service runs as `root` (see `ops/systemd/gitops-pull.service`). Do not add other users to the `docker` group on production hosts.
- Keep registry credentials under root (stored in `/root/.docker/config.json` after `docker login`).

Environment handling
- During deploy, decrypted envs are written to `/srv/runtime/env/*.env` and concatenated to `/srv/runtime/.env` for Compose variable interpolation.
- Services receive variables via `env_file:` in each stack `docker-compose.yml`.

5) Enable the GitOps timer
```bash
cd /srv/vigo
sudo cp ops/systemd/* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now gitops-pull.timer
```

6) First converge
```bash
sudo bash /srv/vigo/ops/deploy.sh
```

7) Validate
```bash
sudo journalctl -u gitops-pull.service -f   # watch reconcile logs
docker ps                                   # traefik and stacks should be up
```

8) Browse your app
- Visit `https://app.example.com`. TLS should be issued automatically by Let’s Encrypt.
