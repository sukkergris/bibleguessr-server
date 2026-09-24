# Tilføj Docker outside of Docker (DooD) til en devcontainer

DooD lader containeren tale med **host-maskinens** Docker-daemon via en socket-mount — ingen nested Docker-daemon, ingen dind-privilegier. Resultatet er at `docker`- og `docker compose`-kommandoer inde i containeren styrer den samme daemon som på hosten.

## Hvad der skal gøres

### 1. Tilføj devcontainer-feature i devcontainer.json

Featuren installerer Docker CLI og sætter tilladelser op automatisk:

```json
"features": {
  "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
}
```

Placer den under den eksisterende `"features"`-nøgle, eller opret nøglen hvis den mangler:

```json
{
  "name": "Mit projekt",
  "features": {
    "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
  },
  ...
}
```

**Hvorfor denne feature:**

- Installerer Docker CLI (ikke daemon) i containeren
- Opretter eller genbruger `docker`-gruppen og tilføjer container-brugeren
- Håndterer socket-tilladelser automatisk — ingen manuel `chmod` eller `usermod` nødvendig

### 2. Mount Docker-socketen i docker-compose.yml

Tilføj socket-mountet under `volumes` på dev-servicen:

```yaml
services:
  dev:
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

Fuld eksempel på dev-service med socket:

```yaml
services:
  dev:
    build:
      context: .
      dockerfile: Dockerfile
    volumes:
      - ../..:/workspace:cached
      - /var/run/docker.sock:/var/run/docker.sock
    command: sleep infinity
```

**Kun devcontainer.json (uden Compose):** Tilføj mountet i `"mounts"` i stedet:

```json
"mounts": [
  "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind"
]
```

### 3. Tjek gruppe-ID på socket (Linux-hosts)

På Linux ejes `/var/run/docker.sock` typisk af gruppen `docker` med GID 999 eller lignende. Hvis containeren kører som en ikke-root bruger kan der opstå adgangsproblemer.

Tjek GID på hosten:

```bash
stat -c '%g' /var/run/docker.sock
```

Hvis GID ikke er 999 (standard for docker-outside-of-docker-featuren), overstyr den i featuren:

```json
"features": {
  "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {
    "dockerDashComposeVersion": "v2",
    "installDockerBuildx": true
  }
}
```

Eller ret gruppen manuelt i Dockerfile (sjældent nødvendigt med featuren):

```dockerfile
ARG DOCKER_GID=999
RUN groupmod -g ${DOCKER_GID} docker 2>/dev/null \
    || groupadd -g ${DOCKER_GID} docker && \
    usermod -aG docker container-user
```

### 4. Rebuild og verificer

Efter ændringerne: **Rebuild container** (Ctrl+Shift+P → "Dev Containers: Rebuild Container").

Verificer at Docker virker inde i containeren:

```bash
docker version
docker ps
docker compose version
```

Du bør se host-maskinens Docker-version og kørende containere.

## Vigtige noter

- **DooD er ikke isoleret** — containeren ser og kan styre alle containers på hosten, inkl. sig selv. Brug kun i dev-miljøer.
- **Mac/Windows Docker Desktop:** Socket er typisk `/var/run/docker.sock` og virker uden GID-justeringer, da Docker Desktop håndterer tilladelser via en bagvedliggende VM.
- **Linux-hosts:** GID-mismatch er den hyppigste fejl — tjek altid med `stat` som nævnt ovenfor.
- Featuren installerer også Docker Compose v2 (`docker compose`). Hvis projektet bruger det gamle `docker-compose` (v1), tilføj: `"installDockerComposeSwitch": true`.
- Socketen er en bind-mount fra hosten — den overlever ikke i et navngivet volume og skal ikke forsøges persisteret.
