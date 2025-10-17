#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=/srv/vigo
RUNTIME_DIR=/srv/runtime
HOSTNAME=$(hostname)
REMOTE_BRANCH=${REMOTE_BRANCH:-main}

. "$REPO_DIR/ops/functions.sh"

cd "$REPO_DIR"

msg "Fetch $REMOTE_BRANCH…"
git fetch --quiet origin "$REMOTE_BRANCH" || true
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/$REMOTE_BRANCH" || echo "$LOCAL")
if [[ "$LOCAL" != "$REMOTE" ]]; then
  msg "Reset to origin/$REMOTE_BRANCH"
  git reset --hard "origin/$REMOTE_BRANCH"
fi

ensure_docker || { err "Docker not ready"; exit 1; }

# Retire stacks that were removed from git before syncing new files
if [[ -d "$RUNTIME_DIR/stacks" ]]; then
  declare -A DESIRED_STACKS=()
  if [[ -d "$REPO_DIR/stacks" ]]; then
    while IFS= read -r -d '' d; do
      DESIRED_STACKS[$(basename "$d")]=1
    done < <(find "$REPO_DIR/stacks" -maxdepth 1 -mindepth 1 -type d -print0)
  fi
  while IFS= read -r -d '' d; do
    stack=$(basename "$d")
    if [[ -z "${DESIRED_STACKS[$stack]:-}" ]]; then
      msg "Retire stack: ${stack}"
      compose_file="$RUNTIME_DIR/stacks/$stack/docker-compose.yml"
      if [[ -f "$compose_file" ]]; then
        docker compose -p "$stack" --project-directory "$RUNTIME_DIR" -f "$compose_file" down --remove-orphans || true
      fi
      rm -rf "$RUNTIME_DIR/stacks/$stack"
    fi
  done < <(find "$RUNTIME_DIR/stacks" -maxdepth 1 -mindepth 1 -type d -print0)
fi

msg "Prepare runtime…"
mkdir -p "$RUNTIME_DIR"
overlay "$REPO_DIR" "$RUNTIME_DIR"

if [[ -d "$REPO_DIR/hosts/$HOSTNAME" ]]; then
  msg "Host overlay: $HOSTNAME"
  overlay "$REPO_DIR/hosts/$HOSTNAME" "$RUNTIME_DIR"
fi

# Ensure Traefik ACME store exists with correct perms
mkdir -p "$RUNTIME_DIR/proxy/acme"
[[ -f "$RUNTIME_DIR/proxy/acme/acme.json" ]] || touch "$RUNTIME_DIR/proxy/acme/acme.json"
chmod 600 "$RUNTIME_DIR/proxy/acme/acme.json"

# Decrypt envs and build a Compose .env for interpolation
if command -v sops >/dev/null 2>&1; then
  if [[ -d "$REPO_DIR/env" ]]; then
    msg "Decrypt envs"
    decrypt_envs "$REPO_DIR/env" "$RUNTIME_DIR/env"
    msg "Build .env for compose"
    build_dotenv "$RUNTIME_DIR/env" "$RUNTIME_DIR/.env"
  fi
fi

# Optional: allow running without the proxy for quick tests
DISABLE_PROXY=${DISABLE_PROXY:-}
# Default to auto-freeing 80/443 to keep first-run zero-touch
AUTO_FREE_PORTS=${AUTO_FREE_PORTS:-1}

# If proxy is enabled, ensure ports 80/443 are free, or optionally free them
if [[ -z "$DISABLE_PROXY" || "$DISABLE_PROXY" == "0" || "$DISABLE_PROXY" == "false" ]]; then
  # Helper to show processes bound to a port
  show_port(){ local p="$1"; (ss -ltnp 2>/dev/null || true) | awk -v p=":$p" '$4 ~ p {print $0}'; }
  in_use() { local p="$1"; show_port "$p" | grep -q ":$p"; }
  PROXY_COMPOSE_PROJECT=proxy
  PROXY_CONTAINER_NAME="${PROXY_COMPOSE_PROJECT}-traefik-1"
  is_running_container(){
    local name="$1"
    docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -qi '^true$'
  }
  busy_port_containers(){
    docker ps --format '{{.Names}} {{.Ports}}' \
      | awk '/:80->|:443->/ {print $1}' \
      | sort -u
  }
  if in_use 80 || in_use 443; then
    err "Ports 80/443 are in use on the host."
    err "Port 80: $(show_port 80 | tr '\n' ' ' | sed 's/ *$//')"
    err "Port 443: $(show_port 443 | tr '\n' ' ' | sed 's/ *$//')"
    if is_running_container "$PROXY_CONTAINER_NAME"; then
      msg "Managed proxy ($PROXY_CONTAINER_NAME) already listening on 80/443; continuing."
    else
    if [[ -n "$AUTO_FREE_PORTS" && ( "$AUTO_FREE_PORTS" == "1" || "$AUTO_FREE_PORTS" == "true" ) ]]; then
      msg "Attempting to stop common services that occupy 80/443 (nginx, apache2, caddy, traefik)"
      for svc in nginx apache2 caddy traefik; do
        if systemctl list-unit-files | grep -q "^${svc}\.service"; then
          systemctl stop "$svc" 2>/dev/null || true
          systemctl disable "$svc" 2>/dev/null || true
        fi
      done
      for c in $(busy_port_containers); do
        [[ "$c" == "$PROXY_CONTAINER_NAME" ]] && continue
        msg "Stopping container publishing 80/443: $c"
        docker stop "$c" >/dev/null 2>&1 || true
      done
      sleep 1
      if in_use 80 || in_use 443; then
        err "Ports still busy after attempting to stop services."
        err "Set DISABLE_PROXY=1 to skip Traefik, or free the ports and retry."
        exit 1
      else
        msg "Ports 80/443 are now free. Proceeding."
      fi
    else
      err "Free these ports (stop nginx/apache/caddy) or set AUTO_FREE_PORTS=1 to let this script stop them."
      err "Alternatively set DISABLE_PROXY=1 to run stacks that do not require Traefik."
      exit 1
    fi
    fi
  fi
fi

# Sanity checks (proxy only if enabled)
if [[ -z "$DISABLE_PROXY" || "$DISABLE_PROXY" == "0" || "$DISABLE_PROXY" == "false" ]]; then
  [[ -f "$RUNTIME_DIR/proxy/docker-compose.yml" ]] || { err "Missing proxy/docker-compose.yml in runtime"; exit 1; }
fi

# Require ACME email to prevent confusing Traefik errors (only if proxy is enabled)
if [[ -z "$DISABLE_PROXY" || "$DISABLE_PROXY" == "0" || "$DISABLE_PROXY" == "false" ]]; then
  if ! have_env_var "$RUNTIME_DIR/.env" "TRAEFIK_ACME_EMAIL" && ! have_env_var "$RUNTIME_DIR/env/global.env" "TRAEFIK_ACME_EMAIL"; then
    err "TRAEFIK_ACME_EMAIL is not set. Add it to env/global.env (encrypted)."
    err "See docs: docs/traefik-acme.md and docs/02-setup-local.md"
    exit 1
  fi
fi

if [[ -z "$DISABLE_PROXY" || "$DISABLE_PROXY" == "0" || "$DISABLE_PROXY" == "false" ]]; then
  msg "Proxy up"
  COMPOSE_PROJECT=proxy
  pushd "$RUNTIME_DIR" >/dev/null
  if ! docker compose -p "$COMPOSE_PROJECT" --env-file "$RUNTIME_DIR/.env" -f proxy/docker-compose.yml up -d --remove-orphans; then
    err "Proxy up failed; attempting clean restart"
    docker compose -p "$COMPOSE_PROJECT" --env-file "$RUNTIME_DIR/.env" -f proxy/docker-compose.yml down --remove-orphans || true
    # Remove any stray container with the expected name if created outside compose
    docker rm -f "${COMPOSE_PROJECT}-traefik-1" >/dev/null 2>&1 || true
    # Retry after a brief pause; if network is stuck in use, it will be reused by up
    sleep 1
    docker compose -p "$COMPOSE_PROJECT" --env-file "$RUNTIME_DIR/.env" -f proxy/docker-compose.yml up -d --remove-orphans || { err "Failed to start proxy"; popd >/dev/null; exit 1; }
  fi
  popd >/dev/null
else
  msg "Proxy disabled (DISABLE_PROXY set)"
fi

STACKS_ONLY=${STACKS_ONLY:-}
IFS=',' read -r -a ONLY_ARR <<< "$STACKS_ONLY"

for stack in "$RUNTIME_DIR"/stacks/*; do
  [[ -f "$stack/docker-compose.yml" ]] || continue
  stack_name=$(basename "$stack")
  # Filter by STACKS_ONLY if provided
  if [[ -n "$STACKS_ONLY" ]]; then
    skip=1
    for s in "${ONLY_ARR[@]}"; do
      [[ "$stack_name" == "${s}" ]] && skip=0 && break
    done
    (( skip == 1 )) && { msg "Skip ${stack_name} (not in STACKS_ONLY)"; continue; }
  fi
  msg "Stack: ${stack_name}"
  # If the stack references an env named after the stack and it doesn't exist, skip gracefully
  expected_env="$RUNTIME_DIR/env/${stack_name}.env"
  if grep -q "${stack_name}\.env" "$stack/docker-compose.yml" 2>/dev/null && [[ ! -f "$expected_env" ]]; then
    msg "Skip ${stack_name} (missing env/${stack_name}.env)"
    continue
  fi
  pushd "$RUNTIME_DIR" >/dev/null
  # Use a path relative to the runtime dir so env_file relative paths resolve correctly
  rel_stack=${stack#"$RUNTIME_DIR/"}
  docker compose -p "$stack_name" --env-file "$RUNTIME_DIR/.env" -f "$rel_stack/docker-compose.yml" up -d --remove-orphans || { err "Failed to start stack ${stack_name}"; popd >/dev/null; exit 1; }
  popd >/dev/null
done

msg "Done"
