# VIGO — Local Setup (Your Laptop)

Start here for first-time setup: docs/00-zero-to-live.md

This sets up your workstation to manage encrypted env files and push infra changes.

0) Clone this infra repo
```bash
git clone https://github.com/WTRVGL/VIGO.git vigo && cd vigo
```

1) Install tools (age + SOPS)
- macOS (Homebrew):
  ```bash
  brew install age sops
  ```
- Ubuntu/Debian (prefer release for sops; age via apt or release):
  ```bash
  # sops (auto-detect arch, install from GitHub release)
  SOPS_VER=v3.11.0
  ARCH=$(dpkg --print-architecture)
  case "$ARCH" in amd64) SUF=amd64;; arm64) SUF=arm64;; *) echo "unsupported arch: $ARCH"; exit 1;; esac
  curl -fsSL "https://github.com/getsops/sops/releases/download/$SOPS_VER/sops-$SOPS_VER.linux.$SUF" | sudo tee /usr/local/bin/sops >/dev/null
  sudo chmod +x /usr/local/bin/sops

  # age (try apt, fallback to release)
  sudo apt-get update && sudo apt-get install -y age || true
  if ! command -v age >/dev/null; then
    AGE_VER=v1.1.1
    case "$ARCH" in amd64) AGE_TAR="age-$AGE_VER-linux-amd64.tar.gz";; arm64) AGE_TAR="age-$AGE_VER-linux-arm64.tar.gz";; esac
    curl -fsSL "https://github.com/FiloSottile/age/releases/download/$AGE_VER/$AGE_TAR" \
      | sudo tar -xz -C /usr/local/bin --strip-components=1 age/age age/age-keygen
  fi
  ```
- Arch:
  ```bash
  sudo pacman -S --needed age sops
  ```
- Windows:
  - Scoop: `scoop install age sops`
  - Chocolatey: `choco install age sops`
  - Or use WSL and follow the Ubuntu steps.

Verify:
```bash
age --version && sops --version
```

2) Generate an age keypair
```bash
age-keygen -o age.txt
```
Open `age.txt`. Copy the public key line (starts with `age1...`). Keep this file private.

2.5) Place your private key where SOPS finds it (local)
```bash
mkdir -p ~/.config/sops/age
cp ./age.txt ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```
Verify the public key matches:
```bash
age-keygen -y ~/.config/sops/age/keys.txt
# should print the same recipient you’ll put in .sops.yaml (age1...)
```
Robust detection across environments:
```bash
# Explicitly tell sops where the key is
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"

# Also populate age's default dir used by some builds
mkdir -p "$HOME/.config/age"
cp "$HOME/.config/sops/age/keys.txt" "$HOME/.config/age/keys.txt"
chmod 600 "$HOME/.config/age/keys.txt"
```

3) Configure `.sops.yaml`
Edit `.sops.yaml` and replace the placeholder public key:
```yaml
creation_rules:
  - path_regex: env/.*\.env$
    age: ["age1YOUR_PUBLIC_KEY_HERE"]
```

Notes
- You can allow multiple operators by listing multiple `age: ["age1...", "age1..."]` keys.
- Only the public keys go in repo; private keys stay local and on VPS root.

4) Create env files (plaintext placeholders)
```bash
cat > env/global.env <<'EOF'
TRAEFIK_ACME_EMAIL=you@example.com
EOF

cat > env/sampleapp.env <<'EOF'
SAMPLEAPP_HOST=app.example.com
SAMPLEAPP_INTERNAL_PORT=8080
EOF
```

5) Encrypt in place with SOPS
```bash
sops -e -i env/global.env
sops -e -i env/sampleapp.env
```

6) Verify encryption works
```bash
head -n 5 env/global.env          # looks encrypted (garbled, with sops metadata)
sops -d env/global.env | head -n 5 # decrypts to plaintext
```
If decryption fails
```bash
# 1) Ensure the key file exists and has correct perms
grep -q '^AGE-SECRET-KEY-1' "$HOME/.config/sops/age/keys.txt" && ls -l "$HOME/.config/sops/age/keys.txt"

# 2) Ensure sops can find it and retry
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
mkdir -p "$HOME/.config/age" && cp "$HOME/.config/sops/age/keys.txt" "$HOME/.config/age/keys.txt" && chmod 600 "$HOME/.config/age/keys.txt"
sops -d env/global.env | head -n 5

# 3) Confirm recipient matches .sops.yaml
age-keygen -y "$HOME/.config/sops/age/keys.txt"
# Must equal the age1... value in .sops.yaml
```

7) Commit and push
```bash
git add .
git commit -m "Add encrypted envs"
git push
```

8) Keep your private key safe
- Store `age.txt` in a password manager or secure vault.
- You will copy the private key onto each VPS at `/root/.config/sops/age/keys.txt`.

Key discovery and sudo
- By default, SOPS looks for an age key at `~/.config/sops/age/keys.txt`.
- If you run `sudo sops`, it runs as root and won’t see your user’s key or env vars. Either:
  - Put a copy at `/root/.config/sops/age/keys.txt`, or
  - Use `sudo -E` after exporting `SOPS_AGE_KEY_FILE`, or
  - Inline: `sudo SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt sops -d env/foo.env`

Optional: Local validation
- Lint Traefik compose:
  ```bash
  docker compose -f proxy/docker-compose.yml config >/dev/null
  ```
- Lint each stack (adjust for your app names):
  ```bash
  docker compose -f stacks/sampleapp/docker-compose.yml --project-directory . config >/dev/null
  ```
- Run a quick preflight (checks tools, `.sops.yaml`, and env decryption):
  ```bash
  bash ops/preflight-local.sh
  ```
