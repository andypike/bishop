# Running commands in Docker Compose

Every project this workflow runs against lives inside a Docker container
managed by `docker-compose` (or the `docker compose` v2 plugin). **Nothing
Ruby/Rails-related — tests, RuboCop, RubyCritic, Evilution, `bin/rails`,
`bundle` — runs on the host.** Every command referenced elsewhere in this
plugin (`quality-gates.md`, `SKILL.md`) is written as a bare shell command for
readability; always wrap it per this file before running it.

## Detect the setup (part of Phase 2 — Investigation)

1. **Find the compose file**: `docker-compose.yml` / `docker-compose.yaml` /
   `compose.yml` at the project root (or wherever the ticket's project lives).
   If there isn't one, stop — this project isn't containerized the way Andy
   described, and the wrapping below doesn't apply. Ask before assuming
   anything.
2. **Pick the CLI**: prefer the `docker compose` v2 plugin; fall back to the
   standalone `docker-compose` binary if v2 isn't available.
   ```bash
   docker compose version >/dev/null 2>&1 && echo "docker compose" || echo "docker-compose"
   ```
3. **Identify the app service** — the service that runs the Rails app (has
   the Gemfile mounted, is where you'd run `bundle exec`). Usually named
   `web` or `app`, but confirm from the compose file rather than assuming:
   look for the service whose `build.context`/`Dockerfile` is the project
   root, or that mounts the project directory as a volume. If more than one
   service plausibly fits, ask which one.

## Choosing `exec` vs `run --rm`

- If the service is already running (`docker compose ps --status running`
  includes it), use `exec`:
  ```bash
  docker compose exec <service> <command>
  ```
- If it's not running, don't require Andy to start it first — use a one-off
  container instead:
  ```bash
  docker compose run --rm <service> <command>
  ```

## Examples

Given service name `web`:

```bash
docker compose exec web bundle exec rspec
docker compose exec web bundle exec rubocop -a
docker compose exec web bundle exec rubycritic --format console --minimum-score 0
docker compose exec web bundle exec evilution run app/models/foo.rb:10-25 --format json --min-score 0.8
docker compose exec web bin/rails db:prepare   # only if a migration is part of the ticket
```

## Gotchas

- Interactive/TTY flags aren't needed for these one-shot commands — don't add
  `-it` when capturing output programmatically.
- If a command needs the test database prepared and CI/dev seed state isn't
  already there, that's a project-specific setup step, not something this
  workflow should silently trigger — ask if a run fails for that reason
  rather than guessing at `db:test:prepare`/`db:prepare` invocations.
- Bind-mount lag: if RuboCop/RubyCritic output looks stale right after an
  autocorrect, re-run rather than trusting a cached result — some compose
  setups have slower volume sync.
