# Installing / Using the `host-replica` Devcontainer

This document describes the `host-replica` devcontainer (`.devcontainer/host-replica/`), what it
is for, how it is built, and a known issue you may hit while testing server install scripts
inside it.

## Purpose

`host-replica` is a Debian 13 (trixie) devcontainer meant to approximate the real production
server environment closely enough that install scripts under `scripts/server-install/` can be
developed and tested without touching an actual server. It is **not** the production server
itself — some tooling differs (see "Known issue" below).

Key files:

- [Dockerfile.debian](../.devcontainer/host-replica/Dockerfile.debian) — base image, installs
  common CLI tooling and sets locale to `en_US.UTF-8`.
- [devcontainer.json](../.devcontainer/host-replica/devcontainer.json) — devcontainer
  configuration. Adds Docker access via the `docker-outside-of-docker` feature, mounts SSH keys
  and AI-tool config volumes, and runs `post-container-install.sh` after creation.
- [post-container-install.sh](../.devcontainer/host-replica/post-container-install.sh) — copies
  SSH files into the container and removes the user keychain helper from `~/.ssh/config`.

## Building / rebuilding

Use the VS Code command **Dev Containers: Rebuild Container** (or **Reopen in Container** the
first time). Rebuild whenever `Dockerfile.debian` or `devcontainer.json` changes for the new
configuration to take effect.

## Testing server install scripts

`./server-install.sh` (repo root) can be run directly inside this devcontainer to exercise the
same code path used on a real server:

```sh
./server-install.sh
```

It delegates to `scripts/server-install/server-install.sh`, which in turn runs
`scripts/server-install/server-install-common.sh`. That script does an `apt install` of, among
other things, `docker.io` and `docker-cli` from Debian's own repository — this is expected and
correct for a **real server**, which has no other source of Docker tooling.

## Known issue: `docker-buildx` conflicts with `docker-buildx-plugin`

### Symptom

Running `./server-install.sh` inside the `host-replica` devcontainer can produce an error like:

```text
Preparing to unpack .../80-xclip_0.13-4+b2_arm64.deb ...
Unpacking xclip (0.13-4+b2) ...
Errors were encountered while processing:
 /tmp/apt-dpkg-install-jCVP0E/39-docker-buildx_0.13.1+ds1-3_arm64.deb
Error: Sub-process /usr/bin/dpkg returned an error code (1)
```

Everything else in the same `apt install` transaction (e.g. `xclip`) installs successfully;
only `docker-buildx` fails to configure.

### Root cause

Two different packages both try to provide the `docker buildx` CLI plugin
(`/usr/libexec/docker/cli-plugins/docker-buildx`):

| Source | Package | Version | Where it comes from |
| --- | --- | --- | --- |
| `download.docker.com` (Docker's own apt repo) | `docker-buildx-plugin` | 0.37.1 | Installed by the `docker-outside-of-docker` devcontainer feature |
| `deb.debian.org` (Debian trixie) | `docker-buildx` | 0.13.1 | Pulled in as a *Recommends* of `docker.io`, installed by `server-install-common.sh` |

This conflict is specific to the devcontainer: a real production server never has
`docker-buildx-plugin` pre-installed, so `docker.io`'s `docker-buildx` recommendation installs
cleanly there. Inside `host-replica`, the devcontainer feature installs the Docker-repo plugin
first, and the later `apt install docker.io docker-cli` step in
`server-install-common.sh` then tries to also pull in Debian's older, conflicting package.

### Fix

`Dockerfile.debian` pins Debian's `docker-buildx` package to priority `-1` so it is never
selected as an install candidate:

```dockerfile
RUN printf 'Package: docker-buildx\nPin: origin deb.debian.org\nPin-Priority: -1\n' \
    > /etc/apt/preferences.d/no-debian-docker-buildx
```

Only `docker-buildx` is pinned — **not** `docker.io`, `docker-cli`, or `docker-compose` — because
`server-install-common.sh` must still be able to install those from Debian's repo when run on a
real server. The pin lives in the devcontainer's `Dockerfile.debian` and has no effect outside
this devcontainer image, so production installs are unaffected.

Since `docker-buildx` is only a *Recommends* (soft dependency) of `docker.io`, pinning it away
does not break the `docker.io`/`docker-cli` install — apt simply skips the recommended package.

You must **rebuild the devcontainer** for this fix to take effect on an existing container.

### If you still hit this error

1. Confirm the devcontainer image includes the pin above (rebuild if not).
2. Verify both tools still work:

   ```sh
   docker buildx version   # should report the Docker-repo version, e.g. v0.37.1
   task --version
   ```

   If both commands succeed, the dpkg error is cosmetic and does not affect functionality.
3. Running `sudo apt-get install -f` afterwards is safe to clear the dpkg "broken package" state.
   Confirmed 2026-09-24: this did not downgrade `docker buildx` and did not reintroduce any
   packages stuck in the `iU` (unpacked, not configured) state.
4. If `docker buildx version` reports the *old* Debian version (`0.13.x`) instead of the
   Docker-repo one, `docker-buildx-plugin` was somehow removed — rebuild the devcontainer so the
   `docker-outside-of-docker` feature reinstalls it, rather than running `apt install
   docker-buildx` manually.

### Related note: packages stuck in `iU` state

Separately from the `docker-buildx` conflict, `dpkg -l` may show a large number of packages in
`iU` (unpacked, not configured) state, including `dbus`, `containerd`, `docker.io`, `docker-cli`,
`iptables`, `apparmor`, and `certbot`.

This happens because PID 1 in the devcontainer is a plain shell, not `systemd`. Packages whose
`postinst` scripts try to talk to systemd (enabling/starting a service, reloading sysctl
settings, etc.) cannot finish configuring without an init system. This is expected and normal
for a devcontainer and is not something that needs to be "fixed".
