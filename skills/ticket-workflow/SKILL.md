---
name: ticket-workflow
description: End-to-end Rails ticket workflow — read a Linear ticket, investigate the codebase, clarify the approach with the user before writing code, implement in small reviewed TDD batches, then run a quality gate (tests, RuboCop, RubyCritic, mutation testing, style guide, code review) and a correctness-vs-ticket check before calling it done. Use when the user gives a Linear ticket reference (e.g. "let's work on ENG-1234", "pick up ENG-1234") or asks to start/implement a ticket.
---

# Ticket Workflow

A staged workflow for taking a Linear ticket from "assigned" to "implemented, verified, and documented." In interactive mode it pauses at several gates for the developer; in auto mode it runs unattended and stops only where `references/escalation.md` says to (see [Modes](#modes)). Follow the phases in order; don't skip ahead.

Two reference files this workflow depends on, kept in this plugin so they're consistent across every project:

- [`style-guide/rails-style-guide.md`](../../style-guide/rails-style-guide.md) — what good code looks like here. Applies in Phase 5 (implementation) and Phase 6 (quality gate).
- [`references/quality-gates.md`](../../references/quality-gates.md) — exact commands, baseline mechanics, and how each tool is interpreted. Read this before running any check.
- [`references/docker.md`](../../references/docker.md) — every project runs inside Docker Compose; this covers detecting the compose setup and how to wrap every command. Read this before running anything at all, including the baseline capture.
- [`references/git.md`](../../references/git.md) — epic and ticket branches, per-slice commits, pushing, and opening the PR. Read this before Phase 5 — nothing gets written until the branch is settled.

## Modes

- **Interactive** (default) — a developer is in the session, and every gate below pauses for them.
- **Auto** — started headless by the orchestrator, which passes `mode: auto`, the ticket ID, the worktree path (already on the ticket branch, cut from the epic), and a **state directory** for files that must outlive this run. Nobody is in the session to answer, so each gate becomes either a logged assumption or **parking** the ticket. Read [`references/agent-status.md`](../../references/agent-status.md) and [`references/escalation.md`](../../references/escalation.md) before Phase 1. Each phase below says what changes under **Auto mode**; where it says nothing, the phase runs as written.

### Resuming in auto mode

The orchestrator resumes a parked worker once its label is `agent:plan-approved` or `agent:answered`. Read every comment since your most recent agent parking comment — they are the developer's binding response — then continue from where you parked. If you start without your earlier context (a fresh session rather than a resumed one), rebuild it first from the ticket's agent comments (plan, decisions, assumptions), the branch's commits, and the state directory.

## Phase 1 — Ticket intake

Fetch the ticket via whatever Linear MCP tools are available in this session (search/get issue by identifier). Pull title, description, acceptance criteria, **status**, and existing comments. If the ticket reference is ambiguous or not found, ask rather than guessing which ticket was meant.

If the ticket links to a feature document (tickets created by the `feature-planning` skill do), read it too — it holds the wider feature context and cross-ticket decisions. Treat it as background: this ticket's own description, acceptance criteria, and comments define the scope.

**Check the status before going further.** A status of **Rejected** means the ticket was already implemented once and then failed QA or client review — it's a rework, not a fresh build:

- Read the comments for the rejection reasons. There may be several rounds if the ticket has been rejected more than once; treat every still-outstanding reason as in scope, not just the most recent one.
- Rejection feedback can legitimately change the original scope — new or revised requirements, not only bug fixes. Where feedback and the original description conflict, the feedback wins; note that explicitly in the Phase 3 decision log.
- Work out what's already built versus what the rejections ask for. The job from here is that delta, not a re-implementation of the whole ticket.
- The original work has most likely already been merged into a feature or root branch (that's how someone came to be testing it), so the rework gets a **new** branch — `<TICKET-ID>_feedback_<summary>`, never the original ticket branch. See `references/git.md`.

Carry the rejection reasons forward: they're part of what Phase 7 checks correctness against, and Phase 8 should record which rejections were addressed.

For any other status, continue with the phases below as written.

**Auto mode:** the ticket ID comes from the orchestrator, so there's no ambiguity to ask about; if the ticket can't be fetched, stop and report the error — the orchestrator handles it. For a Rejected ticket, the rejection reasons are the comments the developer added before marking it `agent:claimable`, and the orchestrator has already put the worktree on the `_feedback_` branch.

## Phase 2 — Investigation

Read-only exploration of the target codebase:

- Find the files, models, controllers, and existing tests relevant to the ticket.
- Identify existing patterns worth reusing (don't propose new abstractions where a suitable one already exists).
- Note which parts of the style guide are most relevant to this change.
- **Tool detection**: check whether RSpec/Minitest, RuboCop, RubyCritic, and Evilution are configured (see `quality-gates.md`). If something's missing, flag it and ask before adding it as a dev dependency.
- **Docker detection**: find the compose file, confirm `docker compose` vs `docker-compose`, and identify the app service (see `docker.md`). Every command from here on — baseline capture included — runs through this, not on the host.

**As soon as investigation is far enough along to know what to run, kick off baseline metric capture in the background** (full test suite + coverage, RuboCop, RubyCritic — commands in `quality-gates.md`). These can be slow; don't block the conversation on them. Mutation testing is *not* run here — there's no diff yet to mutate against.

**Auto mode:**

- Run every command through the worker setup in `references/docker.md` — the worker's own app container and databases, never the shared service via `exec`.
- Preflight guarantees the quality tools are installed, except any your prompt says the developer skipped for this project: leave those out and report them as skipped in the baseline and the PR. If another tool is missing anyway, park with `agent:needs-input` rather than adding it.
- The worker exits when it parks at the plan gate, so the baseline must outlive this run: let it finish before parking, and write its results to `<state dir>/baseline.md`. Run it in the foreground, per "Knowing a run has finished" in `references/quality-gates.md`.

## Phase 3 — Clarification Q&A

Work through logic gaps, technical architecture, and order of operations with the user until both of you are confident in the approach. Ask short, specific questions — don't dump a wall of questions at once. Cover:

- Ambiguous or missing requirements in the ticket.
- Architectural choices (where new code lives, what patterns to follow).
- Order of operations / sequencing, if the ticket has multiple moving parts.

Keep a running **decision log**: a short bullet list of what was decided and why, including any explicit scope calls ("X is out of scope for this ticket").

**Gate**: don't move to Phase 4 until the user explicitly confirms the plan. Baseline metrics keep running in the background during this phase.

**Auto mode:** there's no Q&A. Draft the plan from the investigation: put every question you would have asked under **Questions**, each with options and a recommendation, and every judgement call under **Assumptions**. Once the baseline is saved, park with the plan-for-approval comment from `references/escalation.md` and `agent:awaiting-approval`. The gate clears when the developer swaps the label to `agent:plan-approved`.

## Phase 4 — Post decisions to Linear

Post the decision log as a comment on the ticket, so the ticket becomes the full record of what was decided, not just what was originally asked for.

Collect the baseline results (should be done or close to it by now) for comparison in Phase 6.

**Auto mode:** the plan comment already carries the decision log. On resume:

- **`agent:plan-approved`** — apply any amending comments to the decision log. If they changed anything, post a `**🤖 Agent — Final plan**` comment listing just the changes. Load the baseline from `<state dir>/baseline.md`, swap to `agent:working`, and continue to Phase 5.
- **`agent:answered`** — the developer wants a revised plan: revise it, post a new plan-for-approval comment, and park again.

## Phase 5 — TDD implementation, small batches

**Before anything else in this phase** — not even a test file — settle the branch per `references/git.md`: check the current branch matches `<TICKET-ID>_*` (or `<TICKET-ID>_feedback_*` for a rejected ticket); if not, gate on whether to create it now (off an up-to-date root branch).

This is the core loop, and it must stay small-batch — **never write the whole test suite up front**. For each slice:

1. Pick the smallest next slice of behavior (one method, one branch, one scenario — not "the whole feature").
2. Write failing test(s) for *only* that slice, following the Testing section of the style guide.
3. **Gate**: present the test(s) to the user for review before implementing anything. Wait for approval or feedback.
4. Implement the minimal code to make those tests pass — simplest correct implementation, not the final polished version. Follow the style guide at `style-guide/rails-style-guide.md`
5. **Gate**: present the implementation for review.
6. **Gate**: ask whether to commit this slice. If approved, re-check the branch (per `git.md`) and commit with a short, specific message.
7. Repeat from step 1 until the ticket's behavior is covered.

If the user's review feedback implies a style guide gap (something they correct that isn't written down), suggest adding it to `style-guide/rails-style-guide.md` — that's how review burden goes down over time.

Only after this loop is quality-gate work appropriate — don't run RuboCop, RubyCritic, or mutation testing mid-loop; they're a Phase 6 concern.

**Auto mode:**

- **Branch**: the orchestrator created the worktree on the ticket branch, so only verify it — `git branch --show-current` matches the expected name. If it doesn't, park with `agent:needs-input`; never create or switch branches yourself.
- **Slices** come from the approved plan, in order. Each slice runs steps 1, 2, 4 and 6 without the gates: write the failing test and watch it go red, implement until it's green, then commit (re-check the branch, stage only this slice's files).
- **Escalation**: check every slice against the triggers in `references/escalation.md`, and post the slice's assumptions before moving on.

## Phase 6 — Quality gate

Follow `references/quality-gates.md` exactly for commands and interpretation. In summary:

- Full test suite (must be green).
- RuboCop: auto-fix safe offenses (`-a`, never `-A`), report what's left. Offense count must not exceed baseline.
- RubyCritic: score must not regress vs baseline.
- Evilution: mutation testing scoped to just the changed files/lines. No baseline comparison (nothing to mutate before the change existed) — judge survivors on their own merits.
- Invoke the `code-review-runner` agent (via the Agent tool) against the diff for reuse/simplification/efficiency findings — runs the `code-review` skill on Opus at high effort, rather than calling the skill directly in the main session.
- Style guide checklist: walk the diff against `style-guide/rails-style-guide.md`.

**Gate**: report baseline-vs-after plus all findings to the user. If anything needs fixing, loop back into Phase 5 for that fix (small batch, reviewed), then re-run the affected checks — don't re-run everything from scratch unless the fix was broad.

**Auto mode:** the gate is a hard stop, with no developer to decide which findings matter:

- **Code review findings**: verify each against the real source before acting. Fix the real ones; record inaccurate ones as rejected, with what you checked. A finding whose fix would change the approved plan is an escalation trigger, not a fix.
- **Evilution survivors**: kill each meaningful survivor with a test; record equivalent mutants as such.
- The gate is **clean** when the suite is green, RuboCop and RubyCritic haven't regressed against baseline, and every valid finding and meaningful survivor is resolved.
- If it isn't clean, fix in Phase 5 style (test first where behaviour changes, commit), then re-run the affected checks. That's one retry. After **two** retries, if the gate still isn't clean, park with `agent:gate-failed` (see `references/escalation.md`).
- Keep every finding's outcome (fixed, added, rejected, already-approved) for Phase 8.

## Phase 7 — Correctness check

Invoke the `correctness-checker` agent (via the Agent tool) once the quality gate is clean. Give it, in the prompt:

- The full ticket (title, description, acceptance criteria, comments).
- The decision log from Phase 3.
- The diff (or list of changed files + base ref) for this ticket.

**Gate**: present its report to the user. If it finds gaps, loop back into Phase 5.

**Auto mode:** if it finds gaps, close them in Phase 5 style, re-run the affected Phase 6 checks, and run the correctness check again. If gaps remain after that one fix attempt, park with `agent:needs-input`, quoting the report.

## Phase 8 — Final Linear update

Post a final comment on the ticket — this is the permanent record of what shipped and what it took to get there, not just a "done" notice. Include:

- **What was implemented.** Brief.
- **Quality metrics before/after**: tests (example count, pass/fail, coverage), RuboCop, RubyCritic, mutation score. If Phase 6 ran more than once (a fix loop), report the final numbers, not the first pass.
- **Code review findings**, grouped by outcome, not just "see above" — the review is often where the real bugs surface, and that's easy to lose if it's not written down:
  - Fixed (what was wrong, in one line each).
  - Added — decisions made *during* review that expanded scope (e.g. a missing action the review exposed as necessary).
  - Rejected — findings checked and found inaccurate, with what was actually verified (a hallucinated claim caught by reading the real source is worth recording so the pattern is visible later).
  - Already-approved — anything the review flagged that was in fact a decision made earlier in the ticket; note this so the record doesn't look like a contradiction.
- **The correctness check's verdict** — including a second pass if the first one found gaps. A correctness check that finds nothing is worth stating explicitly ("no gaps found"), not omitting.

Then **gate**: ask whether to push the branch and open the PR. If approved, follow the push and PR steps in `references/git.md`; otherwise both stay with the user.

**Auto mode:**

1. Push the branch and open the PR against the epic branch, per `references/git.md`. The PR body carries the same record as the final comment, plus every assumption from the ticket.
2. Post the final comment under a `**🤖 Agent — Complete**` heading, with the PR link at the top.
3. Swap the label to `agent:pr-open` and exit. Linear moves the ticket to In Review when the PR opens; the orchestrator posts token usage after this run ends.
