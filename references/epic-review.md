# Epic Review

Every ticket's PR is code reviewed on its own, but nothing reviews the epic as a whole: how tickets merged weeks apart fit together, code duplicated across them, and assumptions one ticket made that a later one broke. The epic review does that once a project's tickets are all merged, before the client tests the epic.

It's optional. The orchestrator offers it when the project finishes (step 7 of the orchestrate skill), and the developer can also ask for one at any time with `/bishop:orchestrate "<project>" review`. It runs in the orchestrator's session with the developer present, after the loop has stopped, so nothing else changes the epic while it runs.

It runs from the folder the orchestrator runs in, and every command names its repo, per "Repos" in `references/git.md`. A project spanning repos has an epic branch in each: each repo's epic is reviewed and fixed on its own, and a **cross-repo check** looks at how they fit together. Below, "each repo" means each repo in the `Stacks:` line whose epic changed since the root branch.

## State

```
~/.bishop/projects/<project-slug>/
  worktrees/epic-review-<repo>/     each repo's review worktree, on its fix branch
  epic-review-<n>/                  one folder per review, numbered from 1
    findings.md                     every finding, its repo, and the developer's decision
    progress.md                     one line per step of the review, as for a ticket
  epic-review-<n>-<repo>/           one per repo with findings to fix: its fixer's state
    prompt.md                       the fixer's prompt
    run-<n>.json, run-<n>.stderr    the fixer's output
    pid                             the fixer's PID, while it runs
    baseline.md, summary.md         written by the fixer
    progress.md                     one line per step of the fixer
```

`<repo>` is the repo's name without its owner (`shop-app` for `acme/shop-app`).

`project.md` keeps a **Reviews** list: one line per review with its number, date, the epic SHA it reviewed in each repo, and the outcome (`declined`, `<n> fixed · <n> deferred`, or `fixes not pushed`). The orchestrator offers a review at finish only when some repo's current epic SHA (`git -C <checkout> rev-parse origin/<epic branch>`) differs from the last one on that list, so a project that finishes twice without new merges isn't asked twice.

## Offering it

Ask with `AskUserQuestion`, naming the epic branch and how many tickets merged into it:

- **Review the epic** — run it now, as below.
- **Not now** — record `declined` in the Reviews list and end.

## 1. Set up

For each repo:

1. `git -C <checkout> fetch origin <epic branch> <root branch>`, then find where the epic started: `git -C <checkout> merge-base origin/<root branch> origin/<epic branch>`. A repo whose epic hasn't moved from there has nothing to review: leave it out.
2. Create the repo's review worktree, `worktrees/epic-review-<repo>`, on a new fix branch, `<epic name>_review_fixes` (the epic's name without `epic/`, e.g. `csv_export_review_fixes`), the same way a ticket's worktree is made in `references/git.md`. If the worktree or branch is left over from an earlier review, remove them first (`git -C <checkout> worktree remove`, `git -C <checkout> branch -D`); if git refuses, stop and report it.

Then create the next `epic-review-<n>` folder and append `Review · started · <repo> <short epic SHA>, …` to its `progress.md`.

## 2. Review

For each repo, invoke the `code-review` skill at **`xhigh`** effort on that repo's whole epic change: the diff from its merge-base to `origin/<epic branch>`, with files read from its review worktree. Say in the request that each ticket was already reviewed alone, so the most valuable findings are the ones only visible across tickets — but don't limit it to those. Run the repos one after another, not at once: each review fans out to many agents.

**Cross-repo check** — when more than one repo was reviewed, also check that they fit together. Invoke an `Explore` agent with the architecture document's **API contract**, and both review worktrees' paths, asking it to compare, for every endpoint the epics add or change:

- the backend as built: route, controller, parameters, and the response it serialises, including error responses;
- the app as built: the request its API service sends, the type and mapper it reads the response with, and how it handles each error;
- the contract.

Each mismatch is a finding (a field named differently, a status code the app doesn't handle, an endpoint the app calls that the backend doesn't have), against the repo that departs from the contract — or both, when the contract itself has a gap.

Each review fans out to many reviewers and verifiers and can run for a long time; log `Review · code review · <repo> · running` before each starts, and `Review · cross-repo check · running` before the check.

## 3. Report and decide

Write every finding to `findings.md`, numbered across all repos, then show the developer the same as a table: number, repo, file and line, a one-line summary, and a **recommendation**:

- **Fix** — the review confirmed it (a verifier reproduced it or traced it in the source).
- **Look** — plausible but unconfirmed, or a clean-up whose value is a judgement call.

Below the table, give the detail of each finding: what goes wrong and when, and the fix the review suggests.

Then ask with `AskUserQuestion`:

- **Fix the recommended ones** (first, as the default) — fix every **Fix** finding; defer every **Look**.
- **Fix all** — fix every finding.
- **Choose** — the developer names which to fix; the rest are deferred.
- **Defer all** — fix nothing.

If anything is deferred, ask how to record it, again with `AskUserQuestion`:

- **Linear tickets** — one ticket per finding in the project, labelled with its repo's `stack:*` label, in Todo, **without** `agent:claimable`: the developer releases any they want worked and restarts the orchestrator. Title it after the finding; the description gives what goes wrong, where, the suggested fix, and that it came from the epic review.
- **Feature document** — add the findings to an **Epic review** section at the end of the feature document (fetch it fresh, append, save).
- **Not recorded** — `findings.md` is the only record.

The developer may answer with something else (group some findings into one ticket, record only some); do what they say. Record each finding's decision in `findings.md`.

If nothing is to be fixed, go to [Finish](#6-finish).

## 4. Fix

A headless fixer makes the fixes, one per repo with findings to fix, the same way a worker works a ticket: in that repo's review worktree, kept apart the same way (its own databases, for Rails), under `settings/worker.json`. The orchestrator never writes code. Fixers in different repos can run at the same time, within `max_workers`.

For each repo with findings to fix — `<review state dir>` below is that repo's fixer folder, `epic-review-<n>-<repo>/`, and `<review folder>` is the review's own `epic-review-<n>/`:

1. Do the repo's stack's setup, per "At claim" in the stack's `environment.md`, using `review` as the ticket ID.
2. Write `prompt.md`:

   ```markdown
   Fix findings from a code review of the epic branch <epic branch>, following the "Fixing findings" section of <plugin root>/references/epic-review.md.

   - worktree: <review worktree> (your current directory), on branch <fix branch>, cut from <epic branch>.
   - state directory: <review state dir>
   - stack: <stack ID> — use the files in <plugin root>/stacks/<stack ID>/.
   - repo: <owner/repo> — the only repo you work in.
   - findings to fix: numbers <list>, in <review folder>/findings.md. Ignore the others.

   <the stack's block, per "Worker prompt" in the stack's environment.md, filled in with `review` as the ticket>

   Run until every listed finding is fixed or skipped and summary.md is written, then exit.
   ```

   Add any skipped quality tools as for a ticket's prompt (see "Worker prompt" in the orchestrate skill).
3. Start it: `<plugin root>/bin/start-worker <review worktree> <review state dir> <plugin root>`, and append `Review · fixing <n> findings · <repo>` to the review's `progress.md`.
4. Wait for it: run `<plugin root>/bin/wait-for-worker <review state dir>` with `run_in_background`. You're notified when the fixer exits. Tell the developer it's running and that `bin/agent-status` shows its progress.

If the fixer's run ends on a usage limit or crashes, resume it once with its session ID (from the run's JSON) and a `resume-prompt.md` saying it stopped before finishing and should carry on from its commits and `summary.md`. After a second failure, stop and report it with the log path.

## 5. Push

For each repo that had a fixer, read its `summary.md` and the fix branch's commits (`git -C <checkout> log --oneline origin/<epic branch>..<fix branch>`), then:

- **Gate clean, every finding fixed or skipped with a reason** — push the commits to the epic:

  ```bash
  git -C <checkout> push origin <fix branch>:<epic branch>
  ```

  Run it alone. It only fast-forwards: if the epic moved since the review started, git rejects it — report that and leave the branch for the developer. Nothing is ever force-pushed.
- **Gate not clean** — don't push. Show the developer what failed (from `summary.md`) and ask whether to push anyway or leave the branch for them to finish.

Report each finding's outcome — fixed with its commit, or skipped and why. Record skipped findings the way the developer chose for deferred ones.

## 6. Finish

1. For each repo, unless its fix branch was left for the developer: remove its review worktree (`git -C <checkout> worktree remove`, without `--force`), delete the fix branch (`git -C <checkout> branch -D <fix branch>`), and undo the stack's setup for the review per "Cleaning up" in the stack's `environment.md`.
2. Add the review to the Reviews list in `project.md`, with each repo's epic SHA after any push.
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
