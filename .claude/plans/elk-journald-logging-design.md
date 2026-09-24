# Design & Implementation Plan: Hybrid Logging — journald + ELK

## Context

Projektet er et nginx honeypot playground der allerede logger security events struktureret til
stdout (via `security_events` log-format med `key=value`-felter). Produktions-docker-compose
bruger allerede `journald` driver med tag `nginx`. Målet er at introducere ELK langsomt og
inkrementelt, så journald forbliver som primær lokal log-kilde, og ELK tilføjer dashboards
og langsigtet retention.

Eksisterende relevante filer:
- `e2e/docker-compose.prod.yml` — journald driver sat op med tag `nginx`
- `nginx/includes/log-formats.conf` — `security_events` og `realip` formater
- `nginx/includes/tarpit.conf` — honeypot location blocks logger via `security_events`
- `nginx-log/` — dev bind-mount (access.log, error.log, security.log)
- `.git/refs/heads/feature/logging-elk` — tidligere ELK-branch eksisterer
- `LEARNING/06-linux-prod-journald.md` — dokumentation om journald-strategi

---

## Arkitektur

```
┌─────────────────────────────────┐        ┌──────────────────────────────────┐
│  nginx-host (nuværende server)  │        │  ELK-maskine (dedikeret)         │
│                                 │        │                                  │
│  nginx container                │        │  Docker Compose:                 │
│  (journald driver, tag=nginx)   │        │  - Elasticsearch :9200           │
│         ↓                       │        │  - Kibana :5601                  │
│  systemd-journald               │        │                                  │
│  (lokal, altid tilgængeligt)    │        │  Ingest pipeline:                │
│         ↓                       │        │  - kv (key=value parsing)        │
│  Filebeat container             │─HTTPS──▶  - geoip på remote_addr         │
│  (reads /run/log/journal)       │  API   │  - user_agent parsing            │
│  input: journald                │  key   │                                  │
│  filter: nginx + system         │        │  Data streams:                   │
└─────────────────────────────────┘        │  - logs-nginx.security-default   │
                                           │  - logs-nginx.access-default     │
  journalctl -t nginx ← stadig            │  - logs-system.syslog-default    │
  tilgængeligt lokalt                     └──────────────────────────────────┘
```

**Hybrid-garanti**: Filebeat er en passiv læser — logs går ikke tabt hvis ELK er nede.
journald på host er altid primær kilde til lokale `journalctl`-queries.

---

## Filstruktur (dette repo)

```
filebeat/
├── docker-compose.yml          # Filebeat som standalone Docker service på nginx-host
├── filebeat.yml                # Filebeat konfiguration (journald input, ES output)
└── .env.example                # ELASTICSEARCH_HOST, ELASTICSEARCH_API_KEY, CA_FINGERPRINT

elk/
├── docker-compose.yml          # Elasticsearch + Kibana på ELK-maskine
├── .env.example                # ES_VERSION, ELASTIC_PASSWORD, heap sizes
├── setup/
│   └── setup.sh                # Bootstrap: opret roller, API key, ingest pipeline
├── elasticsearch/
│   └── elasticsearch.yml       # Single-node, TLS, security config
└── kibana/
    └── kibana.yml              # Kibana base URL, ES connection
```

---

## Filebeat konfiguration (nøgledele)

```yaml
# filebeat/filebeat.yml
filebeat.inputs:
  - type: journald
    id: nginx-host-journal
    seek: cursor                     # Gem cursor-position; genoptag ved restart
    include_matches:
      - SYSLOG_IDENTIFIER=nginx
      - _SYSTEMD_UNIT=docker.service

processors:
  - add_fields:
      target: host
      fields:
        name: "${HOSTNAME}"
  - community_id: ~

output.elasticsearch:
  hosts: ["https://${ELASTICSEARCH_HOST}:9200"]
  api_key: "${ELASTICSEARCH_API_KEY}"
  ssl.ca_trusted_fingerprint: "${CA_FINGERPRINT}"
  pipeline: "nginx-security-parse"
  data_stream.enabled: true
```

Filebeat kører med volume mounts:
- `/run/log/journal:/run/log/journal:ro` — journald socket adgang
- `/etc/machine-id:/etc/machine-id:ro` — required af journald input

---

## ELK stack på ELK-maskinen

**`elk/docker-compose.yml`** — single-node setup:
- `elasticsearch:8.x` med `xpack.security.enabled=true`, self-signed cert eller CA
- `kibana:8.x` med enrollment token fra ES

**`elk/setup/setup.sh`** — køres én gang efter første opstart:
1. Venter på ES er healthy
2. Opretter ingest pipeline `nginx-security-parse`:
   - `kv` processor: parser `security_events` key=value linjer
   - `geoip` processor: `remote_addr` → `geo.*` felter
   - `user_agent` processor: UA-string → strukturerede felter
3. Opretter API key til Filebeat med minimale rettigheder (`auto_indexing`)
4. Printer API key — kopieres til `filebeat/.env`

**ILM policy**: 30-dages retention på `logs-*` data streams (hot → delete).

---

## Kibana dashboards (Fase 4)

Fire visualiseringer på ét dashboard "Honeypot Security":
1. **Overview** — pie/bar over angrebstyper per location block (`.env`, `.php`, `wp-admin`, DNS)
2. **Geo Map** — world map med `geo.location` fra GeoIP-enrichment
3. **Timeline** — date histogram (per time) over honeypot hits
4. **Top Attackers** — tabel: IP, request count, seneste request, user agent

Eksporteres som `elk/kibana/dashboards/honeypot-security.ndjson` for reproducibilitet.

---

## Task-kommandoer (tilføjes Taskfile.elk.yml)

```
task elk:start          # Start ELK stack på ELK-maskinen
task elk:stop           # Stop ELK stack
task elk:status         # ES cluster health + Kibana status
task filebeat:start     # Start Filebeat på nginx-host
task filebeat:stop      # Stop Filebeat
task filebeat:test      # Test Filebeat config (filebeat test config)
task filebeat:output    # Test forbindelsen til Elasticsearch
```

---

## Introduktionsstrategi — 4 faser

### Fase 1 — ELK lokalt i devcontainer (validering)
- Tilføj ES + Kibana til `.devcontainer/alpine/docker-compose.yml` (profile `elk`)
- Filebeat læser `nginx-log/security.log` (fileinput, ikke journald)
- Mål: se security events i Kibana lokalt, iterere på ingest pipeline
- Ingen netværkskonfiguration nødvendig

### Fase 2 — Filebeat → journald (single-machine validering)
- Skift Filebeat input til `journald` type
- ELK stadig lokal — validér at journald-logs parses korrekt
- Kræver: nginx-host kører linux med systemd

### Fase 3 — ELK på dedikeret maskine
- Klon `elk/` til ELK-maskinen, kør `docker compose up`
- Kør `setup.sh`, kopiér API key til `filebeat/.env` på nginx-host
- Verificér med `task filebeat:output` at forbindelsen virker
- Valider data i Kibana

### Fase 4 — Dashboards og retention
- Import `elk/kibana/dashboards/honeypot-security.ndjson` via Kibana UI
- Konfigurer ILM policy (30 dage)
- Konfigurer alerting på spikes i honeypot hits (valgfrit)

---

## Verifikation per fase

**Fase 1:**
```sh
curl -u elastic:${ELASTIC_PASSWORD} http://localhost:9200/_cat/indices?v
# Forventer: logs-nginx.security-default index med dokumenter
```

**Fase 2:**
```sh
journalctl -t nginx --since "5 minutes ago" | head -20
# Sammenlign med hvad Kibana viser — skal matche
```

**Fase 3:**
```sh
task filebeat:output
# Forventer: "Connection to backoff(elasticsearch(...)) established"
```

**Fase 4:**
```sh
curl -vL --insecure https://nginx-playground.dk/.env
# Forventer: ny honeypot hit vises i Kibana Security Overview inden for 30s
```

---

## Kritiske filer at oprette

1. `filebeat/docker-compose.yml`
2. `filebeat/filebeat.yml`
3. `filebeat/.env.example`
4. `elk/docker-compose.yml`
5. `elk/.env.example`
6. `elk/elasticsearch/elasticsearch.yml`
7. `elk/kibana/kibana.yml`
8. `elk/setup/setup.sh`
9. `Taskfile.elk.yml` (inkluderes fra rod-Taskfile)

Eksisterende filer der evt. modificeres:
- `.devcontainer/alpine/docker-compose.yml` — tilføj `elk` profile (Fase 1)
- Rod-`Taskfile.yml` — inkluder `Taskfile.elk.yml`

---

## Design doc

Efter plan mode afsluttes skrives designdokumentet til:
`docs/superpowers/specs/2026-05-30-elk-journald-logging-design.md`
