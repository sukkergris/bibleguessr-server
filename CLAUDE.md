# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Server-side infrastructure for **bibleguessr**: an nginx reverse proxy + a .NET web API, shipped as prebuilt images (`docker.io/isuperman/bibleguessr-nginx`, `docker.io/isuperman/bibleguessr-api`) and run with Docker Compose. There is no application source here — only Bash, Taskfiles, nginx config and compose.

The repo was derived from `site-fleet-cms-server` (itself modelled on `korttilkort.dk/ktk-server`). Leftovers from that origin are still present and are **not** part of bibleguessr: `DOMAIN_KFK/CVP/HVT` substitution vars, `scripts/preflight-dood.sh` (still wired to site-fleet-cms), the site-fleet-cms paths in `.env-template`, and the squidex/yarp/prerender/backup env files that `scripts/env-init.sh` generates. `initialize-certs/README.md` also documents `task certs:*` tasks and a `Taskfile.Certs.yml` that do not exist in this repo.

## Commands

All automation goes through `task` (`task` alone lists everything):

| Command | What it does |
| --- | --- |
| `task docker:nginx:generate-conf` | Render `nginx/conf.d/*.conf.template` → `*.conf` via `scripts/initialize-nginx-conf.sh` |
| `task docker:site:up` / `site:down` | Start/stop the compose stack (up depends on generate-conf) |
| `task docker:nginx:test` | Routing test (`scripts/test/nginx-routing.sh`): runs the generated config in a throwaway nginx container against a mock API (`scripts/test/mock-api.conf`). Never touches the running stack |
| `task docker:site:pull` | Pull images at `APP_VERSION` (hardcoded in `Taskfile.Docker.yml`) |
| `task dev:host:bootstrap` | (Run on the macOS host) create + trust a self-signed cert for `bibleguessr.srv`, add it to `/etc/hosts` |
| `task dev:srv:add-certs-to-container` | (Run inside the devcontainer) copy dev certs into `/etc/letsencrypt/live/bibleguessr.srv/` |
| `./server-install.sh` | Server provisioning (apt packages, Task, env files). Branches on `HOST_ENVIRONMENT` in `env/app.env` (`production` vs replica) |

The only automated test is `task docker:nginx:test`; extend it when you change routing, rate limits or logging. Validate Bash with `shellcheck <file>` (the devcontainer has the VS Code extension, but no `shellcheck` binary on the PATH).

## Architecture

### Configuration flow
1. `env/*.env` (gitignored; created by `scripts/env-init.sh`) holds all config. `env/bibleguessr/` holds bibleguessr-specific files (`brevo.env`, `webapi.env`).
2. `process_templates` (`lib-bash/env-substitution.sh`) sources **every** `env/*.env` (top level only) with `set -a`, then runs `envsubst` restricted to an explicit whitelist (`LIMIT_RATE`, `ASSET_EXPIRES`, `DOMAIN_*`). This whitelist is deliberate — it keeps nginx's own `$host`, `$uri` etc. intact. **A new template variable must be added to that list** or it will be left literal.
3. `docker-compose.yml` bind-mounts the whole `nginx/` dir into the container as `/etc/nginx/`, so generated `.conf` files are what the running nginx sees. `.conf.template` files are ignored by nginx only because `nginx.conf` includes `conf.d/*.conf`.
4. The compose file requires `VERSION`, `LETSENCRYPT_DIR`, `LETSENCRYPT_CHALLENGES_DIR`, `NGINX_DIR` (`:?` guards). The Taskfile loads `.env` last, so its host paths win over `env/*.env`; keep `NGINX_DIR` identical in `.env` and `env/nginx.env`.
5. The `bibleguessr-prod` network has a fixed subnet (`10.201.0.0/24`) because the API trusts `X-Forwarded-For` only from that network (`ForwardedHeadersOptions.KnownIPNetworks` in the app repo). Change both together.

Known inconsistency: `nginx/conf.d/20-bibleguessr.conf` is a generated file but is tracked in git. Always edit the `.conf.template` and regenerate; never edit the `.conf` by hand.

### nginx layout
`nginx.conf` → `includes/http-globals.conf` (log formats, rate limiting, good/bad-guys maps, `includes/upstreams.conf`) → `conf.d/NN-site.conf`. Site configs are thin and compose behaviour from `includes/` (`tarpit.conf`, `ssl-params.conf`, `security-headers.conf`, `static-assets.conf`, `proxy-webapi.conf`, …). Requests flagged by the `$bad_guys` map are bounced before any other handling. The `nginx.conf` inside the image (from the app repo's `server-replica/`, including its `test/`) is never used: this repo's `nginx/` is mounted over `/etc/nginx`.

Routing in `20-bibleguessr.conf.template`:
- The SPA is baked into the nginx image at `/usr/share/nginx/html` (`$site_root`). `location /` falls back to `index.html` for client routes. `/assets/` (Vite's hashed output) 404s on misses and is cached as `immutable`.
- `/api/`, `/hubs/` and `/sitemap.xml` proxy to `$api_upstream` (`http://bibleguessr-api:8080`, defined with `map` in `upstreams.conf` so DNS is resolved per request). **Never strip the `/api/` or `/hubs/` prefix**: the API maps them itself and has no path base or CORS, so it must share the frontend's origin.
- `/api/` is limited by `api_limit`; the email-sending POSTs (`/api/reports`, `/api/abuse-reports`, `/api/bug-reports`) also by `report_limit`. `/hubs/` (SignalR, WebSocket-only) has no `limit_req` and 1h timeouts. `/api/healthz` is unlimited and not logged.
- No CDN is in front, so rate limits key on `$binary_remote_addr` and `proxy-params.conf` **overwrites** `X-Forwarded-For` with `$remote_addr` (appending would let clients inject addresses).
- Never log request bodies. Query strings are logged on purpose (they carry no verse text).

Let's Encrypt certs are expected at `/etc/letsencrypt/live/<domain>/`, and the ACME webroot is `/var/www/letsencrypt_challenges`.

### lib-bash
A small module system (same pattern as `ktk-server`):
- Scripts source `lib-bash/header.sh`, which locates the project root by walking up (max 5 levels) to the `root-marker` file, exports `PROJECT_ROOT`, `LIB_DIR`, `SCRIPTS_DIR`, and auto-loads `error-handling` (`set -Eeuo pipefail` + ERR trap) and `logging` (`log::info/warn/error/ok`).
- `load_module <name>` finds `<name>.sh` **anywhere under `lib-bash/`** by filename (e.g. `load_module certs` resolves `lib-bash/certs/certs.sh`), so module filenames must be unique across subfolders.
- Modules guard against double-sourcing with a `_<NAME>_LOADED` variable; follow that pattern in new modules.

### Environments
- **macOS host (development):** runs `dev:host:bootstrap` for certs/hosts entries. `scripts/development/cert-issue.sh` refuses to run inside Docker.
- **`host-replica` devcontainer** (`.devcontainer/host-replica/`, Debian 13, workspace mounted at `/xyz`, runs as root, Docker-outside-of-Docker): approximates the production server so `server-install.sh` can be tested. `Dockerfile.debian` pins Debian's `docker-buildx` to priority -1 to avoid a conflict with the DooD feature's `docker-buildx-plugin`. See `docs/Installing-host-replica.md`. Do **not** "fix" the many `iU` dpkg packages there (the container has no systemd); `sudo apt-get install -f` is safe.
- **Production server:** `initialize-certs/` and `scripts/initial-install-scripts/` are host-only. Do not run them in the replica.

## Conventions

- Bash scripts start with `#!/usr/bin/env bash` and `set -u`. Use `log::*` for output once `header.sh` is sourced, and `local` for all function variables.
- Scripts that call `sudo` (cert copying, certbot, hosts file) are expected to prompt; don't try to work around that.
