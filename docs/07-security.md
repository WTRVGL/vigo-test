# VIGO — Security Notes

Start here for first-time setup: docs/00-zero-to-live.md

SOPS/age keys
- Generate one age keypair per operator or per org; distribute private key only to trusted endpoints (VPS root).
- Backup the private key securely; losing it means you can’t decrypt committed secrets.

Least privilege registry tokens
- Use read-only PATs for VPS pulls (e.g., GHCR `read:packages` only).
- Rotate tokens periodically and after staff changes.

Traefik ACME store
- File `proxy/acme/acme.json` is created on the VPS at `/srv/runtime/proxy/acme/acme.json` with `chmod 600`.
- Back up this file; it contains your issued certs/keys.

Network
- Expose only ports 80/443 on the VPS; apps are behind Traefik.
- Use Traefik middleware for additional headers/rate limits if needed.

Auditing
- All changes are git-based. Protect main branch and require reviews.
