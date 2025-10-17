#!/usr/bin/env bash
set -euo pipefail

msg(){ echo -e "[gitops] $*"; }
err(){ echo -e "[gitops][error] $*" >&2; }

# Overlay src -> dst (delete removed files, ignore .git)
overlay(){ rsync -a --delete --exclude ".git" "$1/" "$2/"; }

# Decrypt envs from $1 -> $2 using sops
decrypt_envs(){
  local src="$1" dst="$2"
  mkdir -p "$dst"
  # If directory exists but empty, this is a no-op
  while IFS= read -r -d '' f; do
    local rel=${f#"$src/"}
    local out="$dst/$rel"
    mkdir -p "$(dirname "$out")"
    if sops -d "$f" >"$out" 2>/dev/null; then
      :
    else
      # Allow plaintext envs for first-run defaults; copy through as-is
      cp "$f" "$out"
    fi
  done < <(find "$src" -type f -name '*.env' -print0)
}

# Build a Compose .env from all env/*.env (global first, then others)
build_dotenv(){
  local envdir="$1" out="$2"
  : > "$out"
  if [[ -f "$envdir/global.env" ]]; then cat "$envdir/global.env" >> "$out"; echo >> "$out"; fi
  # Append remaining .env files (excluding global.env)
  while IFS= read -r -d '' f; do
    [[ "$(basename "$f")" == "global.env" ]] && continue
    cat "$f" >> "$out"
    echo >> "$out"
  done < <(find "$envdir" -type f -name '*.env' -print0 | sort -z)
}

require_cmd(){
  command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; return 1; }
}

ensure_docker(){
  require_cmd docker || return 1
  if ! docker info >/dev/null 2>&1; then
    err "Docker daemon not running. Start it (e.g., 'systemctl start docker')."
    return 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    err "'docker compose' plugin not found. Install docker-compose-plugin."
    return 1
  fi
}

have_env_var(){
  local envfile="$1" name="$2"
  [[ -f "$envfile" ]] && grep -qE "^${name}=" "$envfile"
}
