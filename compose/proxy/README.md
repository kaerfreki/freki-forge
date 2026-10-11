# Reverse proxy (Caddy + Basic Auth)

Single HTTP entrypoint in front of Ollama, vLLM, and ComfyUI with HTTP Basic
Auth. Path prefixes keep it simple on a LAN; backends stay in their own compose
projects.

**This is LAN protection, not multi-tenant security.** Basic Auth over plain
HTTP is readable on the wire — use only on trusted networks, or terminate TLS
in front (Caddy can do automatic HTTPS if you put a real hostname on it).
Backend ports remain published on the host unless you lock them down yourself.
Still run **one GPU service at a time** on a single consumer card.

## Routes

| Client path | Upstream (default) | After strip |
| --- | --- | --- |
| `/ollama/*` | `host.docker.internal:11434` | `/api/...`, `/v1/...` |
| `/vllm/*` | `host.docker.internal:8000` | `/v1/...`, `/health` |
| `/comfyui/*` | `host.docker.internal:8188` | ComfyUI paths |

Example: `/ollama/api/tags` → `http://host.docker.internal:11434/api/tags`.

Backends are reached via `extra_hosts: host.docker.internal:host-gateway` so
this project does not need to join the ollama/vllm/comfyui Docker networks.
Override `OLLAMA_UPSTREAM` / `VLLM_UPSTREAM` / `COMFYUI_UPSTREAM` in `.env` if
your ports differ.

**ComfyUI UI caveat:** stripping `/comfyui` is fine for many HTTP API calls;
the browser UI often misbehaves under a subpath (static assets, WebSockets).
For interactive ComfyUI, prefer binding it only on localhost or a dedicated
host name rather than this subpath.

## Setup

```bash
cd compose/proxy
cp .env.example .env

# Generate bcrypt for your password (uses caddy hash-password in Docker)
../../scripts/gen-proxy-auth.sh 'your-strong-password'
# paste the printed PROXY_USER / PROXY_PASSWORD_HASH into .env

# Start backends you need (separate compose projects), then:
docker compose up -d
```

`.env.example` ships only a placeholder for `PROXY_PASSWORD_HASH`; the proxy
will not accept any login until you replace it with a generated hash.

## curl examples

```bash
# Ollama version through the proxy (Basic Auth)
curl -sS -u 'freki:YOUR_PASSWORD' http://localhost:8080/ollama/api/version

# Ollama tags
curl -sS -u 'freki:YOUR_PASSWORD' http://localhost:8080/ollama/api/tags | jq .

# vLLM health + models (when vLLM is up)
curl -sS -u 'freki:YOUR_PASSWORD' http://localhost:8080/vllm/health
curl -sS -u 'freki:YOUR_PASSWORD' http://localhost:8080/vllm/v1/models | jq .

# Without credentials → 401
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:8080/ollama/api/version
```

Smoke-test scripts still talk to the backends directly by default
(`OLLAMA_URL=http://localhost:11434`). To exercise the proxy:

```bash
OLLAMA_URL=http://localhost:8080/ollama curl -sS -u freki:YOUR_PASSWORD \
  "$OLLAMA_URL/api/version"
```

(or put the password in a netrc / `CURL_USER` wrapper — the stock smoke
scripts do not send Basic Auth headers today).

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `CADDY_IMAGE_TAG` | `2.11.4-alpine` | Pinned Caddy image tag |
| `PROXY_HOST_PORT` | `8080` | Host port for the proxy |
| `PROXY_USER` | `freki` | Basic Auth username |
| `PROXY_PASSWORD_HASH` | _(required)_ | bcrypt hash; use `$$` for each `$` in `.env` |
| `OLLAMA_UPSTREAM` | `host.docker.internal:11434` | Ollama host:port from the proxy container |
| `VLLM_UPSTREAM` | `host.docker.internal:8000` | vLLM host:port |
| `COMFYUI_UPSTREAM` | `host.docker.internal:8188` | ComfyUI host:port |

## Notes

- Image pin matches the rest of the repo: bump `CADDY_IMAGE_TAG` deliberately.
- Password hashes are created with the same Caddy binary that verifies them
  (`caddy hash-password` via `scripts/gen-proxy-auth.sh`).
- Never commit `.env` (gitignored) or real password hashes.
- Kubernetes Ingress / Gateway for the same paths is out of scope here; see
  `k8s/` for the bare Deployments only.
