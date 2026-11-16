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
4. **Check how the code gets into the container.** A plain bind mount of the checkout (`.:/usr/src/app`) is live: the container always sees this checkout's files. A named or external volume (for example a `docker-sync` override such as `shop_sync:/usr/src/app`) is a copy kept up to date by a sync process. If that process isn't running, or lags, tests run against stale code and results are silently wrong. In that case don't use `exec`, or `run --rm` as it stands; bind-mount the checkout over the volume instead:
   ```bash
   docker compose run --rm -v "$PWD":<app path> <service> <command>
   ```
   with `<app path>` the volume's mount point in the service, and the same compose files the developer uses. Announce it in one line (`Running tests with this checkout bind-mounted: the app's code is on a docker-sync volume`), then use this form for every command.

## Choosing `exec` vs `run --rm`

Unless step 4 above found the code on a synced volume, in which case always use its bind-mounted `run --rm`:

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

## Screenshots

How the `browser` target captures a journey, per [`references/screenshots.md`](../../references/screenshots.md). The journey runs as a one-off browser spec that is written for the ticket and never committed. It uses the test database, the project's factories and its sign-in helpers, and drives a headless Chromium with Cuprite.

There are two ways to get a browser, and the project's setup decides which:

- **A browser in the app image.** The app's image has Chromium, and the project already drives it with Cuprite (usually for its JavaScript specs). Use them as they are: nothing to set up, and each test container runs its own browser.
- **A browser container.** The image has no browser. Chromium runs in its own container, which Cuprite drives over a websocket, and the browser loads pages from a Capybara server inside the app container. The two containers reach each other on the project's Docker network. This needs some one-off setup.

Prefer the app image's browser when there is one. The examples use a fictitious project: Compose project `shop`, app service `web`, ticket ENG-123.

### Setup

**A browser in the app image** needs nothing, when both of these are true:

- **The project registers a Cuprite driver**, usually in `spec/support/capybara.rb`, as `Capybara.javascript_driver` or a named driver its specs use.
- **The app image has Chromium.** Check with `command -v chromium chromium-browser google-chrome`, run through the app container.

If the project uses Selenium instead, or has no browser driver, use a browser container.

**A browser container** has four parts. Parts 1 to 3 change the project, so the developer adds them, or approves the agent adding them as their own commit. Part 4 changes only the developer's machine.

**1. The gem**, in the `Gemfile`'s test group:

```ruby
gem "cuprite"
```

Then run `bundle install` the usual way, through the app container.

**2. A driver that's off by default.** Put it in `spec/support/screenshots.rb`, or in `test/support/screenshots.rb` required from `test/test_helper.rb` on a Minitest project. Check that the project loads its support files. Nothing in it runs unless `SCREENSHOTS` is set, so the project's own system tests keep their driver:

```ruby
# Screenshots of the UI for pull requests. Inactive unless SCREENSHOTS is set.
if ENV["SCREENSHOTS"]
  require "capybara/cuprite"

  Capybara.register_driver(:screenshots) do |app|
    Capybara::Cuprite::Driver.new(
      app,
      ws_url: ENV.fetch("CHROME_WS_URL"),
      window_size: [1440, 900],
      timeout: 15,
      process_timeout: 20
    )
  end

  # The browser runs in another container, so the server listens on every interface
  # and pages load from this container's name on the Docker network.
  Capybara.server_host = "0.0.0.0"
  Capybara.server_port = 4000
  Capybara.app_host = "http://#{ENV.fetch('CAPYBARA_APP_HOST')}:4000"

  screenshot_hosts = [ENV.fetch("CAPYBARA_APP_HOST"), URI(ENV.fetch("CHROME_WS_URL")).host]

  RSpec.configure do |config|
    config.before(:suite) do
      if defined?(VCR)
        VCR.configure do |c|
          c.ignore_localhost = true # Capybara checks its server at 0.0.0.0
          c.ignore_hosts(*screenshot_hosts)
        end
      end
      WebMock.disable_net_connect!(allow_localhost: true, allow: screenshot_hosts) if defined?(WebMock)
    end
  end
end
```

The `before(:suite)` hook runs after the project's own WebMock and VCR set-up, so its allow-list wins. Without it, they block Capybara's check that its server has started. On Minitest, put those lines at the end of `test_helper.rb` instead, inside the same `if`.

The variables have distinct names on purpose. Projects often have their own `APP_HOST`, and reusing that name breaks the app's boot.

**3. Allowing the host, only if the project restricts hosts.** If `config.hosts` is set in `config/application.rb` or `config/environments/test.rb`, Rails blocks the browser's requests ("Blocked hosts"). Add this to `config/environments/test.rb`:

```ruby
config.hosts << ENV["CAPYBARA_APP_HOST"] if ENV["CAPYBARA_APP_HOST"].present?
```

It has to go in the environment file: the allowed hosts are fixed when the app boots, before support files load.

**4. A Chromium container**, one per Compose project. The developer and every worker share it:

```bash
docker run -d --name shop-chrome --network shop_default --restart unless-stopped \
  -e TIMEOUT=300000 -e CONCURRENT=10 \
  ghcr.io/browserless/chromium:v2.63.1
```

- **Name:** `<project>-chrome`, where `<project>` is the Compose project name, as in the worker prefix.
- **Network:** the one the app service joins. Usually that's `<project>_default`: `docker network ls --filter label=com.docker.compose.project=<project>`.
- **Image:** pin the version. A newer one can render differently, and the before and after images should come from the same browser.
- **`TIMEOUT`:** browserless ends a session after 30 seconds by default, which a longer journey exceeds.
- **`CONCURRENT`:** must be at least the number of workers, plus one for the developer.

The container stays outside the project's compose file, because compose files often hard-code `container_name`s.

**Assets**, for both routes. Pages come out unstyled unless the CSS and JS are built for the test environment. Before each capture, run the project's build through the app container:
- `bin/rails tailwindcss:build` for `tailwindcss-rails`;
- `bin/rails css:build javascript:build` for `cssbundling-rails` and `jsbundling-rails` (these need Node in the image);
- nothing for plain Propshaft or Sprockets assets, which compile on request.

### Readiness check

**A browser in the app image** is ready when:

1. The project registers a Cuprite driver.
2. Chromium is in the app image. Run `command -v chromium chromium-browser google-chrome` through the app container: it should print a path.
3. The asset build command (see "Assets" above) runs in the app container.

**A browser container** is ready when:

1. `Gemfile.lock` has a `cuprite (` entry.
2. A support file registers the `:screenshots` driver, and the test helper loads it.
3. If the project restricts hosts, `config/environments/test.rb` has the `CAPYBARA_APP_HOST` line.
4. The Chromium container is running:
   ```bash
   docker inspect -f '{{.State.Running}}' shop-chrome
   ```
5. The app container can reach the Chromium container. Run this through the same command form that runs the tests, and it should print `200`:
   ```bash
   ruby -rnet/http -e 'puts Net::HTTP.get_response(URI("http://shop-chrome:3000/json/version")).code'
   ```
6. The asset build command (see "Assets" above) runs in the app container. Failing because the image has no Node counts as not ready.

When the container exists but has stopped, starting it again (`docker start shop-chrome`) is part of setting up, not a project change.

### Capture

1. **Write the journey** as `tmp/screenshots/<TICKET-ID>_spec.rb`. Rails gitignores `tmp/`, so it's never committed. Write it the way the project writes its own browser specs: a system spec with `driven_by`, or a feature spec tagged for its JavaScript driver (`:js`).

   ```ruby
   # One-off screenshots for ENG-123. Not committed.
   require "rails_helper"

   RSpec.describe "ENG-123 screenshots", type: :system do
     before { driven_by :screenshots }       # a browser in the app image: the project's Cuprite driver

     { "desktop" => [1440, 900], "mobile" => [390, 844] }.each do |view, (width, height)|
       it view do
         out = Rails.root.join("tmp/screenshots/out")
         viewport = lambda do |h|
           page.driver.browser.page.command("Emulation.setDeviceMetricsOverride",
                                            width: width, height: h, deviceScaleFactor: 1, mobile: false)
         end
         capture = lambda do |n, step|
           viewport.(page.evaluate_script("document.documentElement.scrollHeight"))
           page.save_screenshot(out.join("#{n}-#{step}-#{view}.png").to_s)
           viewport.(height)
         end
         viewport.(height)

         admin = create(:user, :admin)
         create_list(:order, 2, user: admin)
         sign_in admin                       # the project's own helper

         visit root_path
         click_link "Orders"
         capture.("01", "orders")

         click_link "Export", match: :first
         choose "CSV"
         capture.("03", "export-dialog")
       end
     end
   end
   ```

   - **Give the type explicitly** (`type: :system` or `type: :feature`). A spec outside `spec/` doesn't get its type from its folder, so without one, `page` is undefined.
   - **Set the size through the viewport, not the window.** `viewport` uses the browser's own device emulation, so a view is exactly its width. Window resizing (`resize_to`, `driver.resize`) can't go below Chrome's minimum window width (about 500), and `full: true` resizes the window, undoing the emulation. `capture` makes the viewport as tall as the page, so the image shows all of it, then puts the height back.
   - **One example per view**, each setting its viewport first: the size carries over to the next example in the same browser session.
   - `driven_by` in the spec overrides any project-wide `driven_by :rack_test` hook.
   - Use the project's factories (or fixtures) and sign-in helpers, the way its own browser specs do.
   - On Minitest, the same journey goes in `tmp/screenshots/<TICKET-ID>_test.rb`, as a subclass of `ApplicationSystemTestCase`.
   - **The before run** uses the same file, minus the steps the base code can't reach (a new screen, a factory or route the ticket adds). Those steps are recorded as new.

2. **Build the assets**, as above.
3. **Run the spec.** Turn coverage off: running one spec would overwrite the suite's coverage results. If the project's `.rspec` excludes a tag the spec uses (`--tag ~js` is common), pass it: `--tag js`.

   - **A browser in the app image:** the project's usual test command, for example:
     ```bash
     docker compose run --rm web bundle exec rspec --tag js tmp/screenshots/ENG-123_spec.rb
     ```
   - **A browser container:** add the screenshot settings:
     ```bash
     docker compose exec -e SCREENSHOTS=1 -e CHROME_WS_URL=ws://shop-chrome:3000 -e CAPYBARA_APP_HOST=web \
       web bundle exec rspec tmp/screenshots/ENG-123_spec.rb
     ```
     With `exec`, the app host is the service name. With `run --rm`, give the container a name with `--name shop-shots`, and use that name as the host.
   - **On a synced volume:** use the bind-mounted form from "Detect the setup", step 4.

4. **Move the images** from `tmp/screenshots/out/` in the checkout to `media/before/` or `media/after/` in the media folder. Then empty `tmp/screenshots/out/`. Delete `tmp/screenshots/` once the PR is open.

**Failures.** If a step fails (an element isn't found, or the page errors), read RSpec's output and the failure screenshot Capybara saves in `tmp/capybara`. Fix the journey, not the app, and run it again, once. If it still fails, the target gets a skip line naming the step.

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
  -v <main checkout>/.git:<main checkout>/.git:ro \
  -e <dev db var>=<dev db name>_<ticket> -e <test db var>=<test db name>_<ticket> \
  <service> [<command prefix>] <command>
```

For example — a fictitious project, `acme/shop`, checked out at `/home/dev/code/shop`, with an app service `web`, a stack named `shop`, and ticket ENG-123:

```bash
docker compose -p shop -f /home/dev/code/shop/docker-compose.yml run --rm \
  --entrypoint bundle \
  -v /home/dev/.bishop/projects/csv_export/worktrees/ENG-123:/usr/src/app \
  -v /home/dev/code/shop/.git:/home/dev/code/shop/.git:ro \
  -e SHOP_DB_DATABASE=shop_development_eng123 -e SHOP_TEST_DB_DATABASE=shop_test_eng123 \
  web exec rails test TEST=test/helpers/price_helper_test.rb
```

Both sides of the `.git` mount are the same absolute path, and it's read-only (`:ro`).

### Working out the prefix (orchestrator, at preflight)

Each part has a reason; skip one and the worker silently runs the wrong code or touches shared data.

1. **Project name (`-p`)** — the developer's existing stack, so the worker shares its services instead of Compose starting a second stack named after the worktree directory. Use the name in `docker compose ls`, or the prefix on the project's volumes in `docker volume ls`; it defaults to the main checkout's directory name.
2. **Compose files (`-f`)** — the main checkout's files, given explicitly, because the worker runs from the worktree. Leave out any file that mounts the app's code through a named or external volume (for example a `docker-sync` override such as `shop_sync:/usr/src/app`): that volume mirrors the developer's checkout and would hide the worktree. A plain bind mount of the checkout (`.:/app`) can stay: the worker's own `-v <worktree>:/app` replaces it.
3. **App dir** — where the code lives in the container: the target of the app service's code mount, or the `Dockerfile`'s final `WORKDIR`.
4. **`.git` mount** — a worktree's `.git` is a file pointing at `<main checkout>/.git/worktrees/<name>`. Mounting the main `.git` at the same absolute path makes git work inside the container, which Evilution's diff scoping needs. Mount it **read-only**: reading (`git diff`, `log`, `status`) works, but nothing in the container can move a branch — the main checkout's `.git` holds every branch, `main`/`master` included, and the worker's permission rules don't reach inside the container. Commits happen on the host, where those rules apply.
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

### Mutation testing (orchestrator, at preflight)

Evilution needs two things the rest of the worker's commands don't (see "Parallel jobs and the test database" and "Coverage" in [`quality-gates.md`](./quality-gates.md)):

- **Mutation prefix** — if the worker prefix turns on a coverage tool (for example `-e COVERAGE=true` for SimpleCov), record a copy without it. Workers run Evilution, and its database setup, through the mutation prefix, and everything else through the worker prefix. Setting the variable to an empty value isn't the same as leaving it out: a test helper that checks `if ENV['COVERAGE']` treats `""` as on. If the worker prefix doesn't turn on coverage, the two are the same.
- **Per-job databases** — if the project has a command that copies the test database once per Evilution job, record it, with `<jobs>` as a placeholder, and the job count: `nproc` inside the container divided by the maximum active workers, capped at 8 and no less than 2. Record the names the copies take, so clean-up can drop them. If the project has no such command, record `--jobs 1`, and say what the project would need.

### Screenshots (orchestrator, at preflight)

Only when the `browser` target is ready and isn't opted out (see "Screenshots" above). Workers capture through a **screenshot prefix**, which starts from the mutation prefix, so coverage is off:

- **A browser in the app image:** the mutation prefix as it is. Each worker's container runs its own browser, so nothing more is needed to keep them apart.
- **A browser container:** the mutation prefix, with these inserted before the service name:

  ```bash
  --name <project>-shots-<ticket> -e SCREENSHOTS=1 -e CHROME_WS_URL=ws://<project>-chrome:3000 -e CAPYBARA_APP_HOST=<project>-shots-<ticket>
  ```

  The container name gives the Chromium container something to load pages from, and keeps parallel workers' containers apart. Write `<ticket>` in lowercase (`shop-shots-eng123`): hostnames don't take underscores. Workers share the one Chromium container, each with its own browser session and, as usual, its own test database.

Record which route the project uses, and any tag the spec has to pass because `.rspec` excludes it. Run the readiness check through the worker prefix, using `preflight` as the ticket.

### Preflight checks

Run as part of the orchestrator's preflight (`references/preflight.md`), after the tool check in `quality-gates.md`. Work through "Working out the prefix" above, then:

- **Worker prefix** — build it, with a placeholder for the ticket, and run the database check above using `preflight` as the ticket. It must print `<test db name>_preflight` (and the development name, for `DATABASE_URL` projects). Check every other database the app connects to as well: each must resolve to a per-worker name. ❌ if the primary database can't be separated, explaining the `database.yml` change the project needs. ⚠️ if only a secondary database can't be: the project runs with one worker.
- **Shared services** — per "Shared services that tests write to" above. ⚠️ if tests write to a shared service that can't be separated per worker: the project runs with **one** active worker until it can. Say what the project needs to add.
- **Gitignored files** — list the files to copy into each new worktree, per item 7 of "Working out the prefix" above. Show the list so the developer can spot anything missing or anything that shouldn't be copied.
- **Screenshots**: the readiness check in "Screenshots" above, unless `browser` is opted out for this repo. If it isn't ready, ⚠️ only, with the setup steps that are missing: "set it up, or opt out". Workers then skip it.

**Smoke test command**, for preflight's headless smoke test: `<worker prefix> ruby -v`. If it fails, check whether the Docker socket is reachable from the worker's sandbox.

### Project state

What preflight records for this stack in `project.md`:

- the worker prefix template (and the development prefix, for `DATABASE_URL` projects);
- per-worker databases the orchestrator must create at claim and drop at clean-up, with the service each lives on;
- the mutation prefix, the per-job database command and the job count (or `--jobs 1`), per "Mutation testing" above;
- the files to copy into each worktree;
- screenshots: `browser` ready, not ready (and why), or opted out. When it's ready, also record the route (a browser in the app image, or a browser container), the screenshot prefix template, the asset build command, any tag to pass, and, for a browser container, the Chromium container's name.

### At claim

Once the orchestrator has created a ticket's worktree (or the epic review's, with `review` as the ticket):

1. Copy in the files listed in `project.md`.
2. Create any per-worker databases `project.md` lists for the orchestrator to create.
3. If `browser` screenshots are ready through a browser container, check the Chromium container is running, and `docker start` it if it isn't. If it won't start, leave the target out of this worker's prompt; the PR's skip line will say why.

### Worker prompt

The orchestrator puts this block in the worker's prompt, after the list of inputs, filled in from `project.md`:

```markdown
Docker: put this prefix in front of every Ruby/Rails command — tests, RuboCop, RubyCritic, Evilution, rails. Never use `docker compose exec`, or the Docker commands in the ticket's notes or the project's own docs: those run the developer's checkout, not this worktree.

<test prefix>
```

For a `DATABASE_URL` project, add the development prefix after the test prefix, introduced as: `Development database — only for db:prepare and migrations, never for tests:`. Add the mutation testing settings (see "Mutation testing" above): if the mutation prefix differs from the test prefix, add it, introduced as `Mutation testing — run Evilution and its database setup through this prefix instead (coverage off):`; then either `Before each Evilution run in Phase 6, copy the test database once per job: <per-job database command>, then pass --jobs <n>.` or `Run Evilution with --jobs 1: this project's test database isn't copied per job.`

When `browser` screenshots are ready, add:

```markdown
Screenshots: browser (desktop, mobile), <a browser in the app image | a browser container>. Build the assets with `<asset build command>`, then run the journey spec through this prefix<, passing --tag <tag>>, per "Screenshots" in the stack's environment.md:

<screenshot prefix>
```

Otherwise add `Screenshots: browser skipped: <reason from project.md>`.

### Using it (worker)

- Every Ruby/Rails command goes through the prefix, never `exec` into the developer's running service: that runs the developer's checkout, not yours.
- Databases start empty. The test database is created on the first `rails test:db` (or `db:test:prepare`). Create the development database with `db:prepare` only when the ticket has a migration, before running it, so `db/schema.rb` is dumped from your own database.
- Run Evilution through the mutation prefix, if the orchestrator gave you one. When it gave you a per-job database command, run that first in each Phase 6 pass (after any migrations, since the copies don't follow schema changes), then pass the job count it gave you to `--jobs`.
- Leave the shared stack running: stopping or removing its services would break every other worker and the developer's own environment. `settings/worker.json` denies those commands.

### Cleaning up (orchestrator)

When the ticket reaches QA or Done, drop the worker's databases through the service that holds each one (development and test may be separate services):

```bash
docker compose -p <project> exec <db service> psql -U <user> -c "DROP DATABASE IF EXISTS <db name>_<ticket>;"
```

One command per database, including any the orchestrator created at claim and the per-job copies of the test database. `IF EXISTS` matters: the development database only exists if the ticket had a migration, and the copies only if the worker ran mutation testing.
