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
    --format json --min-score 0.8
  ```

  - Use the diff hunks for this ticket to find *which methods* changed, then widen each range to whole methods (see pitfalls below).
  - `--min-score` is a starting point (0.8), not a hard rule — use judgement per ticket; the real bar is "no unreasonable survivors in the code we just wrote." Read `survived[]` in the JSON output and treat each as a genuine gap to close with a test, not noise to suppress.
  - Exit code 0 = met threshold, 1 = below threshold, 2 = tool error (parse failure, bad config) — don't treat exit 2 as a quality failure, treat it as a bug to fix or report.

  **Evilution pitfalls.** Each of these produces a confident score over work that never happened, so a clean result is not trustworthy until they've been ruled out:

  - **Run it strictly alone.** Evilution mutates source files on disk while it runs. The test suite, RuboCop, RubyCritic or a review agent running at the same time will see half-mutated code and report nonsense. Finish every other check first, and never background Evilution beside another task.
  - **Ranges must enclose whole methods.** A line or range that only partly covers a method produces no mutations for it — silently, with `score: 1.0`. Widen each range from `def` to `end`; don't pass diff hunk lines directly.
  - **One range per file per invocation.** Passing the same file twice (`foo.rb:16-30 foo.rb:38-42`) silently keeps only the **last** range for that file. Either widen to one range covering all changed methods in the file, or run one invocation per range.
  - **Pass `--spec` explicitly.** Evilution picks the spec by name convention (`app/models/foo.rb` → `spec/models/foo_spec.rb`) and runs nothing else. Code covered by a caller's spec (feature, request, integration, list/query object specs) then reports false survivors or false `neutral`s. Pass `--spec a_spec.rb,b_spec.rb` with every spec that pins the behaviour. `--spec` applies to the whole invocation, which is another reason to run one invocation per target. A stderr line `No matching test found for <file>, running full suite` means that target contributed nothing.
  - **Use `--example-targeting coverage`.** The default (`lexical`) picks examples by grepping their names for the mutated method, and falls back to every example in every `--spec` file when nothing matches. It can skip the very example that would kill a mutation and file the result as `neutral`. On BRIG-136 (2026-10-01), `lexical` left 7 killable mutations neutral — including removing the line that uploads a file, which a spec did catch — while `coverage`, which runs only the examples that execute the mutated line, killed all 7. It was ~20% slower on a target with fast model specs; its speed on feature-spec-heavy targets is unmeasured. Use it for accuracy: it makes `neutral[]` worth reading instead of a list of false alarms to hand-check.
  - **Read `neutral[]` and `unresolved`, not just `survived[]`.** The score ignores `neutral`, and some genuinely uncaught mutations land there. Sort each neutral mutation into "can't change behaviour" (e.g. `size`→`length`) or "real gap, needs a spec". A neutral with 0 killed and 0 survived means nothing exercised those lines at all.
  - **Verify the mutated lines.** After every run, compare the line numbers in the JSON's `killed` + `survived` against the methods you asked for. A requested method with zero mutations means one of the pitfalls above hit — fix the invocation and re-run.
  - **ActiveRecord models with an `enum` can't be mutated.** Evilution reloads the file per mutation and Rails raises on the duplicate enum definition. Every mutation errors, or `total` comes back 0, and the score reads 0.0. That's a tool failure, not a quality regression: check `total` before reading anything into a 0.0, and fall back to behavioural specs plus hand-mutating the code to confirm a spec fails.

- **`code-review` skill**: run for reuse/simplification/efficiency findings on the diff.
- **Style guide checklist**: walk the changed files against `style-guide/rails-style-guide.md`.

Report all of the above — baseline vs after, plus the mutation score and any survivors — to the developer before moving to the correctness check.
