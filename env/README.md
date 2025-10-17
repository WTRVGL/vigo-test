This directory holds runtime `.env` files that are committed ENCRYPTED using SOPS (with age keys).

What are SOPS and age?
- age: a modern, simple encryption tool. You generate a keypair once.
- SOPS: a config/secrets management tool that encrypts files at rest and edits them in-place.
- Result: you can commit secrets to git safely; only machines with the private key can decrypt.

Steps (one-time local setup)
1) Generate an age key locally: `age-keygen -o age.txt`
2) Copy the public key from `age.txt` (starts with `age1...`) into `.sops.yaml`:
   - `.sops.yaml` → `creation_rules[0].age: ["age1YOUR_PUBLIC_KEY_HERE"]`
3) Keep `age.txt` private. Place it for local use at `~/.config/sops/age/keys.txt` (chmod 600) and export:
   - `export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt`
   For robust detection across environments, also copy to age’s default directory used by some builds:
   - `mkdir -p $HOME/.config/age && cp $HOME/.config/sops/age/keys.txt $HOME/.config/age/keys.txt && chmod 600 $HOME/.config/age/keys.txt`
4) You will also copy its contents to each VPS at `/root/.config/sops/age/keys.txt` (chmod 600).

Create and encrypt env files
1) Create `env/global.env` and per-app files like `env/sampleapp.env`.
2) Encrypt in-place with SOPS: `sops -e -i env/global.env` and `sops -e -i env/sampleapp.env`.
3) Commit the encrypted files (they look like YAML/JSON blocks; human-unreadable).

Variables
- `env/global.env` must define: `TRAEFIK_ACME_EMAIL=you@example.com`
  - What is this? Traefik talks to Let’s Encrypt (ACME) to issue TLS certificates. The email is only for Let’s Encrypt account notices (expiry/recover).
- Examples:
  - `env/sampleapp.env`

  SAMPLEAPP_HOST=app.example.com
  SAMPLEAPP_INTERNAL_PORT=8080

  - `env/whoami.env`

  WHOAMI_HOST=whoami.example.com
  WHOAMI_INTERNAL_PORT=80

  - `env/echoserver.env`

  ECHOSERVER_HOST=echo.example.com
  ECHOSERVER_INTERNAL_PORT=80

  - `env/grafana.env`

  GRAFANA_HOST=grafana.example.com
  GRAFANA_INTERNAL_PORT=3000
  GF_SECURITY_ADMIN_USER=admin
  GF_SECURITY_ADMIN_PASSWORD=change-me

Runtime behavior
- During deploy, envs decrypt to `/srv/runtime/env/*.env` on the VPS.
- The deploy script also builds `/srv/runtime/.env` for Compose variable interpolation in labels/args.
