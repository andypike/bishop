# Preflight

The orchestrator runs preflight before it starts any work on a project, and again whenever a saved result looks stale (a check fails mid-run, or the project's Docker setup changed). It runs from the project's main checkout, for one Linear project.

Every check ends in one of four outcomes:

- ✅ **pass**
- 🔧 **fixed** — preflight made the change itself (only where noted)
- ⚠️ **warning** — work can start, with a limitation stated
- ❌ **blocked** — work can't start; report what's missing and exactly how to fix it

Run every check, then report them all together, so the developer can fix everything in one pass rather than discovering problems one at a time. If anything is ❌, stop there: no claiming, no workers.

## Linear

1. **Project** — the named Linear project exists. Its feature document has an `Epic branch: epic/<name>` line (see `references/ticket-template.md`). ❌ if either is missing: the project needs planning with `feature-planning`.

   It also has a `Stacks:` line (see `references/stack-selection.md`). If it doesn't — a project planned before stacks existed — detect this repo's stack per that file, announce it, and 🔧 add the line under `Epic branch:`, with this checkout's GitHub repo. ❌ if a stack it names has no folder in `stacks/`, or if any stack's repo isn't this checkout's `origin`: every stack must live in this repo.
2. **Architecture** — the project has an architecture document (see `references/architecture.md`), linked from the feature document, with every section filled in and no placeholder ticket identifiers left in "Introduced by". ❌ if it's missing or incomplete: workers running in parallel need the shared design to build against. The fix is `feature-planning`'s "Adding architecture to an existing project".
3. **Statuses** — the project's team has Todo, In Progress, In Review, QA, Done, and Rejected. ❌ if any is missing: name it, and say it's added under team settings → Issue statuses & automations.
4. **Labels** — the team has the `agent` single-select label group with every label in `references/agent-status.md`, and the `stack` single-select group with a `stack:<id>` label for each stack in the `Stacks:` line (see `references/stack-selection.md`). 🔧 Create whatever is missing, with each label's meaning, or its stack's name, as its description.
5. **GitHub automation** — PR opened → In Review, and PR merged into `epic/*` → QA. The Linear MCP can't read automation settings, so ask the developer to confirm both rules once, and record the confirmation in the project state. ❌ until confirmed.
6. **Claimable tickets with open gaps** — any ticket labelled `agent:claimable` whose description still has a **Gaps** section with unanswered items. ⚠️ for each, naming the ticket: it will be claimed, but its worker will almost certainly park at the plan gate with the same questions. Answer the gaps in the ticket, or remove the label until they are.

   Also ⚠️ for each claimable ticket without a `stack:*` label when the `Stacks:` line names more than one stack: it won't be claimed until it has one.

## Git and GitHub

7. **Repo** — the current directory is the main checkout of a git repo whose `origin` is on GitHub.
8. **Epic branch** — `epic/<name>` exists on `origin`. 🔧 If it doesn't, create it from the up-to-date root branch, per `references/git.md`.
9. **Push access** — `gh auth status` succeeds, and `gh repo view --json viewerPermission` reports `WRITE`, `MAINTAIN`, or `ADMIN`. ❌ otherwise.
10. **Branch clean-up** — `gh repo view --json deleteBranchOnMerge`. ⚠️ if off: merged ticket branches will pile up on GitHub; suggest turning on "Automatically delete head branches".

## Tools

Checks 11–14 run for each stack in the `Stacks:` line, against that stack's `quality-gates.md` and `environment.md`.

11. **Test and quality tools** — the `Gemfile` / `Gemfile.lock` include RSpec or Minitest, RuboCop, RubyCritic, and Evilution. ❌ for each one missing, giving the developer two ways forward: add the gem, or **skip that tool for this project**. A test framework can't be skipped. Record skipped tools in the project state; the orchestrator tells every worker, and workers report them as skipped in the baseline and the PR rather than silently leaving them out. Auto mode can't ask for permission to add a dependency mid-ticket, which is why this is settled up front.

## Docker

Work through "Working out the prefix" in the stack's `environment.md`, then:

12. **Worker prefix** — build it, with a placeholder for the ticket, and run the database check from the stack's `environment.md` using `preflight` as the ticket. It must print `<test db name>_preflight` (and the development name, for `DATABASE_URL` projects). Check every other database the app connects to as well, per the stack's `environment.md`: each must resolve to a per-worker name. ❌ if the primary database can't be separated, explaining the `database.yml` change the project needs. ⚠️ if only a secondary database can't be: the project runs with one worker.
13. **Shared services** — per "Shared services that tests write to" in the stack's `environment.md`. ⚠️ if tests write to a shared service that can't be separated per worker: the project runs with **one** active worker until it can. Say what the project needs to add.
14. **Gitignored files** — list the files to copy into each new worktree, per the stack's `environment.md`. Show the list so the developer can spot anything missing or anything that shouldn't be copied.

## Headless agent

15. **Smoke test** — start one short headless run, the way the orchestrator starts a worker, with `settings/worker.json`: ask it to read the Linear project and to run `<worker prefix> ruby -v`. ❌ if it can't reach Linear (connector not connected, or tools not allowed) or Docker (socket not reachable from the sandbox). Show the error.

## Project state

On success, save the results to `~/.bishop/<repo>/<project-slug>/project.md`:

- the epic branch
- the project's stacks, from the `Stacks:` line; the results below are recorded per stack
- the worker prefix template (and the development prefix, for `DATABASE_URL` projects)
- per-worker databases the orchestrator must create at claim and drop at clean-up, with the service each lives on
- the mutation prefix, the per-job database command and the job count (or `--jobs 1`), per "Mutation testing" in the stack's `environment.md`
- quality tools skipped for this project
- the files to copy into each worktree
- the maximum active workers: the orchestrator's setting (default 2), or 1 if check 13 warned
- that the GitHub automation was confirmed, and when

Later runs reuse this file and repeat only the cheap checks (1–4, 6, 8, 9) unless a worker fails in a way that points at the saved setup.
