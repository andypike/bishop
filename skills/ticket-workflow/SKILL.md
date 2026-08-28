---
name: ticket-workflow
description: End-to-end Rails ticket workflow — read a Linear ticket, investigate the codebase, clarify the approach with the user before writing code, implement in small reviewed TDD batches, then run a quality gate (tests, RuboCop, RubyCritic, mutation testing, style guide, code review) and a correctness-vs-ticket check before calling it done. Use when the user gives a Linear ticket reference (e.g. "let's work on ENG-1234", "pick up ENG-1234") or asks to start/implement a ticket.
---

# Ticket Workflow

A staged workflow for taking a Linear ticket from "assigned" to "implemented, verified, and documented." It intentionally pauses at several gates — this is not meant to run unattended. Follow the phases in order; don't skip ahead.

Two reference files this workflow depends on, kept in this plugin so they're consistent across every project:

- [`style-guide/rails-style-guide.md`](../../style-guide/rails-style-guide.md) — what good code looks like here. Applies in Phase 5 (implementation) and Phase 6 (quality gate).
- [`references/quality-gates.md`](../../references/quality-gates.md) — exact commands, baseline mechanics, and how each tool is interpreted. Read this before running any check.
- [`references/docker.md`](../../references/docker.md) — every project runs inside Docker Compose; this covers detecting the compose setup and how to wrap every command. Read this before running anything at all, including the baseline capture.
- [`references/git.md`](../../references/git.md) — branch naming and per-slice commit conventions. Read this before Phase 5 — nothing gets written until the branch is settled.

## Phase 1 — Ticket intake

Fetch the ticket via whatever Linear MCP tools are available in this session (search/get issue by identifier). Pull title, description, acceptance criteria, and existing comments. If the ticket reference is ambiguous or not found, ask rather than guessing which ticket was meant.

## Phase 2 — Investigation

Read-only exploration of the target codebase:

- Find the files, models, controllers, and existing tests relevant to the ticket.
- Identify existing patterns worth reusing (don't propose new abstractions where a suitable one already exists).
- Note which parts of the style guide are most relevant to this change.
- **Tool detection**: check whether RSpec/Minitest, RuboCop, RubyCritic, and Evilution are configured (see `quality-gates.md`). If something's missing, flag it and ask before adding it as a dev dependency.
- **Docker detection**: find the compose file, confirm `docker compose` vs `docker-compose`, and identify the app service (see `docker.md`). Every command from here on — baseline capture included — runs through this, not on the host.

**As soon as investigation is far enough along to know what to run, kick off baseline metric capture in the background** (full test suite + coverage, RuboCop, RubyCritic — commands in `quality-gates.md`). These can be slow; don't block the conversation on them. Mutation testing is *not* run here — there's no diff yet to mutate against.

## Phase 3 — Clarification Q&A

Work through logic gaps, technical architecture, and order of operations with the user until both of you are confident in the approach. Ask short, specific questions — don't dump a wall of questions at once. Cover:

- Ambiguous or missing requirements in the ticket.
- Architectural choices (where new code lives, what patterns to follow).
- Order of operations / sequencing, if the ticket has multiple moving parts.

Keep a running **decision log**: a short bullet list of what was decided and why, including any explicit scope calls ("X is out of scope for this ticket").

**Gate**: don't move to Phase 4 until the user explicitly confirms the plan. Baseline metrics keep running in the background during this phase.

## Phase 4 — Post decisions to Linear

Post the decision log as a comment on the ticket, so the ticket becomes the full record of what was decided, not just what was originally asked for.

Collect the baseline results (should be done or close to it by now) for comparison in Phase 6.

## Phase 5 — TDD implementation, small batches

**Before anything else in this phase** — not even a test file — settle the branch per `references/git.md`: check the current branch matches `<TICKET-ID>_*`; if not, gate on whether to create it now (off an up-to-date root branch).

This is the core loop, and it must stay small-batch — **never write the whole test suite up front**. For each slice:

1. Pick the smallest next slice of behavior (one method, one branch, one scenario — not "the whole feature").
2. Write failing test(s) for *only* that slice, following the Testing section of the style guide.
3. **Gate**: present the test(s) to the user for review before implementing anything. Wait for approval or feedback.
4. Implement the minimal code to make those tests pass — simplest correct implementation, not the final polished version.
5. **Gate**: present the implementation for review.
6. **Gate**: ask whether to commit this slice. If approved, re-check the branch (per `git.md`) and commit with a short, specific message.
7. Repeat from step 1 until the ticket's behavior is covered.

If the user's review feedback implies a style guide gap (something they correct that isn't written down), suggest adding it to `style-guide/rails-style-guide.md` — that's how review burden goes down over time.

Only after this loop is quality-gate work appropriate — don't run RuboCop, RubyCritic, or mutation testing mid-loop; they're a Phase 6 concern.

## Phase 6 — Quality gate

Follow `references/quality-gates.md` exactly for commands and interpretation. In summary:

- Full test suite (must be green).
- RuboCop: auto-fix safe offenses (`-a`, never `-A`), report what's left. Offense count must not exceed baseline.
- RubyCritic: score must not regress vs baseline.
- Evilution: mutation testing scoped to just the changed files/lines. No baseline comparison (nothing to mutate before the change existed) — judge survivors on their own merits.
- Invoke the `code-review-runner` agent (via the Agent tool) against the diff for reuse/simplification/efficiency findings — runs the `code-review` skill on Opus at high effort, rather than calling the skill directly in the main session.
- Style guide checklist: walk the diff against `style-guide/rails-style-guide.md`.

**Gate**: report baseline-vs-after plus all findings to the user. If anything needs fixing, loop back into Phase 5 for that fix (small batch, reviewed), then re-run the affected checks — don't re-run everything from scratch unless the fix was broad.

## Phase 7 — Correctness check

Invoke the `correctness-checker` agent (via the Agent tool) once the quality gate is clean. Give it, in the prompt:

- The full ticket (title, description, acceptance criteria, comments).
- The decision log from Phase 3.
- The diff (or list of changed files + base ref) for this ticket.

**Gate**: present its report to the user. If it finds gaps, loop back into Phase 5.

## Phase 8 — Final Linear update

Post a final comment on the ticket summarizing:

- What was implemented.
- Quality metrics before/after (tests, RuboCop, RubyCritic, mutation score).
- The correctness check's verdict.

Branching and per-slice commits happened in Phase 5; pushing and opening the PR remain manual, left to the user.
