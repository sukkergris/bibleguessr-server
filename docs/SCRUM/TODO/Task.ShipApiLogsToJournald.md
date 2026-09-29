# Ship the API's logs to journald on the production host

In production, stdout should be the API's only log sink, and Docker/systemd
should own retention. Today `bibleguessr-api` in `docker-compose.yml` has no
`logging:` section, so it uses Docker's default `json-file` driver with no
size limit. (`nginx` already takes its driver from `NGINX_LOGGING_DRIVER`.)

## Requirements

- `backend/Api/appsettings.Production.json` in the app repo stays as it is:
  console only, JSON. No File sink in the container.
- The Docker host sends container logs to journald, either with
  `"log-driver": "journald"` in `/etc/docker/daemon.json`, or with
  `logging: driver: journald` per service in `docker-compose.yml`, with
  `tag: bibleguessr-api`.
- Retention is set in `/etc/systemd/journald.conf` with `SystemMaxUse=` and
  `MaxRetentionSec=`.
- Whatever is configured on the host is reproducible from this repo
  (`server-install.sh` or a script under `scripts/`), not only done by hand.

## Usage

```bash
journalctl CONTAINER_NAME=bibleguessr-api -o cat -f | jq
journalctl CONTAINER_NAME=bibleguessr-api -o cat --since today \
  | jq 'select(."@l"=="Error" or ."@l"=="Warning")'
```

## Not recommended

`Serilog.Sinks.Journald` would give native journald fields (`PRIORITY`, so
`journalctl -p err` works). It ties the image to systemd, and `jq` already
covers the need.

## Source

Item 3 ("Host med journald") in the former `docs/SCRUM/Plan.md`.
