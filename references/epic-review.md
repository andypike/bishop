# Epic Review

Every ticket's PR is code reviewed on its own, but nothing reviews the epic as a whole: how tickets merged weeks apart fit together, code duplicated across them, and assumptions one ticket made that a later one broke. The epic review does that once a project's tickets are all merged, before the client tests the epic.

It's optional. The orchestrator offers it when the project finishes (step 7 of the orchestrate skill), and the developer can also ask for one at any time with `/bishop:orchestrate "<project>" review`. It runs in the orchestrator's session with the developer present, after the loop has stopped, so nothing else changes the epic while it runs.

Everything here runs from the project's main checkout, like the rest of the orchestrator.

## State

```
~/.bishop/<repo>/
  worktrees/epic-review/            the review's worktree, on the fix branch
  <project-slug>/
    epic-review-<n>/                one folder per review, numbered from 1
      findings.md                   every finding, with the developer's decision
      prompt.md                     the fixer's prompt
      run-<n>.json, run-<n>.stderr  the fixer's output
      pid                           the fixer's PID, while it runs
      baseline.md, summary.md       written by the fixer
      progress.md                   one line per step, as for a ticket
```

`project.md` keeps a **Reviews** list: one line per review with its number, date, the epic SHA it reviewed, and the outcome (`declined`, `<n> fixed · <n> deferred`, or `fixes not pushed`). The orchestrator offers a review at finish only when the epic's current SHA (`git rev-parse origin/<epic branch>`) differs from the last one on that list, so a project that finishes twice without new merges isn't asked twice.

## Offering it

Ask with `AskUserQuestion`, naming the epic branch and how many tickets merged into it:

- **Review the epic** — run it now, as below.
- **Not now** — record `declined` in the Reviews list and end.

## 1. Set up

1. `git fetch origin <epic branch> <root branch>`, then find where the epic started: `git merge-base origin/<root branch> origin/<epic branch>`.
2. Create the review worktree on a new fix branch, `<epic name>_review_fixes` (the epic's name without `epic/`, e.g. `csv_export_review_fixes`), the same way a ticket's worktree is made in `references/git.md`, and copy in the files listed in `project.md`. If the worktree or branch is left over from an earlier review, remove them first (`git worktree remove`, `git branch -D`); if git refuses, stop and report it.
3. Create the next `epic-review-<n>` folder and append `Review · started · <short epic SHA>` to its `progress.md`.

## 2. Review

Invoke the `code-review` skill at **`xhigh`** effort on the epic's whole change: the diff from the merge-base to `origin/<epic branch>`, with files read from the review worktree. Say in the request that each ticket was already reviewed alone, so the most valuable findings are the ones only visible across tickets — but don't limit it to those.

It fans out to many reviewers and verifiers and can run for a long time; log `Review · code review · running` before it starts.

## 3. Report and decide

Write every finding to `findings.md`, numbered, then show the developer the same as a table: number, file and line, a one-line summary, and a **recommendation**:

- **Fix** — the review confirmed it (a verifier reproduced it or traced it in the source).
- **Look** — plausible but unconfirmed, or a clean-up whose value is a judgement call.

Below the table, give the detail of each finding: what goes wrong and when, and the fix the review suggests.

Then ask with `AskUserQuestion`:

- **Fix the recommended ones** (first, as the default) — fix every **Fix** finding; defer every **Look**.
- **Fix all** — fix every finding.
- **Choose** — the developer names which to fix; the rest are deferred.
- **Defer all** — fix nothing.

If anything is deferred, ask how to record it, again with `AskUserQuestion`:

- **Linear tickets** — one ticket per finding in the project, in Todo, **without** `agent:claimable`: the developer releases any they want worked and restarts the orchestrator. Title it after the finding; the description gives what goes wrong, where, the suggested fix, and that it came from the epic review.
- **Feature document** — add the findings to an **Epic review** section at the end of the feature document (fetch it fresh, append, save).
- **Not recorded** — `findings.md` is the only record.

The developer may answer with something else (group some findings into one ticket, record only some); do what they say. Record each finding's decision in `findings.md`.

If nothing is to be fixed, go to [Finish](#6-finish).

## 4. Fix

A headless fixer makes the fixes, the same way a worker works a ticket: in the review worktree, kept apart the same way (its own databases, for Rails), under `settings/worker.json`. The orchestrator never writes code.

1. Do the stack's setup, per "At claim" in the stack's `environment.md`, using `review` as the ticket ID.
2. Write `prompt.md`:

   ```markdown
   Fix findings from a code review of the epic branch <epic branch>, following the "Fixing findings" section of <plugin root>/references/epic-review.md.

   - worktree: <review worktree> (your current directory), on branch <fix branch>, cut from <epic branch>.
   - state directory: <review state dir>
   - stack: <stack ID> — use the files in <plugin root>/stacks/<stack ID>/.
   - findings to fix: numbers <list>, in <review state dir>/findings.md. Ignore the others.

   <the stack's block, per "Worker prompt" in the stack's environment.md, filled in with `review` as the ticket>

   Run until every listed finding is fixed or skipped and summary.md is written, then exit.
   ```

   Add any skipped quality tools as for a ticket's prompt (see "Worker prompt" in the orchestrate skill).
3. Start it: `<plugin root>/bin/start-worker <review worktree> <review state dir> <plugin root>`, and append `Review · fixing <n> findings` to `progress.md`.
4. Wait for it: run `<plugin root>/bin/wait-for-worker <review state dir>` with `run_in_background`. You're notified when the fixer exits. Tell the developer it's running and that `bin/agent-status` shows its progress.

If the fixer's run ends on a usage limit or crashes, resume it once with its session ID (from the run's JSON) and a `resume-prompt.md` saying it stopped before finishing and should carry on from its commits and `summary.md`. After a second failure, stop and report it with the log path.

## 5. Push

Read `summary.md` and the fix branch's commits (`git log --oneline origin/<epic branch>..<fix branch>`), then:

- **Gate clean, every finding fixed or skipped with a reason** — push the commits to the epic:

  ```bash
  git push origin <fix branch>:<epic branch>
  ```

  Run it alone. It only fast-forwards: if the epic moved since the review started, git rejects it — report that and leave the branch for the developer. Nothing is ever force-pushed.
- **Gate not clean** — don't push. Show the developer what failed (from `summary.md`) and ask whether to push anyway or leave the branch for them to finish.

Report each finding's outcome — fixed with its commit, or skipped and why. Record skipped findings the way the developer chose for deferred ones.

## 6. Finish

1. Unless the fix branch was left for the developer: remove the review worktree (`git worktree remove`, without `--force`), delete the fix branch (`git branch -D <fix branch>`), and undo the stack's setup for the review per "Cleaning up" in the stack's `environment.md`.
2. Add the review to the Reviews list in `project.md`, with the epic SHA after any push.
3. Append `Cleaned up · review <n>` to `progress.md`.
4. End with a short summary: findings fixed and pushed, findings deferred and where they were recorded, and anything left for the developer.

## Fixing findings

**For the fixer** — the headless agent started in step 4. There's no Linear ticket and nobody in the session: never post to Linear, never open a PR, and never push. The orchestrator pushes once you've finished.

Log progress to `<state dir>/progress.md` the way the ticket-workflow skill's "Progress log" section describes, with `Fix <number>` in place of a slice.

1. **Check the branch**: `git branch --show-current` must be the fix branch in the prompt. If it isn't, write that in `summary.md` and exit.
2. **Baseline**: capture the stack's baseline per its `quality-gates.md`, through the prefix in your prompt, and write it to `baseline.md`.
3. **Each finding**, in number order:
   1. Read it in `findings.md`, then check it against the real source. If it isn't real, skip it: say what you checked.
   2. If fixing it needs a decision the review didn't settle — a choice between behaviours, a change to the architecture document, a migration on data the client already has — skip it and say what needs deciding.
   3. Otherwise fix it test first, per Phase 5 of the ticket-workflow skill in auto mode: write a test that fails because of the finding, make it pass, and commit with a short, specific message. A clean-up with no behaviour change needs no new test, only the suite still passing.
4. **Quality gate**: run Phase 6 of the ticket-workflow skill in auto mode against your baseline and your diff from the epic (`git diff origin/<epic branch>...HEAD`), with up to two retries. Skip the architecture check unless a fix touched a component the architecture document describes.
5. **Write `summary.md`**: whether the gate is clean (and if not, what still fails), then every listed finding with its outcome — fixed (commit SHA and one line on the fix) or skipped (why) — and the gate's figures against the baseline.

Follow the stack's style guide, as for any ticket.
