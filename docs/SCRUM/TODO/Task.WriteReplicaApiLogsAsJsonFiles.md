# Write the replica's API logs as JSON files

The host replica should run as close to production as possible, and also
leave its logs behind as JSON files that can be analyzed afterwards.
Production writes only to the console (`backend/Api/appsettings.Production.json`
in the app repo), so today the replica's logs are gone once the process
stops.

Most of the code change lives in the app repo (`../bibelguessr`); this repo
only owns the part where the replica runs the Docker image.

## Requirements

- A new environment, `ASPNETCORE_ENVIRONMENT=Replica` (or a launch profile),
  with a `backend/Api/appsettings.Replica.json` that is checked into git.
  Add it to the `.gitignore` exceptions if a rule would exclude it.
- It uses production's log levels plus a File sink:
  - `path: logs/bibleguessr-api-.json`. The `.json` extension keeps the files
    clear of the `*.log` rule in `.gitignore` in contexts where they should
    be included. `logs/` itself stays in `.gitignore`.
  - `rollingInterval: Day`, `retainedFileCountLimit: 7`, a
    `fileSizeLimitBytes`, and `rollOnFileSizeLimit: true`.
  - `RenderedCompactJsonFormatter`, the same format as production, so the
    same `jq` queries work in both places.
- If the replica later runs the Docker image instead of `dotnet run`, mount
  `logs/` as a volume owned by `apiuser` (UID 1000), like `bible-data` in
  `docker-compose.yml`.

## Usage

```bash
jq 'select(."@l"=="Error")' logs/*.json
jq 'select(.SourceContext|startswith("BibleGuessr"))' logs/*.json
```

## Source

Item 2 ("Hostreplica (JSON-filer)") in the former `docs/SCRUM/Plan.md`.
