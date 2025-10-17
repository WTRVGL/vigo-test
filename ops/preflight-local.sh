#!/usr/bin/env bash
set -euo pipefail

YELLOW="\033[33m"; GREEN="\033[32m"; RED="\033[31m"; NC="\033[0m"
info(){ echo -e "${YELLOW}[preflight]${NC} $*"; }
ok(){ echo -e "${GREEN}[ok]${NC} $*"; }
fail(){ echo -e "${RED}[fail]${NC} $*"; }

# 1) Repo sanity
if [[ ! -f README.md || ! -f .sops.yaml ]]; then
  fail "Run from repo root (README.md and .sops.yaml required)."
  exit 1
fi
ok "In repo root"

# 2) Tooling
need_cmd(){ command -v "$1" >/dev/null 2>&1 || { fail "Missing command: $1"; MISSING=1; }; }
MISSING=0
for c in git age sops; do need_cmd "$c"; done
if [[ ${MISSING} -eq 1 ]]; then
  info "Install tools: macOS 'brew install age sops' | Linux: install sops from releases (see docs/02-setup-local.md); age via apt or release"
  exit 1
fi
ok "Tools present (git, age, sops)"

# 3) .sops.yaml configured
if ! grep -qE 'age1(?!YOUR_PUBLIC_KEY_HERE)[a-z0-9]+' .sops.yaml 2>/dev/null; then
  fail ".sops.yaml does not contain a real age public key (still placeholder?)"
  info "Edit .sops.yaml and set your public key (age1...)"
  exit 1
fi
ok ".sops.yaml contains a public key"

# 4) Env files (optional but recommended)
shopt -s nullglob
env_files=(env/*.env)
if (( ${#env_files[@]} == 0 )); then
  info "No env/*.env files yet. Create and encrypt per docs/02-setup-local.md"
else
  for f in "${env_files[@]}"; do
    # Detect encryption markers or try to decrypt
    if grep -q 'sops:' "$f" || grep -q 'ENC\[' "$f"; then
      if sops -d "$f" >/dev/null 2>&1; then
        ok "Encrypted and decryptable: $f"
      else
        info "File looks encrypted but cannot decrypt: $f"
        info "Ensure your local age private key matches the public key in .sops.yaml"
        info "SOPS looks for a key at: \"$SOPS_AGE_KEY_FILE\" (if set), ~/.config/sops/age/keys.txt, or ~/.config/age/keys.txt"
        info "Fix (local): export SOPS_AGE_KEY_FILE=\"$HOME/.config/sops/age/keys.txt\""
        info "Also: mkdir -p ~/.config/age && cp ~/.config/sops/age/keys.txt ~/.config/age/keys.txt && chmod 600 ~/.config/age/keys.txt"
        exit 1
      fi
    else
      fail "Not encrypted: $f"
      info "Encrypt in place: sops -e -i $f"
      exit 1
    fi
  done

  # Check for required Traefik variable in global.env if present
  if [[ -f env/global.env ]]; then
    if sops -d env/global.env 2>/dev/null | grep -q '^TRAEFIK_ACME_EMAIL='; then
      ok "TRAEFIK_ACME_EMAIL present in env/global.env"
    else
      fail "TRAEFIK_ACME_EMAIL missing in env/global.env"
      info "Add: TRAEFIK_ACME_EMAIL=you@example.com (then re-encrypt if needed)"
      exit 1
    fi
  else
    info "Create env/global.env (encrypted) with TRAEFIK_ACME_EMAIL=..."
  fi
fi

ok "Local preflight passed"
