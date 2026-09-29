# BibleGuessr Server — Project Context & Rules

## Project Overview

**bibelguessr-server** provides the server-side infrastructure, `host-replica` development environment, and production deployment stack for **BibleGuessr** (`bibleguessr.uk` / `bibleguessr.srv`).

There is **no application source code** (frontend or backend) in this repository. The application runs as prebuilt container images (`docker.io/isuperman/bibleguessr-nginx` and `docker.io/isuperman/bibleguessr-api`). This repository contains the Bash automation, Taskfiles, Nginx configurations, environment templates, and Docker Compose definitions that orchestrate them.

### Services Stack (`docker-compose.yml`)

1. **`nginx`** (`docker.io/isuperman/bibleguessr-nginx`):
   - Custom reverse proxy and TLS termination point.
   - Serves the baked-in SPA from `/usr/share/nginx/html`.
   - Mounts `./nginx/` configuration over `/etc/nginx`.
   - Handles Let's Encrypt certificates, security headers, rate limiting, bad-bot tarpitting, and upstream routing.
2. **`bibleguessr-api`** (`docker.io/isuperman/bibleguessr-api`):
   - .NET/F# backend API and SignalR hub (`/hubs/`).
   - Unpacks and caches public-domain Bible archives into persistent named volume `bible-data` (`/data/bibles`).
   - Communicates on fixed internal subnet (`10.201.0.0/24`).
3. **`vaultwarden`** (`docker.io/vaultwarden/server`):
   - Self-hosted password manager isolated on its own Docker network (`vaultwarden`).
   - Exposed through Nginx on dedicated domain (`DOMAIN_VW`, e.g. `vault.bibleguessr.srv` or `vault.kforkode.dk`).
   - Protected with dedicated login rate-limiting (`vault_login`) and query-sanitized logging.

---

## Environments

### 1. macOS Development Host

- Used for local development and bootstrapping.
- `task dev:host:bootstrap`: Generates self-signed dev certificates for `bibleguessr.srv` and `vault.bibleguessr.srv`, trusts them in the macOS keychain, and appends mappings to `/etc/hosts`.
- `scripts/development/cert-issue.sh` is host-only and deliberately rejects running inside Docker.

### 2. `host-replica` Devcontainer (`.devcontainer/host-replica/`)

- Debian 13 (trixie) container running Docker-outside-of-Docker (DooD), mounting workspace at `/xyz` as root.
- Replicates the production server environment closely so `server-install.sh` and routing configurations can be developed and tested safely.
- **Package Pinning Note:** Debian's `docker-buildx` package is pinned to priority `-1` in `Dockerfile.debian` to avoid conflicting with the DooD feature's `docker-buildx-plugin`.
- **Systemd & `iU` Packages:** The container does not run systemd, leaving some system service packages in `iU` (unpacked) state. This is expected; do **not** run `apt --fix-broken install`.
- `task dev:srv:add-certs-to-container`: Copies local dev certificates to `/etc/letsencrypt/live/`.

### 3. Production Server

- Target is a Debian server provisioned with `./server-install.sh` (`HOST_ENVIRONMENT=production` in `env/app.env`).
- Manages real Let's Encrypt SSL certificates in `/etc/letsencrypt/live/` via Certbot.

---

## Configuration Flow & Templating

1. **Environment Variables (`env/*.env`):**
   - Config is kept in `env/` (gitignored, initialized via `scripts/env-init.sh`).
   - `env/app.env`, `env/nginx.env`, `env/letsencrypt.env`.
   - Subsystem folders: `env/bibleguessr/` (`webapi.env`, `brevo.env`) and `env/vaultwarden/` (`vaultwarden.env`).
   - `vaultwarden.env` is isolated in a subfolder so its `DOMAIN` variable does not collide with `DOMAIN` in `env/nginx.env`.
2. **Nginx Template Processing:**
   - Template files live in `nginx/conf.d/*.conf.template`.
   - `task docker:nginx:generate-conf` (runs `scripts/initialize-nginx-conf.sh` → `process_templates` in `lib-bash/env-substitution.sh`).
   - `process_templates` sources all top-level `env/*.env` files with `set -a` and runs `envsubst` against an **explicit whitelist** (`LIMIT_RATE`, `ASSET_EXPIRES`, `DOMAIN_BG`, `DOMAIN_VW`, etc.).
   - **Crucial Rule:** Any new substitution variable in `.conf.template` **must** be added to the whitelist array in `lib-bash/env-substitution.sh`.
   - **Crucial Rule:** Never edit generated `.conf` files directly; always edit `.conf.template` and regenerate.
3. **Docker Compose Environment:**
   - `docker-compose.yml` expects `VERSION`, `LETSENCRYPT_DIR`, `LETSENCRYPT_CHALLENGES_DIR`, and `NGINX_DIR`.
   - The Taskfile loads `.env` last, taking precedence over `env/*.env`. Keep paths synchronized.

---

## Networking, Routing & Security Guidelines

- **Subnet Synchronization:** The `bibleguessr-prod` network has a fixed subnet (`10.201.0.0/24`). The API container trusts `X-Forwarded-For` only from this subnet (`ForwardedHeadersOptions.KnownIPNetworks` in backend). Both must always match.
- **Prefix Preservation:** Never strip `/api/` or `/hubs/` prefixes in Nginx when proxying to `bibleguessr-api`. The API maps them directly and has no CORS enabled, relying on sharing the frontend origin.
- **Spoofing Prevention:** Rate limits key on `$binary_remote_addr`. `proxy-params.conf` deliberately overwrites `X-Forwarded-For` with `$remote_addr` rather than appending, preventing client IP spoofing.
- **Rate Limiting Zones:**
  - General API: `api_limit` zone.
  - Abusive/report endpoints (`/api/reports`, `/api/abuse-reports`, `/api/bug-reports`): `report_limit` zone.
  - Vaultwarden login (`/identity/connect/token`): `vault_login` zone (10r/m).
  - WebSockets (`/hubs/`): No rate limiting, 1-hour connection timeouts.
  - Health check (`/api/healthz`): Unlimited, not logged in access logs.
- **Privacy & Sanitized Logging:**
  - Request bodies must **never** be logged.
  - Query strings for the main BibleGuessr application are logged (they contain room IDs, coordinates, but no verse text).
  - Query strings for Vaultwarden must **never** be logged (`realip_noquery`), as authentication bearer tokens are passed via query parameters on WebSocket hubs.
  - Uploaded verse text must **never** touch the server; clients only exchange verse references (book, chapter, verse number).

---

## Common Development Commands (Taskfile)

```sh
# Stack Lifecycle
task docker:site:up             # Generate configs and start the stack (detached)
task docker:site:down           # Stop the stack
task docker:site:pull           # Pull images for APP_VERSION specified in Taskfile.Docker.yml
task docker:list-volumes        # List Docker volumes

# Nginx Configuration & Testing
task docker:nginx:generate-conf # Render nginx/conf.d/*.conf.template -> *.conf
task docker:nginx:test          # Run routing test suite against mock API in isolated container

# Host & Replica Dev Setup
task dev:host:bootstrap         # (Host only) Create & trust dev certs, add bibleguessr.srv to /etc/hosts
task dev:srv:add-certs-to-container # (Container only) Link dev certs into /etc/letsencrypt/live/

# Server Provisioning
./server-install.sh             # Run host provisioning (detects production vs replica via env/app.env)
```

---

## Testing & Verification

- **Routing & Proxy Tests (`task docker:nginx:test`):**
  - Executes `scripts/test/nginx-routing.sh`.
  - Spins up a mock API upstream container (`scripts/test/mock-api.conf`), a temporary Nginx container with current configuration, and a client container on an isolated test network.
  - Verifies HTTP-to-HTTPS redirection, routing of `/api/` vs `/` vs `/vaultwarden`, header forwarding, rate-limiting triggers, and absence of sensitive tokens/passwords in logs.
  - **Always run and update this test suite** whenever altering Nginx routing, rate limits, or upstream definitions.
- **Bash Script Linting:**
  - Run `shellcheck <script>` across scripts in `scripts/` and `lib-bash/`.

---

## Scripting & Coding Conventions (`lib-bash`)

- **Script Header:** All scripts begin with `#!/usr/bin/env bash` and `set -u`.
- **Modular Library:** Scripts source `lib-bash/header.sh`, which determines `PROJECT_ROOT`, exports path variables, enables strict error handling (`set -Eeuo pipefail` + ERR trap), and initializes `log::info`, `log::warn`, `log::error`, `log::ok`.
- **Module Loading:** Use `load_module <name>` to load any module under `lib-bash/` by filename without path. All modules must include an idempotency guard (e.g. `_MODULE_NAME_LOADED`).
- **Function Variables:** Always declare function variables with `local`.
- **Documentation & Language:** Code, comments, commit messages, and documentation must always be written in **English (US)**.
