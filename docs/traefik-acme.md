# VIGO — Traefik + Let’s Encrypt (ACME)

Start here for first-time setup: docs/00-zero-to-live.md

Key points
- Traefik automatically gets and renews TLS certs for your domains.
- This template uses the TLS-ALPN challenge on port 443.
- `TRAEFIK_ACME_EMAIL` is required for the ACME account (renewal notices/recovery only).

Configuration in proxy/docker-compose.yml
```
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.le.acme.tlschallenge=true
      - --certificatesresolvers.le.acme.email=${TRAEFIK_ACME_EMAIL}
      - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
```

Storage and perms
- ACME account/certs are stored in `/srv/runtime/proxy/acme/acme.json` with `chmod 600`.

Staging vs production
- For initial tests (to avoid rate limits), add:
```
      - --certificatesresolvers.le.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
```

Per-app routing via labels
- Each service sets labels defining router rule (hostname) and internal port.
