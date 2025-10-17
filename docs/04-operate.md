# VIGO — Operate: Promote, Rollback, Update

Start here for first-time setup: docs/00-zero-to-live.md

First-time validation
1) Verify timer and logs
   ```bash
   sudo systemctl status gitops-pull.timer
   sudo journalctl -u gitops-pull.service -f
   ```
2) Verify Docker and proxy
   ```bash
   docker ps --format 'table {{.Names}}\t{{.Status}}'
   docker compose -f /srv/runtime/proxy/docker-compose.yml --project-directory /srv/runtime config >/dev/null
   ```
3) DNS and TLS
   - Confirm `A/AAAA` records point to the VPS.
   - Visit `https://<your-hostname>` and check a valid cert.
4) Private registry
   ```bash
   docker pull <one-of-your-private-images>:sha-<short> # should succeed after docker login
   ```

Promote a new build
1) Ensure your app repo published an immutable tag like `:sha-abc1234`.
2) Edit `stacks/<app>/docker-compose.yml` and update the image tag.
3) Commit and push. The VPS will pull and apply within ~60s.

Rollback
- Revert the commit that changed the image tag and push.

Rotate secret values
1) `sops env/<file>.env` (this opens an editor; on save, SOPS keeps encryption)
2) Commit and push. The timer will reconcile and restart containers as needed.

Add a new app stack
- See `docs/howto-new-app.md`.

Update Traefik or system scripts
- Modify files under `proxy/` or `ops/` and push; hosts reconcile automatically.

Check logs
```bash
sudo journalctl -u gitops-pull.service -f
docker logs <container>
```
