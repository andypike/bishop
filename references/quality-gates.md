# Quality Gates

How `skills/ticket-workflow/SKILL.md` runs and interprets each tool. There are
no fixed pass/fail numbers here (see the style guide's "Quality gate
philosophy" section) — everything is judged as baseline-vs-after for this
ticket's changes.

**Every command below is written bare (e.g. `bundle exec rspec`) for
readability.** Every project runs inside Docker Compose — see
[`docker.md`](./docker.md) for how to detect the service and wrap these as
`docker compose exec <service> <command>` (or `run --rm` if nothing's
running). Never run Ruby/Rails tooling on the host.

## Tool detection (Investigation phase)

Before running anything, check the target project for:

- Test framework: RSpec (`spec/spec_helper.rb`, `rspec-rails` in Gemfile.lock)
  vs Minitest (`test/test_helper.rb`).
- `rubocop` in Gemfile / `.rubocop.yml` present.
- `rubycritic` in Gemfile.
- `evilution` in Gemfile.

If any of RuboCop, RubyCritic, or Evilution is missing, **stop and ask** Andy
before adding it as a dev dependency — don't silently modify the Gemfile.

## Baseline capture (kicked off in background during Investigation/Q&A)

Run against the unchanged codebase, in parallel with the Q&A conversation:

- **Tests + coverage**: the project's existing test command (`bundle exec
  rspec` or `bin/rails test`), with whatever coverage tool the project
  already uses (e.g. SimpleCov). Record pass/fail count and coverage %.
- **RuboCop**: `bundle exec rubocop --format json` — record total offense
  count (and count by cop, if useful later).
- **RubyCritic**: `bundle exec rubycritic --format console --minimum-score 0`
  — record the overall score (never fail the baseline run itself; `0` just
  means "don't exit non-zero, we're only measuring").

Mutation testing is **not** part of the baseline — there's no diff yet to
mutate against.

## After implementation (Quality gate phase)

- **Tests**: full suite must be green.
- **RuboCop autocorrect**: `bundle exec rubocop -a` (safe autocorrect only —
  never `-A`/unsafe). Re-run plain `bundle exec rubocop --format json`
  afterwards; whatever remains gets reported, not auto-fixed. Offense count
  must not exceed the baseline.
- **RubyCritic**: `bundle exec rubycritic --format console --minimum-score 0`
  again; score must not regress vs baseline, ideally improves.
- **Evilution (mutation testing)** — scoped to only the files/lines changed
  for this ticket, since we care about coverage of the change, not the whole
  file history:

  ```bash
  docker compose exec <service> bundle exec evilution run \
    <changed-file>:<start-line>-<end-line> [...] \
    --format json --min-score 0.8
  ```

  - Build the `file:line-range` args from the actual diff hunks for this
    ticket.
  - `--min-score` is a starting point (0.8), not a hard rule — use judgement
    per ticket; the real bar is "no unreasonable survivors in the code we
    just wrote." Read `survived[]` in the JSON output and treat each as a
    genuine gap to close with a test, not noise to suppress.
  - Exit code 0 = met threshold, 1 = below threshold, 2 = tool error (parse
    failure, bad config) — don't treat exit 2 as a quality failure, treat it
    as a bug to fix or report.

- **`code-review` skill**: run for reuse/simplification/efficiency findings
  on the diff.
- **Style guide checklist**: walk the changed files against
  `style-guide/rails-style-guide.md`.

Report all of the above — baseline vs after, plus the mutation score and any
survivors — to Andy before moving to the correctness check.
