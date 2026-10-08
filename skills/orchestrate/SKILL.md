---
name: orchestrate
description: Run auto mode for one Linear project — claim released tickets, start a headless agent per ticket in its own git worktree, resume agents when a developer responds in Linear, and clean up after merge. One invocation is one tick; run it on a loop. Use when the user wants to start or run the orchestrator, run auto mode, or have agents work a project's tickets.
---

# Orchestrate

The orchestrator runs auto mode for **one Linear project**. Each invocation of this skill is one **tick**: look at the project in Linear and at the workers on this machine, act on what changed, report, and stop. Run it on a loop so ticks repeat.

The orchestrator never writes code. Workers do: each is a headless `claude -p` running `ticket-workflow` in auto mode, in its own git worktree and databases. The orchestrator decides which tickets get a worker, starts and resumes workers, notices when they finish or fail, and cleans up after merge.

References:

- [`references/agent-status.md`](../../references/agent-status.md) — statuses, labels, the claim rules, and the label **swap**. Every label change here follows it.
- [`references/preflight.md`](../../references/preflight.md) — the checks run before any work starts, and the project state they produce.
- [`references/docker.md`](../../references/docker.md) — the worker prefix and per-worker databases.
- [`references/git.md`](../../references/git.md) — the epic branch, ticket branch names, and creating worktrees.

## Starting the orchestrator

From the project's main checkout, start a session with the orchestrator's settings, then loop the skill:

```bash
claude --settings <plugin root>/settings/orchestrator.json
```

```
/loop 5m /bishop:orchestrate "<Linear project name>"
```

An optional `max_workers: <n>` after the project name sets how many workers may run at once (default 2). The orchestrator never runs more than preflight allows for the project.

Keep the session open while auto mode should run. Stopping the loop stops new work; workers already running finish their current run. The orchestrator stops its own loop once the project is finished (step 7).

## State

Everything the orchestrator knows between ticks is in Linear or on disk, never in the conversation — each tick starts by reading it.

```
~/.bishop/<repo>/
  worktrees/<TICKET-ID>/            one git worktree per ticket
  <project-slug>/
    project.md                      preflight results (see references/preflight.md)
    <TICKET-ID>/
      worker.md                     branch, worktree, session ID, crash count, run count
      prompt.md                     the worker's first prompt
      run-<n>.json, run-<n>.stderr  output of each worker run
      pid                           PID of the running worker, while one runs
      baseline.md, pr-body.md, …    written by the worker itself
```

`<repo>` is the repo's name on GitHub; `<project-slug>` is the Linear project's name in lowercase snake_case.

## Each tick

Do these in order. Each step reads the state the previous step left, so a crash mid-tick is repaired by the next tick.

1. **Preflight** — if `project.md` doesn't exist, run `references/preflight.md` in full and stop this tick if anything is ❌. Otherwise repeat only its cheap checks.
2. **Reap** — find workers that have stopped since the last tick, and work out why.
3. **Clean up** — for tickets that reached QA or Done.
4. **Resume** — tickets a developer has responded to.
5. **Claim** — new claimable tickets, while worker slots are free.
6. **Report** — one short summary.
7. **Finish** — stop the loop if the project has nothing left to do.

Steps 4 and 5 share the worker slots: resumes go first, so work already underway finishes before new work starts. A slot is a **running** worker — a ticket parked on a 🔴 label holds no slot.

## Starting a worker

Always through the launcher, so the command stays simple and every run is recorded the same way:

```bash
<plugin root>/bin/start-worker <worktree> <ticket state dir> <plugin root> [<session ID>]
```

- Without a session ID it starts a new worker from `<ticket state dir>/prompt.md`.
- With one, it resumes that session from `<ticket state dir>/resume-prompt.md`.

It starts the worker in the background with `settings/worker.json`, writes its PID to `pid`, sends its output to the next `run-<n>.json` / `run-<n>.stderr`, and returns at once. The worker's session ID is read from that run's JSON once it ends (step 2).

## Step 2 — Reap

For every ticket folder with a `pid` file, check the process with `kill -0 <pid>`. Still alive: it's running and holds a slot; leave it. Gone: the run has ended — delete `pid`, read the newest `run-<n>.json` (record its `session_id` in `worker.md` if it's the session's first run), read the ticket's current label, and decide which of these happened:

- **Usage limit** — the run ended in error and its `result` or stderr mentions a usage or rate limit. Not the worker's fault: don't count it as a crash. Pause the project (see [Usage limits](#usage-limits)) and mark the ticket in `worker.md` to resume once the pause ends.
- **Parked** — the label is `agent:awaiting-approval`, `agent:needs-input`, or `agent:gate-failed`. The worker stopped on purpose; nothing to do until the developer responds.
- **Finished** — the label is `agent:pr-open`. Post the token-usage comment (see [Comments](#comments)) and mark the ticket finished in `worker.md`.
- **Crashed** — anything else: the label is still `agent:planning` or `agent:working`, or the run JSON is empty or ends in an error. Add one to the crash count in `worker.md`. After the first crash, mark the ticket to resume. After the second, post the error comment and swap the label to `agent:error`; the developer takes it from there.

## Step 3 — Clean up

For each ticket that has a `worker.md` not yet marked cleaned up, and whose Linear status is now QA, Done, or Canceled:

1. If a worker is still running (only possible for Canceled), stop it: `kill <pid>`.
2. Remove the worktree: `git worktree remove <worktree>`. Without `--force`: if git refuses because of uncommitted changes, leave the worktree, report it, and carry on with the rest.
3. Delete the local ticket branch: `git branch -D <ticket branch>`.
4. Drop the worker's databases, per "Cleaning up" in `references/docker.md`.
5. Remove the ticket's `agent:*` label (`removeLabels` only — there's nothing to swap to).
6. Mark `worker.md` cleaned up. Keep the ticket folder: its run logs are the record of what happened.

A ticket cleaned up after QA can come back as Rejected and be claimed again; that claim starts a new worktree, branch, and session, and the run numbering carries on.

## Step 4 — Resume

Skip this step while the project is paused. A ticket needs resuming when its label is `agent:plan-approved` or `agent:answered` (the developer has responded), or when step 2 marked it after a crash or a usage limit. For each, while a slot is free:

1. Write `resume-prompt.md` for the reason:
   - **Developer responded**: `<TICKET-ID>'s label is now <label>. Resume in auto mode per the ticket-workflow skill's "Resuming in auto mode" section: read every comment posted since your last parking comment, apply them, and continue.`
   - **After a crash or usage limit**: `Your previous run stopped before finishing (<reason>). Resume in auto mode where you left off: check the branch's commits and your comments on the ticket for what's already done, then continue.`
2. Start the worker with its session ID.

If the session can't be resumed (the run ends at once with an error saying the conversation wasn't found), start a fresh worker from `prompt.md` instead, with this line added at the top: `You are resuming work on this ticket in a fresh session: rebuild your context first, per the skill's "Resuming in auto mode" section.`

## Step 5 — Claim

Skip this step while the project is paused or no slot is free.

1. List the project's issues once, with status, labels, priority, and relations. Find the claimable tickets per the rules in `references/agent-status.md`. A blocker in another project isn't in the listing: fetch it individually.
2. Take them in order: priority (Urgent first, no priority last); at equal priority, Rejected before Todo; then oldest first.
3. For each, while a slot is free:
   1. **Claim it** — one `save_issue` call that sets the status to In Progress and swaps `agent:claimable` for `agent:planning`. If the swap fails, someone changed the ticket in the meantime: skip it this tick.
   2. **Name the branch** per `references/git.md`, summarising the ticket's title. For a Rejected ticket, use the `_feedback_` form, summarising what the developer's rejection comments ask for.
   3. **Create the worktree** from the epic branch, per the auto mode section of `references/git.md`, and copy in the files listed in `project.md`. Create any per-worker databases `project.md` lists for the orchestrator to create (see `references/docker.md`).
   4. **Write `worker.md` and `prompt.md`**, from the template below.
   5. **Start the worker.**

### Worker prompt

```markdown
Use the bishop:ticket-workflow skill in auto mode to work Linear ticket <TICKET-ID>.

- mode: auto
- ticket: <TICKET-ID>, in the Linear project "<project>". The orchestrator has claimed it: status In Progress, label agent:planning.
- worktree: <worktree> (your current directory), on branch <ticket branch>, cut from <epic branch>.
- epic branch: <epic branch>
- state directory: <ticket state dir>

Docker: put this prefix in front of every Ruby/Rails command — tests, RuboCop, RubyCritic, Evilution, rails. Never use `docker compose exec`, or the Docker commands in the ticket's notes or the project's own docs: those run the developer's checkout, not this worktree.

<test prefix>

Run until you park the ticket or open the PR, then exit.
```

For a `DATABASE_URL` project, add the development prefix after the test prefix, introduced as: `Development database — only for db:prepare and migrations, never for tests:`. If `project.md` lists skipped quality tools, add: `Skipped for this project by the developer: <tools>. Don't run them; report them as skipped in the baseline and the PR.` For a Rejected ticket, add to the ticket line: `This is rework after QA: the developer's comments since the last merge are the scope.`

## Step 6 — Report

End the tick with one short summary: each ticket the orchestrator is tracking with its current state, then `running <n>/<max>`, how many tickets wait on a developer (🔴), and the pause end time if paused. Mention anything the tick couldn't do (a worktree git refused to remove, a ❌ preflight check).

## Step 7 — Finish

The project is **finished** when all of these hold after this tick:

- every issue in the project is in QA, Done, or Canceled — none left for the developer to release;
- no worker is running (no `pid` files);
- every `worker.md` is marked cleaned up.

Then end auto mode for the project: cancel the loop that runs this skill, and end the report with `Project finished — loop stopped.` For a fixed-interval loop, find its job with `CronList` (the one whose prompt is this skill for this project) and delete it with `CronDelete`; for a self-paced loop, stop it rather than scheduling another wakeup. Don't ask first — finishing is the expected end of the run.

If a clean-up step failed (a worktree git refused to remove), the project isn't finished: the loop keeps running so the next tick retries, and the report keeps saying what's stuck.

A ticket in QA that comes back as Rejected after this needs the orchestrator started again.

## Usage limits

Every worker runs under the developer's Claude account, so running out of usage stops all of them, not just one. When a run ends on a usage or rate limit:

- record a pause in `project.md` until the reset time given in the error, or 30 minutes from now if none is given;
- while paused, ticks still reap, clean up, and report, but don't resume or claim;
- after the pause, resume the affected tickets first (step 4), then claim as normal.

## Comments

Both comments follow the agent comment style in `references/escalation.md`.

**Error** — posted with the swap to `agent:error`:

```markdown
**🤖 Agent — Error**

The agent stopped unexpectedly twice on this ticket and won't retry again.

**Last run** — <what the run ended with: the error, or the last lines of stderr>

**Branch** — `<ticket branch>`, in the worktree at `<worktree>`. Logs: `<ticket state dir>`.

Fix what's needed (on the branch, or by commenting), then swap to `agent:answered` to resume.
```

**Token usage** — posted when a ticket finishes (`agent:pr-open`). A resumed session's run JSON reports **cumulative** usage for the whole session, so the session's totals are its last run's figures, and each run's own share is the difference from the run before it.

```markdown
**🤖 Agent — Token usage**

| Run | Stage | Output tokens | API list-price equivalent |
|---|---|---|---|
| <n> | <what the run did: plan, implementation, …> | <tokens> | $<cost> |
| **Total** | | **<tokens>** | **$<cost>** |

Model: <model>. Totals also include <n> cache-read tokens, <n> cache-write tokens and <n> uncached input tokens. The cost is an API list-price equivalent, not a bill: runs under a Claude plan count towards its usage limits instead.
```
