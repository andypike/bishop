# Quality Gates

How `skills/ticket-workflow/SKILL.md` runs and judges the quality gate, whatever the stack. The tools, their exact commands, and how to read each one's output are in the stack's own quality gates file: [`stacks/rails/quality-gates.md`](../stacks/rails/quality-gates.md) for Rails. Read both before running any check.

## Baseline vs after

There are no fixed pass/fail numbers here (see the style guide's "Quality gate philosophy" section) — everything is judged as baseline-vs-after for this ticket's changes. The checks run at two points:

- **Baseline** — during Investigation, against the unchanged codebase, in the background while the Q&A goes on. Mutation testing is **not** part of the baseline: there's no diff yet to mutate against.
- **After implementation** — in the Quality gate phase: the same checks again, compared against the baseline, plus mutation testing scoped to this ticket's diff, the code review, and the style guide checklist.

Report all of it — baseline vs after, plus the mutation score and any survivors — to the developer before moving to the correctness check.

## Knowing a run has finished

Wait for the command to **exit**, never for a phrase in its output. Summary lines differ between test frameworks and reporters — RSpec prints `N examples, N failures`, plain Minitest `N runs, …`, minitest-reporters `N tests, …` — so a loop that greps the log for one of them can wait forever on a project that prints another. In auto mode there's no conversation to keep responsive, so run each command in the foreground with a long timeout (a full suite can take several minutes). If a command must run in the background, wait on its exit — the background task's completion notification, or `wait <pid>` — and give any polling loop a time limit. Read the exit status and the summary line only once it has ended.
