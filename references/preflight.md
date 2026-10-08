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
2. **Statuses** — the project's team has Todo, In Progress, In Review, QA, Done, and Rejected. ❌ if any is missing: name it, and say it's added under team settings → Issue statuses & automations.
3. **Labels** — the team has the `agent` single-select label group with every label in `references/agent-status.md`. 🔧 Create whatever is missing, with each label's meaning as its description.
4. **GitHub automation** — PR opened → In Review, and PR merged into `epic/*` → QA. The Linear MCP can't read automation settings, so ask the developer to confirm both rules once, and record the confirmation in the project state. ❌ until confirmed.

## Git and GitHub

5. **Repo** — the current directory is the main checkout of a git repo whose `origin` is on GitHub.
6. **Epic branch** — `epic/<name>` exists on `origin`. 🔧 If it doesn't, create it from the up-to-date root branch, per `references/git.md`.
7. **Push access** — `gh auth status` succeeds, and `gh repo view --json viewerPermission` reports `WRITE`, `MAINTAIN`, or `ADMIN`. ❌ otherwise.
8. **Branch clean-up** — `gh repo view --json deleteBranchOnMerge`. ⚠️ if off: merged ticket branches will pile up on GitHub; suggest turning on "Automatically delete head branches".

## Tools

9. **Test and quality tools** — the `Gemfile` / `Gemfile.lock` include RSpec or Minitest, RuboCop, RubyCritic, and Evilution. ❌ for each one missing, giving the developer two ways forward: add the gem, or **skip that tool for this project**. A test framework can't be skipped. Record skipped tools in the project state; the orchestrator tells every worker, and workers report them as skipped in the baseline and the PR rather than silently leaving them out. Auto mode can't ask for permission to add a dependency mid-ticket, which is why this is settled up front.

## Docker

Work through "Working out the prefix" in `references/docker.md`, then:

10. **Worker prefix** — build it, with a placeholder for the ticket, and run the database check from `docker.md` using `preflight` as the ticket. It must print `<test db name>_preflight` (and the development name, for `DATABASE_URL` projects). Check every other database the app connects to as well, per `docker.md`: each must resolve to a per-worker name. ❌ if the primary database can't be separated, explaining the `database.yml` change the project needs. ⚠️ if only a secondary database can't be: the project runs with one worker.
11. **Shared services** — per "Shared services that tests write to" in `docker.md`. ⚠️ if tests write to a shared service that can't be separated per worker: the project runs with **one** active worker until it can. Say what the project needs to add.
12. **Gitignored files** — list the files to copy into each new worktree, per `docker.md`. Show the list so the developer can spot anything missing or anything that shouldn't be copied.

## Headless agent

13. **Smoke test** — start one short headless run, the way the orchestrator starts a worker, with `settings/worker.json`: ask it to read the Linear project and to run `<worker prefix> ruby -v`. ❌ if it can't reach Linear (connector not connected, or tools not allowed) or Docker (socket not reachable from the sandbox). Show the error.

## Project state

On success, save the results to `~/.bishop/<repo>/<project-slug>/project.md`:

- the epic branch
- the worker prefix template (and the development prefix, for `DATABASE_URL` projects)
- per-worker databases the orchestrator must create at claim and drop at clean-up, with the service each lives on
- quality tools skipped for this project
- the files to copy into each worktree
- the maximum active workers: the orchestrator's setting (default 2), or 1 if check 11 warned
- that the GitHub automation was confirmed, and when

Later runs reuse this file and repeat only the cheap checks (1–3, 6, 7) unless a worker fails in a way that points at the saved setup.
