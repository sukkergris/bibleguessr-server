# Tilføj Claude-volume til en devcontainer

Et named volume på `~/.claude` bevarer Claude Code-konfiguration — plugins, indstillinger og credentials — på tværs af container-rebuilds. Uden det skal plugins geninstalleres hver gang containeren genbygges.

## Hvad der skal gøres

### 1. Find container-brugerens hjemmemappe

Tjek hvad brugeren hedder inde i containeren — det bestemmer stien til `~/.claude`:

| Bruger | Sti |
|--------|-----|
| `vscode` (standard devcontainer) | `/home/vscode/.claude` |
| `root` | `/root/.claude` |
| Projektspecifik (f.eks. `container-user`) | `/home/container-user/.claude` |

Stien kan aflæses fra `"remoteUser"` eller `"containerUser"` i `devcontainer.json`, eller fra `USER`-instruktionen i Dockerfile.

### 2. Tilføj mount i devcontainer.json

Tilføj mountet under `"mounts"`-nøglen. Brug `${localWorkspaceFolderBasename}` så hvert projekt får sit eget volume:

```json
"mounts": [
  "source=claude-${localWorkspaceFolderBasename},target=/home/vscode/.claude,type=volume"
]
```

Ret `target`-stien til den korrekte hjemmemappe fra trin 1.

Fuld eksempel på en minimal `devcontainer.json` med mountet:

```json
{
  "name": "Mit projekt",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "mounts": [
    "source=claude-${localWorkspaceFolderBasename},target=/home/vscode/.claude,type=volume"
  ]
}
```

Bruger projektet `docker-compose.yml` med devcontainer, tilføj stadig mountet i `devcontainer.json` under `"mounts"` — VS Code merger dem automatisk med Compose-konfigurationen.

### 3. Afslut og bed om rebuild

Når mountet er tilføjet, skal du bede brugeren om at genbygge containeren:

> Mountet er tilføjet. Genbyg containeren for at aktivere det:
> **Ctrl+Shift+P → "Dev Containers: Rebuild Container"**
>
> Verificer bagefter at volumet virker:
> ```bash
> ls ~/.claude/
> ```
> Installér et plugin, genbyg igen — plugin'et skal stadig være der efter rebuild.

## Vigtige noter

- **Hvert projekt får sit eget volume** takket være `${localWorkspaceFolderBasename}` — plugins deles ikke på tværs af projekter.
- **Volumet overlever `docker compose down`** — brug `docker volume rm claude-<projektnavn>` hvis du vil starte helt fra scratch.
- **Credentials gemmes i `~/.claude/.credentials.json`** — de bevares også med dette mount, så du ikke skal logge ind igen efter rebuild.
- **Kun devcontainer.json styrer dette mount** — tilføj det ikke direkte i `docker-compose.yml`, da VS Code's devcontainer-runtime tilføjer det ovenpå Compose-konfigurationen.
