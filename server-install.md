# Server Install — dpkg/apt Findings

Notes from investigating an `apt-get install` failure during devcontainer setup, and the resulting package state on the `dev` container.

## The error

```text
Preparing to unpack .../80-xclip_0.13-4+b2_arm64.deb ...
Unpacking xclip (0.13-4+b2) ...
Errors were encountered while processing:
 /tmp/apt-dpkg-install-jCVP0E/39-docker-buildx_0.13.1+ds1-3_arm64.deb
Error: Sub-process /usr/bin/dpkg returned an error code (1)
```

`xclip` installed fine. `docker-buildx` (the Debian repo package, v0.13.1) failed to configure.

## Root cause: package source conflict

Two different `docker-buildx` artifacts both try to own the same CLI plugin path:

| Source | Package | Version | Result |
| --- | --- | --- | --- |
| `download.docker.com` (Docker's own apt repo) | `docker-buildx-plugin` | 0.37.1 | ✅ installed, active |
| `deb.debian.org` (Debian trixie) | `docker-buildx` | 0.13.1 | ❌ failed to configure |

Both packages install a binary at `/usr/libexec/docker/cli-plugins/docker-buildx`. Docker's own package (newer, and already present) wins the conflict; Debian's older package fails during `dpkg --configure`. This is the expected/correct outcome — the newer Docker-maintained plugin should be the one that stays active.

**Verified working despite the error:**

```sh
$ docker buildx version
github.com/docker/buildx v0.37.1 ...

$ task --version
3.52.0
```

Both `docker buildx` and `task` (also installed in the same run) work correctly. The failure did **not** break either tool.

## Secondary finding: 110 packages stuck in `iU` state

Unrelated to the buildx error, `dpkg -l` shows ~110 packages in `iU` (unpacked, not configured), including `dbus`, `containerd`, `docker.io`, `docker-cli`, `iptables`, `apparmor`, `certbot`.

**Cause:** PID 1 in the container is `sh`, not `systemd`. Packages whose `postinst` scripts expect to talk to systemd (enable/start a service, reload sysctl, etc.) can't finish configuring in a container without an init system. This is normal and expected for a devcontainer — not something to "fix" with `apt-get --fix-broken install`.

**Do not run `apt --fix-broken install` to clean this up** — a simulation (`apt-get --simulate --fix-broken install`) shows it would attempt to reconfigure all 110 packages and could reintroduce the `docker-buildx` (Debian) vs `docker-buildx-plugin` (Docker) conflict, potentially downgrading buildx from 0.37.1 to 0.13.1.

## Recommendation

Leave the container as-is; both `docker buildx` and `task` are confirmed functional. If a cleaner long-term fix is wanted, pin Debian's Docker packages out of consideration in `Dockerfile.debian` so the conflict never occurs:

```dockerfile
RUN printf 'Package: docker-buildx docker.io docker-cli docker-compose\nPin: origin deb.debian.org\nPin-Priority: -1\n' \
    > /etc/apt/preferences.d/no-debian-docker
```

This is a cosmetic improvement (avoids the scary-looking error in build logs), not a functional bug fix.
