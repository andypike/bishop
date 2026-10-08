# Escalation in Auto Mode

In auto mode a worker runs without a developer watching. It stops for a developer in exactly four places — the plan gate, an escalation trigger, a failed quality gate, and the finished PR — and otherwise keeps going, recording its judgement calls as assumptions on the ticket. Stopping always means **parking** the ticket (see `references/agent-status.md`): comment, swap the label, exit.

This file decides when to stop and ask. A target project's `CLAUDE.md` still governs code style and commands, but where it asks for a different interaction style ("ask before every assumption", "show a plan and wait"), the plan gate and these rules take its place.

## Assumptions

An **assumption** is a decision the worker made that a reviewer could reasonably have made differently: a naming choice with no precedent, an edge case the ticket is silent on, a default value. Choices the style guide, the approved plan, or an existing codebase pattern already settle are not assumptions — just follow them.

Post assumptions to the ticket as they're made, grouping those from the same slice into one comment:

```markdown
**🤖 Agent — Assumptions** (slice: <what this slice does>)

- <decision> — <why; what it's based on>
```

The final PR body repeats them all, so the reviewer sees every assumption in one place.

## Escalation triggers

The approved plan is the contract. A trigger is a **surprise** — something the plan didn't settle that a developer should decide. After the plan is approved, park with `agent:needs-input` when any of these fire:

1. **Requirements gap** — the acceptance criteria turn out to be missing, ambiguous, or contradictory for the case at hand.
2. **Design fork** — two or more viable designs with real trade-offs, and the plan didn't choose between them.
3. **Uncharted decision** — a design decision that neither the style guide, the plan, nor an existing codebase pattern covers, and that a reviewer would likely question if made silently.
4. **Sensitive change not in the plan** — a migration, data deletion, auth or permissions change, payments change, or public API change.
5. **Scope drift** — the work needs changes to files or areas well outside those the plan named.
6. **Plan change** — anything else that would change what the approved plan says will be built.

Two more stops come from the quality checks rather than from judgement:

7. **Quality gate still failing** — after two retries, any Phase 6 check still fails or regresses against baseline. Park with `agent:gate-failed`.
8. **Correctness gaps remain** — the correctness check still reports gaps after one fix attempt. Park with `agent:needs-input`, quoting the report.

## Before parking

Once implementation has started, leave the branch in a state the developer can pick up:

1. Commit any work in progress on the ticket branch: `<TICKET-ID>: WIP — parked: <trigger>`.
2. Push the ticket branch, so the developer can inspect it or fix it themselves before swapping to `agent:answered`.

## Parking comments

Every parking comment opens with a `**🤖 Agent — …**` heading. On resume, the worker finds its most recent agent parking comment and reads every comment after it: those are the developer's response, and they're binding.

### Plan for approval → `agent:awaiting-approval`

```markdown
**🤖 Agent — Plan for approval**

**Approach** — <how the ticket will be implemented, in a few sentences>

**Slices** — <the ordered TDD slices>

**Decisions** — <decision log: what was decided and why, including scope calls>

**Assumptions** — <decisions the ticket doesn't settle, as above>

**Questions** — <each open question with options and a recommendation; "None" if none>

Swap to `agent:plan-approved` to approve (comments alongside are treated as amendments), or comment and swap to `agent:answered` for a revised plan.
```

### Escalation → `agent:needs-input`

```markdown
**🤖 Agent — Needs input** (trigger: <trigger name>)

**What I found** — <the surprise, with file references>

**Options** — <2–3 options, each with its trade-off>

**Recommendation** — <the option I'd take and why>

**Branch** — `<branch>` at `<short SHA>`, pushed.

Comment with your decision, then swap to `agent:answered`.
```

### Quality gate failed → `agent:gate-failed`

```markdown
**🤖 Agent — Quality gate failed**

**Check** — <which check, baseline vs now>

**Attempts** — <what each of the two retries changed, and the result>

**Remaining failure** — <the relevant output, trimmed to the essentials>

**Suggested next step** — <what I think would fix it>

**Branch** — `<branch>` at `<short SHA>`, pushed.

Comment with guidance or push a fix to the branch, then swap to `agent:answered`.
```

The orchestrator posts the `agent:error` comment for crashed workers; its format lives with the orchestrator skill.
