#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a fresh Ubuntu/Debian VPS
# - Installs dependencies
# - Clones this infra repo to /srv/vigo
# - Ensures docker is enabled
# - Sets up GitOps systemd timer
# - Guides on placing the AGE private key and doing docker login

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)" >&2
  exit 1
fi

INFRA_REPO_URL="${INFRA_REPO_URL:-}"   # e.g. https://github.com/WTRVGL/VIGO.git
REGISTRY="${REGISTRY:-}"                # e.g. ghcr.io
REGISTRY_USERNAME="${REGISTRY_USERNAME:-}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-}"

if [[ -z "$INFRA_REPO_URL" ]]; then
  echo "Set INFRA_REPO_URL to your repo URL (e.g., export INFRA_REPO_URL=...)" >&2
  exit 1
fi

echo "[bootstrap] Installing packages..."
apt-get update -y
apt-get install -y git ca-certificates curl gnupg rsync

# Install Docker from the official repo to ensure compose plugin availability
if ! command -v docker >/dev/null 2>&1; then
  echo "[bootstrap] Installing Docker Engine from official repo"
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg" | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(. /etc/os-release; echo "$VERSION_CODENAME") stable" \
    >/etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
    echo "[bootstrap][warn] Failed to install Docker Engine packages, falling back to distro docker.io"
    apt-get install -y docker.io
  }
fi

echo "[bootstrap] Enabling docker..."
systemctl enable --now docker || true

# Install age and sops (sops from release; age via apt or release)
ARCH=$(dpkg --print-architecture)
SOPS_VER=${SOPS_VER:-v3.11.0}
AGE_VER=${AGE_VER:-v1.1.1}

need_cmd(){ command -v "$1" >/dev/null 2>&1; }

if ! need_cmd sops; then
  echo "[bootstrap] Installing sops ${SOPS_VER} from GitHub release"
  case "$ARCH" in
    amd64|x86_64) SOPS_URL="https://github.com/getsops/sops/releases/download/${SOPS_VER}/sops-${SOPS_VER}.linux.amd64" ;;
    arm64|aarch64) SOPS_URL="https://github.com/getsops/sops/releases/download/${SOPS_VER}/sops-${SOPS_VER}.linux.arm64" ;;
    *) echo "[bootstrap][error] Unsupported arch for sops: $ARCH" >&2; exit 1 ;;
  esac
  curl -fsSL "$SOPS_URL" -o /usr/local/bin/sops
  chmod +x /usr/local/bin/sops
fi

if ! need_cmd age; then
  echo "[bootstrap] Installing age ${AGE_VER} from GitHub release"
  case "$ARCH" in
    amd64|x86_64) AGE_TAR="age-${AGE_VER}-linux-amd64.tar.gz" ;;
    arm64|aarch64) AGE_TAR="age-${AGE_VER}-linux-arm64.tar.gz" ;;
    *) echo "[bootstrap][error] Unsupported arch for age: $ARCH" >&2; exit 1 ;;
  esac
  TMPDIR=$(mktemp -d)
  curl -fsSL "https://github.com/FiloSottile/age/releases/download/${AGE_VER}/${AGE_TAR}" -o "$TMPDIR/age.tgz"
  tar -xzf "$TMPDIR/age.tgz" -C "$TMPDIR"
  install -m 0755 "$TMPDIR/age/age" /usr/local/bin/age
  install -m 0755 "$TMPDIR/age/age-keygen" /usr/local/bin/age-keygen
  rm -rf "$TMPDIR"
fi

echo "[bootstrap] Preparing /srv and cloning repo..."
mkdir -p /srv /srv/runtime
if [[ ! -d /srv/vigo/.git ]]; then
  echo "[bootstrap] Cloning infra repo: $INFRA_REPO_URL"
  if ! git clone "$INFRA_REPO_URL" /srv/vigo; then
    echo "[bootstrap][error] Failed to clone $INFRA_REPO_URL" >&2
    echo "[bootstrap] If your repo is private, use one of these options:" >&2
    echo "  - SSH (recommended):" >&2
    echo "      1) On the VPS: ssh-keygen -t ed25519 -C 'vigo-deploy' -f /root/.ssh/id_ed25519 -N ''" >&2
    echo "      2) Add /root/.ssh/id_ed25519.pub as a read-only Deploy Key in your GitHub repo" >&2
    echo "      3) Ensure GitHub host key is known: ssh-keyscan github.com >> /root/.ssh/known_hosts" >&2
    echo "      4) Clone: INFRA_REPO_URL='git@github.com:<org>/<repo>.git'" >&2
    echo "  - HTTPS + PAT (repo read scope):" >&2
    echo "      export INFRA_REPO_URL='https://<username>:<PAT>@github.com/<org>/<repo>.git'" >&2
    echo "Re-run this script after setting a working INFRA_REPO_URL." >&2
    exit 1
  fi
else
  echo "[bootstrap] Repo already present at /srv/vigo"
fi

echo "[bootstrap] SOPS age key location: /root/.config/sops/age/keys.txt"
mkdir -p /root/.config/sops/age
chmod 700 /root/.config/sops/age
if [[ ! -f /root/.config/sops/age/keys.txt ]]; then
  echo "# Paste your AGE-SECRET-KEY-1... here" > /root/.config/sops/age/keys.txt
  chmod 600 /root/.config/sops/age/keys.txt
  echo "[bootstrap] Placeholder created. Edit /root/.config/sops/age/keys.txt and paste your private key."
else
  chmod 600 /root/.config/sops/age/keys.txt
fi

echo "[bootstrap] SSH setup for private repo cloning (optional)"
install -d -m 700 /root/.ssh
if ! grep -q github.com /root/.ssh/known_hosts 2>/dev/null; then
  ssh-keyscan github.com >> /root/.ssh/known_hosts || true
fi
chmod 700 /root/.ssh
chmod 600 /root/.ssh/known_hosts 2>/dev/null || true
if [[ -f /root/.ssh/id_ed25519 ]]; then
  # Ensure SSH prefers the deploy key when talking to GitHub
  cat > /root/.ssh/config <<'EOF'
Host github.com
  IdentityFile /root/.ssh/id_ed25519
  IdentitiesOnly yes
EOF
  chmod 600 /root/.ssh/config
fi

if [[ -n "$REGISTRY" && -n "$REGISTRY_USERNAME" && -n "$REGISTRY_PASSWORD" ]]; then
  echo "[bootstrap] Logging into registry $REGISTRY as $REGISTRY_USERNAME"
  echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY" -u "$REGISTRY_USERNAME" --password-stdin
else
  echo "[bootstrap] Skipping registry login. Run: docker login <registry> -u <user> -p <token>"
fi

echo "[bootstrap] Installing systemd units..."
cp /srv/vigo/ops/systemd/* /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now gitops-pull.timer

echo "[bootstrap] Done. Next steps:"
echo "  1) Ensure /root/.config/sops/age/keys.txt contains your AGE-SECRET-KEY and is chmod 600"
echo "  2) docker login <your-registry> as root (read-only token)"
echo "  3) First converge: bash /srv/vigo/ops/deploy.sh && journalctl -u gitops-pull.service -f"
