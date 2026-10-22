# Quality Gates

How `skills/ticket-workflow/SKILL.md` runs and interprets each tool. There are no fixed pass/fail numbers here (see the style guide's "Quality gate philosophy" section) — everything is judged as baseline-vs-after for this ticket's changes.

**Every command below is written bare (e.g. `bundle exec rspec`) for readability.** Every project runs inside Docker Compose — see [`docker.md`](./docker.md) for how to detect the service and wrap these as `docker compose exec <service> <command>` (or `run --rm` if nothing's running). Never run Ruby/Rails tooling on the host.

## Tool detection (Investigation phase)

Before running anything, check the target project for:

- Test framework: RSpec (`spec/spec_helper.rb`, `rspec-rails` in Gemfile.lock) vs Minitest (`test/test_helper.rb`).
- `rubocop` in Gemfile / `.rubocop.yml` present.
- `rubycritic` in Gemfile.
- `evilution` in Gemfile.

If any of RuboCop, RubyCritic, or Evilution is missing, **stop and ask** the developer before adding it as a dev dependency — don't silently modify the Gemfile.

## Baseline capture (kicked off in background during Investigation/Q&A)

Run against the unchanged codebase, in parallel with the Q&A conversation:

- **Tests + coverage**: the project's existing test command (`bundle exec rspec` or `bin/rails test`), with whatever coverage tool the project already uses (e.g. SimpleCov). Record pass/fail count and coverage %.
- **RuboCop**: `bundle exec rubocop --format json` — record total offense count (and count by cop, if useful later).
- **RubyCritic**: `bundle exec rubycritic --format console --minimum-score 0` — record the overall score (never fail the baseline run itself; `0` just means "don't exit non-zero, we're only measuring").

Mutation testing is **not** part of the baseline — there's no diff yet to mutate against.

**Knowing a run has finished.** Wait for the command to **exit**, never for a phrase in its output. Summary lines differ between test frameworks and reporters — RSpec prints `N examples, N failures`, plain Minitest `N runs, …`, minitest-reporters `N tests, …` — so a loop that greps the log for one of them can wait forever on a project that prints another. In auto mode there's no conversation to keep responsive, so run each command in the foreground with a long timeout (a full suite can take several minutes). If a command must run in the background, wait on its exit — the background task's completion notification, or `wait <pid>` — and give any polling loop a time limit. Read the exit status and the summary line only once it has ended.

## After implementation (Quality gate phase)

- **Tests**: full suite must be green.
- **RuboCop autocorrect**: `bundle exec rubocop -a` (safe autocorrect only — never `-A`/unsafe). Re-run plain `bundle exec rubocop --format json` afterwards; whatever remains gets reported, not auto-fixed. Offense count must not exceed the baseline.
- **RubyCritic**: `bundle exec rubycritic --format console --minimum-score 0` again; score must not regress vs baseline, ideally improves.
- **Evilution (mutation testing)** — scoped to only the files/lines changed for this ticket, since we care about coverage of the change, not the whole file history:

  ```bash
  # One invocation per target range — see "Evilution pitfalls" below
  docker compose exec <service> bundle exec evilution run \
    <changed-file>:<method-start-line>-<method-end-line> \
    --spec <own_spec.rb>,<caller_spec.rb> \
    --example-targeting coverage \
    --jobs <n> --warmup rails --incremental -t 60 \
    --format json --min-score 0.8
  ```

  Add `--integration minitest` on a Minitest project.

  **Speed.** Mutation testing is usually the slowest check. Its cost is roughly *mutations × the time each mutation's examples take*, so a target with ~280 mutations turns every extra second per mutation into ~5 minutes of gate time. The command runs mutations in parallel and skips work it has already done, and the spec choice and re-run rules below keep the multiplier small:

  - **`--jobs <n>`** runs that many mutations at once. Each runs in its own forked process, with the mutation applied in memory. **Parallel jobs only help if each one has its own test database** (see "Parallel jobs and the test database" below); without that, pass `--jobs 1`. In auto mode, use the job count and per-job database command the orchestrator gives you. Otherwise, with per-job databases, pick `<n>` once per ticket: run `nproc` inside the container (with the same prefix as every other command), divide by the number of workers that may run at once (the orchestrator's `max_workers` in auto mode, default 2; 1 otherwise), and cap it at 8; never go below 2. If parallel workers trip over the test database anyway, Evilution marks those mutations `neutral` with `infra_error` and re-runs them one at a time, so the score stays honest. A large `summary.infra_retried` means contention, not a coverage problem: halve `<n>` for that project.
  - **`--warmup rails`** loads Rails' locales, routes and asset paths once, instead of in every forked mutation.
  - **`--incremental`** caches killed mutations and skips them on a re-run while the source is unchanged. See "Re-running after killing survivors" below.
  - **`-t 60`** caps each mutation at 60 seconds, so one that loops forever can't stall the gate. It's reported as `timed_out`.

  These settings are still being tuned: record the run's `summary.duration`, `summary.killtime`, `total`, `infra_retried` and the `--jobs` value alongside the score. `killtime / total` is the average seconds per mutation; if it rises well above the single-job figure as `<n>` goes up, the jobs are queuing on something shared.

  **Parallel jobs and the test database.** Evilution sets `TEST_ENV_NUMBER` in each job (`""`, `"2"`, `"3"`, …), following the parallel_tests convention, but Rails has already read `config/database.yml` before the jobs fork, so interpolating it there isn't enough on its own. With every job on one database, tests that insert the same fixed-id rows (seed data loaded in `setup`, for example) wait on each other's open transactions, and the jobs take turns. On a real ticket (2026-10-22), `--jobs 4` on a shared database took 137s for 33 mutations against 146s for `--jobs 1`, with Postgres showing three of the four jobs waiting on a lock. With a database per job the same run took 52s at `--jobs 4` and 36s at `--jobs 8`, with identical results. Per-job databases need, in the project:

  - `config/database.yml`'s test database name ending in `<%= ENV['TEST_ENV_NUMBER'] %>`;
  - a `worker_process_start` hook (in `.evilution.yml` or `config/evilution.yml`) that rebuilds the test database config with the job's `TEST_ENV_NUMBER` and re-establishes every connection pool that uses it, including abstract base classes that call `establish_connection` themselves;
  - the extra databases (`<test db>2` … `<test db><n>`) created from the prepared test database, e.g. `CREATE DATABASE <test db>2 TEMPLATE <test db>`.

  Until a project has these, run `--jobs 1`: more jobs on a shared database cost the same wall-clock time and make every mutation's timing noisy.

  **Coverage.** Leave the project's coverage tool (e.g. `COVERAGE=true` for SimpleCov) off for Evilution runs: it's needed for the test-suite check, not here, and it made each mutation about 25% slower on the same ticket. In auto mode, run Evilution through the mutation prefix the orchestrator gives you; it leaves coverage off.

  **Choosing specs for speed.** Every spec file in `--spec` is a candidate for every mutation, so one slow file multiplies across the whole run:

  - **Start with unit-level specs**: the target's own spec, and model, service, presenter or query specs that call it. Leave out controller, request, feature, system and integration specs; each example boots a request stack and costs far more per mutation. On a real ticket (2026-10-22), a ~280-mutation run of a 93-line service that included one controller test was still running after 30 minutes and had to be stopped.
  - **Time each candidate spec file first**, with a plain test run. Any file much slower than its neighbours is a warning sign. Prefer speeding the file up (shared setup, fewer database writes, building objects in memory instead of creating records) over leaving it in as it is.
  - **Add slower specs only where unit specs leave a gap**: if a method is only exercised through a controller or request spec, run a separate invocation for just that method's range, with just those specs. This keeps the "Pass `--spec` explicitly" pitfall below covered without making every mutation pay for a request stack.

  **Re-running after killing survivors.** Don't re-run the whole target from scratch:

  - Re-run the **same command with `--incremental`**: killed mutations are cached and skipped, so only the survivors run again. Adding tests doesn't invalidate the cache, since it's keyed on the source code, not the tests.
  - If the fix also changed source, narrow the range to the **methods that had survivors or changed**, rather than the whole file. Mutations in unchanged methods were already killed by tests that still exist.
  - Use `--no-incremental` only if a fix **rewrote or removed** tests that killed earlier mutations, and then only over the affected methods.

  - Use the diff hunks for this ticket to find *which methods* changed, then widen each range to whole methods (see pitfalls below).
  - `--min-score` is a starting point (0.8), not a hard rule — use judgement per ticket; the real bar is "no unreasonable survivors in the code we just wrote." Read `survived[]` in the JSON output and treat each as a genuine gap to close with a test, not noise to suppress.
  - Exit code 0 = met threshold, 1 = below threshold, 2 = tool error (parse failure, bad config) — don't treat exit 2 as a quality failure, treat it as a bug to fix or report.

  **Evilution pitfalls.** Each of these produces a confident score over work that never happened, so a clean result is not trustworthy until they've been ruled out:

  - **Run it strictly alone.** Evilution mutates source files on disk while it runs. The test suite, RuboCop, RubyCritic or a review agent running at the same time will see half-mutated code and report nonsense. Finish every other check first, and never background Evilution beside another task.
  - **Ranges must enclose whole methods.** A line or range that only partly covers a method produces no mutations for it — silently, with `score: 1.0`. Widen each range from `def` to `end`; don't pass diff hunk lines directly.
  - **One range per file per invocation.** Passing the same file twice (`foo.rb:16-30 foo.rb:38-42`) silently keeps only the **last** range for that file. Either widen to one range covering all changed methods in the file, or run one invocation per range.
  - **Pass `--spec` explicitly.** Evilution picks the spec by name convention (`app/models/foo.rb` → `spec/models/foo_spec.rb`) and runs nothing else. Code covered by a caller's spec (feature, request, integration, list/query object specs) then reports false survivors or false `neutral`s. Pass `--spec a_spec.rb,b_spec.rb` with every spec that pins the behaviour. `--spec` applies to the whole invocation, which is another reason to run one invocation per target. A stderr line `No matching test found for <file>, running full suite` means that target contributed nothing.
  - **Use `--example-targeting coverage`.** The default (`lexical`) picks examples by grepping their names for the mutated method, and falls back to every example in every `--spec` file when nothing matches. It can skip the very example that would kill a mutation and file the result as `neutral`. On a real ticket (2026-10-01), `lexical` left 7 killable mutations neutral — including removing the line that uploads a file, which a spec did catch — while `coverage`, which runs only the examples that execute the mutated line, killed all 7. It was ~20% slower on a target with fast model specs; its speed on feature-spec-heavy targets is unmeasured. Use it for accuracy: it makes `neutral[]` worth reading instead of a list of false alarms to hand-check.
  - **Read `neutral[]` and `unresolved`, not just `survived[]`.** The score ignores `neutral`, and some genuinely uncaught mutations land there. Sort each neutral mutation into "can't change behaviour" (e.g. `size`→`length`) or "real gap, needs a spec". A neutral with 0 killed and 0 survived means nothing exercised those lines at all.
  - **Verify the mutated lines.** After every run, compare the line numbers in the JSON's `killed` + `survived` against the methods you asked for. A requested method with zero mutations means one of the pitfalls above hit — fix the invocation and re-run.
  - **ActiveRecord models with an `enum` can't be mutated.** Evilution reloads the file per mutation and Rails raises on the duplicate enum definition. Every mutation errors, or `total` comes back 0, and the score reads 0.0. That's a tool failure, not a quality regression: check `total` before reading anything into a 0.0, and fall back to behavioural specs plus hand-mutating the code to confirm a spec fails.

- **`code-review` skill**: run for reuse/simplification/efficiency findings on the diff.
- **Style guide checklist**: walk the changed files against `style-guide/rails-style-guide.md`.

Report all of the above — baseline vs after, plus the mutation score and any survivors — to the developer before moving to the correctness check.
