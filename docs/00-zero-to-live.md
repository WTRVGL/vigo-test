# VIGO — Zero to Live (Copy/Paste)

This is the one page you need to go from nothing to a running VPS with Traefik, your stacks, and SOPS‑encrypted env files. Replace placeholders like ORG/REPO and you@example.com.

Prereqs
- Own a domain and point A/AAAA records for your app hostnames to the VPS IP.
- VPS: Ubuntu 22.04+/Debian 12+, root SSH access, ports 80/443 open.
- If another service (nginx/apache/caddy) is using 80/443, stop it or set `AUTO_FREE_PORTS=1` when running deploy to let the script stop them for you.
- A container registry account if you need private images (e.g., GHCR/GitLab).

1) Create your private infra repo
- Use this template, then push to your private repo (skip if done):
  - On GitHub: “Use this template” → Create private repo OR fork, then set to private.
  - Locally (optional): `git remote set-url origin git@github.com:ORG/REPO.git`

2) Laptop: install tools, generate age key, encrypt envs
- macOS (Homebrew) or Ubuntu/Debian (apt with release fallback) — pick ONE block.

macOS
```bash
brew install age sops
```

Ubuntu/Debian
```bash
sudo apt-get update && sudo apt-get install -y age sops || true
# Fallback if apt has no sops/age (amd64; use arm64 on ARM):
SOPS_VER=v3.8.1
curl -fsSL https://github.com/getsops/sops/releases/download/$SOPS_VER/sops-$SOPS_VER.linux.amd64 | sudo tee /usr/local/bin/sops >/dev/null
sudo chmod +x /usr/local/bin/sops
curl -fsSL https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz \
  | sudo tar -xz -C /usr/local/bin --strip-components=1 age/age age/age-keygen
```

Generate age keypair
```bash
age-keygen -o age.txt
printf "\nYour public key:\n" && grep '^# public key:' age.txt | sed 's/# public key: //'
```

Wire `.sops.yaml` to your public key
```bash
# Edit .sops.yaml and replace age1YOUR_PUBLIC_KEY_HERE with your public key
sed -i'' -e "s/age1YOUR_PUBLIC_KEY_HERE/$(grep '^# public key:' age.txt | sed 's/# public key: //')/" .sops.yaml
```

Create minimal envs and encrypt
```bash
mkdir -p env
cat > env/global.env <<'EOF'
TRAEFIK_ACME_EMAIL=you@example.com
EOF
sops -e -i env/global.env

# Update sample stack envs (edit the hostnames to your domain, then encrypt)
$EDITOR env/whoami.env
$EDITOR env/echoserver.env
sops -e -i env/whoami.env
sops -e -i env/echoserver.env
```

Commit and push
```bash
git add .
git commit -m "Initial: keys + encrypted envs"
git push origin main
```

3) VPS: install Docker + compose plugin, age, sops
```bash
sudo apt-get update && sudo apt-get install -y git ca-certificates curl gnupg rsync
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(. /etc/os-release; echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

# sops (install from GitHub release, auto-detect arch)
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

4) VPS: clone YOUR private infra repo (pick SSH or HTTPS+PAT)
SSH deploy key (recommended)
```bash
sudo -i
ssh-keygen -t ed25519 -C "vigo-deploy" -f /root/.ssh/id_ed25519 -N ""
ssh-keyscan github.com >> /root/.ssh/known_hosts
chmod 700 /root/.ssh && chmod 600 /root/.ssh/id_ed25519 /root/.ssh/known_hosts
cat /root/.ssh/id_ed25519.pub   # paste into GitHub → Repo → Settings → Deploy keys (read-only)
mkdir -p /srv /srv/runtime && cd /srv
export GIT_SSH_COMMAND='ssh -o IdentitiesOnly=yes -i /root/.ssh/id_ed25519'
git clone git@github.com:ORG/REPO.git vigo
```

HTTPS + PAT
```bash
sudo -i
export GITHUB_USER=<your-username>
read -s GITHUB_PAT && export GITHUB_PAT
mkdir -p /srv /srv/runtime && cd /srv
git clone https://$GITHUB_USER:$GITHUB_PAT@github.com/ORG/REPO.git vigo
unset GITHUB_PAT
```

If SSH says “Permission denied (publickey)”
- Make sure you added the VPS public key to Repo → Settings → Deploy keys for the exact repo and checked “Allow read access”.
- Test access with your key only: `GIT_SSH_COMMAND='ssh -v -o IdentitiesOnly=yes -i /root/.ssh/id_ed25519' git ls-remote git@github.com:ORG/REPO.git HEAD`
- If your org enforces SSO and you used a user SSH key or PAT, authorize it for the org under your GitHub Settings.

5) VPS: place the age PRIVATE key for root
```bash
install -d -m 700 /root/.config/sops/age
install -m 600 /dev/stdin /root/.config/sops/age/keys.txt <<'EOF'
# paste the entire line from your local age.txt that starts with AGE-SECRET-KEY-1
AGE-SECRET-KEY-1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
EOF
age-keygen -y /root/.config/sops/age/keys.txt   # prints an age1…; must match recipients in your env files
```

6) VPS: private registry login (if using private images)
GHCR (GitHub Container Registry)
```bash
# Create a token first (recommended: Classic PAT for GHCR)
# GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate
#  - Scopes: read:packages (required). If private org images still fail to pull, add repo (Read)
#  - If your org enforces SSO, click “Configure SSO” on the token and authorize it for the org

# Login as root so pulls work under systemd
# Option A (interactive):
docker login ghcr.io -u <your-github-username>
# paste PAT at the password prompt

# Option B (one-liner, no prompt):
echo 'YOUR_PAT' | docker login ghcr.io -u <your-github-username> --password-stdin
```
More registries and details (including fine‑grained PAT caveats): docs/registry.md

7) VPS: enable GitOps timer and run first converge
```bash
cd /srv/vigo
sudo cp ops/systemd/* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now gitops-pull.timer
sudo bash /srv/vigo/ops/deploy.sh
```

You should see `proxy-traefik-1`, `whoami`, `echoserver`, plus the direct demos (`whoami-direct`, `echoserver-direct`) start automatically. The direct demos expose HTTP on ports 8081/8082 for an instant smoke test.

If ports 80/443 are already in use (e.g., nginx installed by your provider), either stop those services first or run:
```bash
AUTO_FREE_PORTS=1 sudo bash /srv/vigo/ops/deploy.sh
```
To temporarily skip Traefik and test direct samples (already included):
```bash
DISABLE_PROXY=1 STACKS_ONLY=whoami-direct,echoserver-direct sudo bash /srv/vigo/ops/deploy.sh
```

8) Validate and troubleshoot
```bash
sudo journalctl -u gitops-pull.service -f   # reconcile logs
sudo docker ps                               # traefik + your stacks up
# TLS issues? ensure DNS points to VPS, and TRAEFIK_ACME_EMAIL is in env/global.env (encrypted).
# Quick smoke (no DNS needed):
curl http://<vps-ip>:8081   # whoami-direct
curl http://<vps-ip>:8082   # echoserver-direct
```

Frequently hit gotchas
- “no identity matched any of the recipients”:
  - You don’t have the age private key that matches the file’s `age1…` recipient; put it at `/root/.config/sops/age/keys.txt`.
  - Verify with `age-keygen -y /root/.config/sops/age/keys.txt`.
- `sudo sops` ignores your user’s key:
  - Running as root won’t see your user env vars; put the key under root, or run `sudo -E` with `SOPS_AGE_KEY_FILE`.
- Private repo won’t clone:
  - Use SSH deploy key (recommended) or HTTPS+PAT with `repo` read scope. See step 4.
- Docker compose not found:
  - Use Docker from the official repo; verify with `docker compose version`.
 - "port is already allocated" on 80/443:
   - Expected if `proxy-traefik-1` is already running; the deploy script continues automatically now.
   - If another service or container owns the ports, either stop it (nginx/apache/caddy) or run with `AUTO_FREE_PORTS=1` to let the script stop known services/containers. You can also set `DISABLE_PROXY=1` to skip Traefik for a quick test.

Next steps
- Add additional env files under `env/` and encrypt with `sops -e -i env/<app>.env`.
- Add new stacks under `stacks/<app>` using `templates/stacks/_template` as a starting point.
