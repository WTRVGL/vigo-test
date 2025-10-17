Per-host overrides live here under a directory named exactly as the VPS hostname.

Example
- `hosts/my-vps/proxy/docker-compose.yml` to override proxy config (rare).
- `hosts/my-vps/stacks/sampleapp/docker-compose.yml` to point to a different image tag.
- `hosts/my-vps/env/sampleapp.env` to override env vars for this host.

During deploy, the host-specific tree overlays `/srv/runtime` after the base repo.

