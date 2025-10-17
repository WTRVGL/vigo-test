# VIGO — How to Add a New App

Start here for first-time setup: docs/00-zero-to-live.md

1) Prepare an app image
- Use templates under `templates/apps/` for Dockerfiles (Node / ASP.NET Core).
- Publish images via your CI to your private registry with `:sha-<short>` tags.

2) Create a stack
```bash
mkdir -p stacks/myapp
cp templates/stacks/_template/docker-compose.yml stacks/myapp/docker-compose.yml
```
Edit fields:
- `image: <registry>/<org>/myapp:sha-<short>`
- Labels use `${MYAPP_HOST}` and `${MYAPP_INTERNAL_PORT}`; set these in `env/myapp.env`.

3) Add env file (encrypted)
```bash
cat > env/myapp.env <<'EOF'
MYAPP_HOST=myapp.example.com
MYAPP_INTERNAL_PORT=8080
EOF
sops -e -i env/myapp.env
```

4) Commit and push
- The VPS will reconcile and bring the new stack up automatically.

5) DNS
- Add `myapp.example.com` (A/AAAA) to your VPS IP.
