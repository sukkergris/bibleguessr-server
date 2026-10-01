# Persist the API's SQLite database in a named volume

**As** the operator of bibleguessr,
**I want** the API's database to live in a named Docker volume,
**so that** a redeploy does not wipe today's daily quiz and players see the
same verses all day.

This must be in place before releasing **v0.0.5** (frontend revision 16,
backend revision 7).

## Background

From v0.0.5 the API keeps a SQLite database at `/data/db/bibleguessr.db`. The
image declares `VOLUME /data/db` and sets `Database__FilePath` itself.

`bibleguessr-api` in `docker-compose.yml` has no mount for `/data/db`, so
Docker creates an anonymous volume per container. On the next deploy that
volume is left behind, the quiz is lost, and a new one is drawn in the middle
of the day. Players then get different verses than they did in the morning.

## Acceptance criteria

- [ ] `docker-compose.yml` mounts a named volume (e.g. `bible-db`) at
      `/data/db` on `bibleguessr-api`, the same way `bible-data` is mounted at
      `/data/bibles`, and the volume is declared under `volumes:`.
- [ ] If a bind mount is used instead, the host directory is writable by the
      container's `apiuser` (UID 1000).
- [ ] After `task docker:site:down` / `task docker:site:up`, today's quiz is
      unchanged.
- [ ] The backup procedure is documented (see below).

## Backup

Do not copy the database file while the API is running. Either:

- run `sqlite3 bibleguessr.db ".backup backup.db"`, or
- stop the API and copy all three files: `.db`, `-wal` and `-shm`.

## Out of scope

**nginx: no changes needed.**

- `location /api/` already forwards everything under `/api/`, including the
  new `/api/daily-quiz`.
- The `api_limit` rate limit (burst 20) covers the new traffic: one quiz fetch
  and five verse lookups per quiz. The ping in the nerd panel runs only while
  the panel is open, every 5 seconds.
- `/hubs/` (SignalR) is unchanged.

**Settings: nothing new to set.**

| Setting                 | Default                                       | Note                                       |
| ----------------------- | --------------------------------------------- | ------------------------------------------ |
| `Database__FilePath`    | Set in the image to `/data/db/bibleguessr.db` | Change only to put the file somewhere else |
| `DailyQuiz__VerseCount` | `5`                                           | Optional                                   |

## Good to know

- **First start:** the API creates the database and tables itself and
  generates today's quiz immediately. After that, a new quiz is generated
  every day at 00:00 UTC.
- **Architectures:** the amd64 build has been verified to ship the correct
  x86-64 SQLite library, and the arm64 image has also been run.
- **Old and new clients:** the game-type wire format is unchanged, so open
  tabs with the old frontend can still play against the new backend. The new
  scoring rules for Chapters apply as soon as the backend is switched.
- **Restart:** as always, rooms and multiplayer games in progress are lost,
  since they live only in memory.
- **CI:** `play-request.spec.ts` can be flaky when tests run in parallel. This
  is a known, pre-existing issue. If it fails in CI, re-run before looking for
  a real bug.

## References

Operational details on the database, backup and settings: `docs/web/daily-quiz`
in the app repo.
