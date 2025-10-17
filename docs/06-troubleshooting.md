# VIGO — Troubleshooting

Start here for first-time setup: docs/00-zero-to-live.md

Traefik not issuing TLS certs
- Check `TRAEFIK_ACME_EMAIL` exists in `/srv/runtime/env/global.env`.
- DNS A/AAAA must point to the VPS, ports 80/443 open.
- View logs: `docker logs $(docker ps -q -f name=traefik)`.
- For testing against Let’s Encrypt staging, add Traefik flag `--certificatesresolvers.le.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory` in `proxy/docker-compose.yml`.

Cannot pull private images
- Run `sudo docker login <registry>` on the VPS as root (the service runs as root).
- If using GHCR, token needs `read:packages`.

Env decryption fails
- Ensure `/root/.config/sops/age/keys.txt` contains your AGE-SECRET-KEY and is `chmod 600`.
- Install `sops` on the VPS.
- Error: `no identity matched any of the recipients`
  - The file was encrypted to `age1...` recipients. You must have the matching age private key.
  - Put the key here for root: `/root/.config/sops/age/keys.txt`.
  - If running `sudo sops ...` from a user shell, your env vars are not preserved. Either use `sudo -E`, or prefix the command with `sudo SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt ...`.
  - Verify your key: `age-keygen -y /root/.config/sops/age/keys.txt` should print a public key found in the file’s `sops:` recipients list.
  - If you don’t have a matching key, you cannot decrypt. Ask a maintainer to add your public key to `.sops.yaml` and re‑encrypt.

- Local (your laptop)
  - Ensure your private key exists and has correct perms:
    ```bash
    grep -q '^AGE-SECRET-KEY-1' "$HOME/.config/sops/age/keys.txt" && ls -l "$HOME/.config/sops/age/keys.txt"
    ```
  - Make sops find it reliably across environments:
    ```bash
    export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
    mkdir -p "$HOME/.config/age"
    cp "$HOME/.config/sops/age/keys.txt" "$HOME/.config/age/keys.txt"
    chmod 600 "$HOME/.config/age/keys.txt"
    ```
  - Verify recipient matches `.sops.yaml` and retry decryption:
    ```bash
    age-keygen -y "$HOME/.config/sops/age/keys.txt"
    sops -d env/global.env | head -n 5
    ```

- VPS (as root)
  - Ensure `/root/.config/sops/age/keys.txt` contains your `AGE-SECRET-KEY-1...` and is `chmod 600`.
  - Install `sops` on the VPS (via apt or release binaries).
  - If you see `no identity matched any of the recipients`:
    - The file was encrypted to `age1...` recipients. You must have the matching age private key.
    - Put the key at `/root/.config/sops/age/keys.txt` so `sudo` and systemd see it.
    - If running `sudo sops ...` from a user shell, env vars aren’t preserved. Use `sudo -E`, or prefix: `sudo SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt sops -d ...`.
    - Verify key: `age-keygen -y /root/.config/sops/age/keys.txt` prints an `age1...` that appears in the file’s recipients.
    - If not your key, ask a maintainer to add your public key to `.sops.yaml` and re‑encrypt.

Compose labels not interpolating variables
- The deploy script builds `/srv/runtime/.env` from decrypted `env/*.env`.
- Ensure the variable names used in labels exist in the env files.

Host-specific overlay not applied
- Directory must be `hosts/<output of hostname>`.
- Files under that tree overlay `/srv/runtime` after the base copy.

Env file not found (e.g., `env file /env/global.env not found`)
- Cause: relative `env_file:` paths may be resolved incorrectly if the compose invocation doesn’t run from `/srv/runtime`.
- Fix:
  ```bash
  cd /srv/runtime
  docker compose -f stacks/<app>/docker-compose.yml config >/dev/null  # validates paths
  docker compose -f stacks/<app>/docker-compose.yml up -d --remove-orphans
  ```
- The deploy script runs compose from `/srv/runtime` so `env_file: ../../env/*.env` resolves to `/srv/runtime/env/*.env`.

Stack missing its own env file (e.g., `env file /srv/runtime/env/echoserver.env not found`)
- Cause: some stacks require an additional env file named after the stack (e.g., `echoserver.env`).
- Fix on laptop:
  ```bash
  cat > env/echoserver.env <<'EOF'
  ECHOSERVER_HOST=echo.example.com
  ECHOSERVER_INTERNAL_PORT=80
  EOF
  sops -e -i env/echoserver.env
  git add env/echoserver.env && git commit -m "echoserver: add env" && git push
  ```
- Then on VPS: `sudo bash /srv/vigo/ops/deploy.sh`
- The deploy script now skips stacks that reference `<stack>.env` when that file is missing, instead of failing the entire deploy.

Missing interpolation vars (e.g., `TRAEFIK_ACME_EMAIL is missing a value`)
- Cause: compose couldn’t see your variables when parsing files.
- Fix:
  - Verify the runtime .env: `grep ^TRAEFIK_ACME_EMAIL= /srv/runtime/.env`
  - Verify decrypted env: `head -n 5 /srv/runtime/env/global.env`
  - Run compose with the env file explicitly: `docker compose --env-file /srv/runtime/.env -f /srv/runtime/proxy/docker-compose.yml config >/dev/null`
  - Re-run deploy: `sudo bash /srv/vigo/ops/deploy.sh` (the script now passes `--env-file` explicitly).

Container name conflict (e.g., ": name is already in use")
- Cause: a stray container exists with the same compose‑derived name (e.g., `runtime-traefik-1`).
- Fix quickly (proxy example):
  ```bash
  docker rm -f runtime-traefik-1 || true
  docker compose -f /srv/runtime/proxy/docker-compose.yml --project-directory /srv/runtime up -d --remove-orphans
  ```
- The deploy script now uses `--remove-orphans` and will try a clean restart if the first attempt fails.

Port 80/443 already allocated
- Causes:
  - The managed Traefik container (`proxy-traefik-1`) is already running — this is expected after the first converge.
  - Another service on the host (e.g., nginx/apache/caddy) or a stray container is binding port 80 and/or 443.
- Fix options:
  - No action needed if the managed Traefik container is the one holding the ports; the deploy script now continues in that case.
  - Stop/disable system services manually: `systemctl stop nginx && systemctl disable nginx` (or apache2/caddy).
  - Let the deploy script stop known services and offending containers for you by setting `AUTO_FREE_PORTS=1` when running `ops/deploy.sh`.
  - Temporarily skip Traefik for a quick test by setting `DISABLE_PROXY=1` and use a direct sample (e.g., `STACKS_ONLY=whoami-direct`).
