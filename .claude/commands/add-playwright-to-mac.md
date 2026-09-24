# Tilføj Playwright Codegen (noVNC) til devcontainer

Tilføjer `playwright codegen`-support til et devcontainer-projekt via Xvfb + noVNC. Bruges fra Mac med Docker Desktop. Kræver ingen XQuartz eller andre opsætninger på Mac-siden.

## Hvad der skal gøres

### 1. Tilføj pakker til Dockerfile

Find projektets Dockerfile (typisk `.devcontainer/Dockerfile` eller `.devcontainer/<navn>/Dockerfile`).

Tilføj følgende pakker til den eksisterende `apt-get install`-blok:

```dockerfile
xvfb \
x11vnc \
novnc \
websockify \
```

Hvis der ikke er en `apt-get install`-blok i forvejen, tilføj:

```dockerfile
RUN apt-get update && apt-get install -y \
    xvfb \
    x11vnc \
    novnc \
    websockify \
    && rm -rf /var/lib/apt/lists/*
```

### 2. Eksponer port 6080 i docker-compose.yml

Find projektets `docker-compose.yml` og tilføj under den relevante service:

```yaml
ports:
  - "6080:6080"
```

Fjern eventuel `DISPLAY`-environment-variabel sat til XQuartz (`host.docker.internal:0` e.l.) — den er ikke længere nødvendig.

### 3. Opret pw-codegen.sh i projektroden

Opret filen `pw-codegen.sh` i projektets rodmappe:

```bash
#!/usr/bin/env bash
set -e

DISPLAY_NUM=99
VNC_PORT=5900
NOVNC_PORT=6080
NOVNC_WEB=/usr/share/novnc

# Start Xvfb hvis ikke kørende
if ! pgrep -x Xvfb > /dev/null; then
    echo "Starter Xvfb på display :${DISPLAY_NUM}..."
    Xvfb :${DISPLAY_NUM} -screen 0 1920x1080x24 &
    sleep 1
fi

# Start x11vnc hvis ikke kørende
if ! pgrep -x x11vnc > /dev/null; then
    echo "Starter x11vnc..."
    x11vnc -display :${DISPLAY_NUM} -nopw -listen localhost -xkb -forever -quiet &
    sleep 1
fi

# Start noVNC/websockify hvis ikke kørende
if ! pgrep -f websockify > /dev/null; then
    echo "Starter noVNC på port ${NOVNC_PORT}..."
    websockify --web ${NOVNC_WEB} ${NOVNC_PORT} localhost:${VNC_PORT} &>/dev/null &
    sleep 1
fi

echo ""
echo "  Åbn browseren her: http://localhost:${NOVNC_PORT}/vnc.html"
echo ""

DISPLAY=:${DISPLAY_NUM} playwright codegen --target=csharp "$@"
```

Gør scriptet eksekverbart:

```sh
chmod +x pw-codegen.sh
```

### 4. Tilføj task (valgfrit)

Hvis projektet bruger Taskfile, tilføj til den relevante taskfile:

```yaml
codegen:
  desc: "Start Playwright codegen (åbn http://localhost:6080/vnc.html). Eks: task codegen -- MyTest.cs"
  dir: "{{.ROOT_DIR}}"
  cmds:
    - ./pw-codegen.sh {{if .CLI_ARGS}}--output={{.CLI_ARGS}}{{end}} http://localhost:3000
```

Tilpas URL'en (`http://localhost:3000`) til projektets dev-server port.

### 5. Rebuild containeren

```
Dev Containers: Rebuild Container
```

## Brug efter opsætning

Start dev-serveren og kør:

```sh
./pw-codegen.sh http://localhost:3000
```

Åbn **http://localhost:6080/vnc.html** i en browser og klik **Connect**.

## Hvordan det virker

```
Container: Chromium → Xvfb (virtuel skærm) → x11vnc → websockify/noVNC → port 6080
Mac:       Browser → http://localhost:6080/vnc.html  (live view af Chromium)
```

Chromium renderer lokalt i containeren. noVNC streamer displayet som en web-app. Du interagerer med Chromium i browseren — Playwright Inspector genererer C#-kode i terminalen.

## For at gøre kommandoen global

Kopiér denne fil til `~/.claude/commands/` på din Mac:

```sh
cp .claude/commands/add-playwright-to-mac.md ~/.claude/commands/
```

Herefter er `/add-playwright-to-mac` tilgængelig i alle Claude Code-projekter.
