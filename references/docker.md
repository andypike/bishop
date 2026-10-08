# Running commands in Docker Compose

Every project this workflow runs against lives inside a Docker container managed by `docker-compose` (or the `docker compose` v2 plugin). **Nothing Ruby/Rails-related — tests, RuboCop, RubyCritic, Evilution, `bin/rails`, `bundle` — runs on the host.** Every command referenced elsewhere in this plugin (`quality-gates.md`, `SKILL.md`) is written as a bare shell command for readability; always wrap it per this file before running it.

Interactive mode runs commands in the developer's own stack, as described in the sections below. Auto mode workers never do: they use their **worker prefix**, which runs the worktree's code in a one-off container with the worker's own databases. See [Worker mode](#worker-mode-auto-mode).

## Detect the setup (part of Phase 2 — Investigation)

1. **Find the compose file**: `docker-compose.yml` / `docker-compose.yaml` / `compose.yml` at the project root (or wherever the ticket's project lives). If there isn't one, stop — this project isn't containerized, and the wrapping below doesn't apply. Ask before assuming anything.
2. **Pick the CLI**: prefer the `docker compose` v2 plugin; fall back to the standalone `docker-compose` binary if v2 isn't available.
   ```bash
   docker compose version >/dev/null 2>&1 && echo "docker compose" || echo "docker-compose"
   ```
3. **Identify the app service** — the service that runs the Rails app (has the Gemfile mounted, is where you'd run `bundle exec`). Usually named `web` or `app`, but confirm from the compose file rather than assuming: look for the service whose `build.context`/`Dockerfile` is the project root, or that mounts the project directory as a volume. If more than one service plausibly fits, ask which one.

## Choosing `exec` vs `run --rm`

- If the service is already running (`docker compose ps --status running` includes it), use `exec`:
  ```bash
  docker compose exec <service> <command>
  ```
- If it's not running, don't require the developer to start it first — use a one-off container instead:
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

- Interactive/TTY flags aren't needed for these one-shot commands — don't add `-it` when capturing output programmatically.
- If a command needs the test database prepared and CI/dev seed state isn't already there, that's a project-specific setup step, not something this workflow should silently trigger — ask if a run fails for that reason rather than guessing at `db:test:prepare`/`db:prepare` invocations.
- Bind-mount lag: if RuboCop/RubyCritic output looks stale right after an autocorrect, re-run rather than trusting a cached result — some compose setups have slower volume sync.

## Worker mode (auto mode)

Several workers run at once, each in its own git worktree. They share the project's stack — database server, Redis, and other services — but each worker gets:

- **its own app container**: a one-off `run --rm` container with the worktree mounted as the app's code, so tests run the worktree's code rather than the developer's checkout;
- **its own databases**: development and test databases named after the ticket, so one worker's migrations and test data never touch another's.

The orchestrator works out a **worker prefix** for the project at preflight and passes each worker its filled-in copy. The worker puts it in front of every Ruby/Rails command, verbatim.

### The worker prefix

```bash
docker compose -p <project> -f <main checkout>/<compose file> run --rm \
  [--entrypoint <binary>] \
  -v <worktree>:<app dir> \
  -v <main checkout>/.git:<main checkout>/.git \
  -e <dev db var>=<dev db name>_<ticket> -e <test db var>=<test db name>_<ticket> \
  <service> [<command prefix>] <command>
```

For example — a fictitious project, `acme/shop`, checked out at `/home/dev/code/shop`, with an app service `web`, a stack named `shop`, and ticket ENG-123:

```bash
docker compose -p shop -f /home/dev/code/shop/docker-compose.yml run --rm \
  --entrypoint bundle \
  -v /home/dev/.bishop/shop/worktrees/ENG-123:/usr/src/app \
  -v /home/dev/code/shop/.git:/home/dev/code/shop/.git \
  -e SHOP_DB_DATABASE=shop_development_eng123 -e SHOP_TEST_DB_DATABASE=shop_test_eng123 \
  web exec rails test TEST=test/helpers/price_helper_test.rb
```

Both sides of the `.git` mount are the same absolute path.

### Working out the prefix (orchestrator, at preflight)

Each part has a reason; skip one and the worker silently runs the wrong code or touches shared data.

1. **Project name (`-p`)** — the developer's existing stack, so the worker shares its services instead of Compose starting a second stack named after the worktree directory. Use the name in `docker compose ls`, or the prefix on the project's volumes in `docker volume ls`; it defaults to the main checkout's directory name.
2. **Compose files (`-f`)** — the main checkout's files, given explicitly, because the worker runs from the worktree. Leave out any file that mounts the app's code through a named or external volume (for example a `docker-sync` override such as `shop_sync:/usr/src/app`): that volume mirrors the developer's checkout and would hide the worktree. A plain bind mount of the checkout (`.:/app`) can stay: the worker's own `-v <worktree>:/app` replaces it.
3. **App dir** — where the code lives in the container: the target of the app service's code mount, or the `Dockerfile`'s final `WORKDIR`.
4. **`.git` mount** — a worktree's `.git` is a file pointing at `<main checkout>/.git/worktrees/<name>`. Mounting the main `.git` at the same absolute path makes git work inside the container, which Evilution's diff scoping needs.
5. **Entrypoint** — if the image's entrypoint script lives on a volume the worker doesn't mount (for example an entrypoint provided by the same sync volume), override it: `--entrypoint bundle` with `exec` as the command prefix. Test the plain form first and override only if it fails.
6. **Database names** — find how `config/database.yml` picks each environment's database name:
   - `<%= ENV['SOME_VAR'] %>` → pass that variable, with the ticket ID appended to its usual value (lowercase: `shop_test_eng123`);
   - a hard-coded name → pass `DATABASE_URL` instead, built from the environment's host, user and password in `database.yml` (Rails merges it over `database.yml` for the environment being run). One URL names one database, so this gives the worker **two prefixes**: a **test prefix** (`…/<test db name>_<ticket>`) for tests and every quality tool, and a **development prefix** (`…/<dev db name>_<ticket>`) used only to prepare and migrate the development database. Running tests with the development prefix would wipe that database;
   - **every** database the app connects to in that environment needs its own per-worker name, not just the primary one: Rails multi-db entries, other named connections in `database.yml` (a legacy or reporting database), anything the test suite connects to. Pass each one's variable or URL. A connection that leaves its database name unset falls back to libpq's `PGDATABASE` (or the user's default database): pass `PGDATABASE=<name>_<ticket>` to separate it. Only stop if a database's name can't be set per worker; preflight reports it, and the project runs with one worker.

   Rails' own tasks (`db:test:prepare`, `db:prepare`) only create the databases Rails manages. Any other per-worker database must exist before the worker's first test run: the orchestrator creates it when it claims the ticket (`CREATE DATABASE` through the database service, as in "Cleaning up" below) and drops it at clean-up. Preflight records which ones need this.

   Verify before any worker starts, by checking which database a worker container actually connects to:
   ```bash
   <prefix> rails runner -e test 'puts ActiveRecord::Base.connection_db_config.database'
   ```
   It must print the per-ticket name.
7. **Gitignored files** — a new worktree has none of the developer's ignored-but-required files (commonly `.env` and untracked files under `config/`). List them in the main checkout with `git ls-files --others --ignored --exclude-standard`, keep configuration (for example `.env*`, `config/**`, local `db/*.sqlite3`), skip caches and build output (`node_modules`, `tmp`, `log`, `public/assets`, editor folders), and copy the rest into every new worktree. They stay ignored, so they can't be committed.

Record the prefix and the file list with the project's orchestrator state; they only change when the project's Docker setup does.

### Shared services that tests write to

Only the databases are separated per worker. Any other service the test suite **writes** to is shared, and two workers running tests at once can corrupt each other's results. Search is the usual case: a suite that rebuilds or wipes Elasticsearch/OpenSearch indexes (common with Searchkick or Chewy) does it to index names shared by every worker.

Preflight looks for this — a search gem in the `Gemfile`, plus index setup or cleanup in the test support files — and checks whether index names can carry a per-worker suffix (with Searchkick, `Searchkick.index_suffix = ENV["…"]`). If they can, the prefix passes that variable like the database names. If not, preflight reports it, and the orchestrator runs that project with one active worker until the project adds the suffix.

### Using it (worker)

- Every Ruby/Rails command goes through the prefix, never `exec` into the developer's running service: that runs the developer's checkout, not yours.
- Databases start empty. The test database is created on the first `rails test:db` (or `db:test:prepare`). Create the development database with `db:prepare` only when the ticket has a migration, before running it, so `db/schema.rb` is dumped from your own database.
- Leave the shared stack running: stopping or removing its services would break every other worker and the developer's own environment. `settings/worker.json` denies those commands.

### Cleaning up (orchestrator)

When the ticket reaches QA or Done, drop the worker's databases through the service that holds each one (development and test may be separate services):

```bash
docker compose -p <project> exec <db service> psql -U <user> -c "DROP DATABASE IF EXISTS <db name>_<ticket>;"
```

One command per database, including any the orchestrator created at claim. `IF EXISTS` matters: the development database only exists if the ticket had a migration.
