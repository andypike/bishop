# Ticket Template

The structure `feature-planning` uses for each ticket it creates and for the feature document. Tickets are written to be picked up by `ticket-workflow`, so they're shaped around what that workflow reads in Phase 1 and checks against in Phase 7 (correctness check).

## What makes a good ticket

- **A vertical slice.** Each ticket delivers a thin end-to-end piece of behaviour — whatever schema, model, controller, view, and tests that behaviour needs — rather than one technical layer. Someone should be able to demo or QA it on its own.
- **A single task.** One branch, one reviewable PR, one `ticket-workflow` run. If the acceptance criteria describe two independent things a user could do, it's probably two tickets.
- **Thin first.** The first slice is the narrowest working path through the feature (happy path, one role, minimal fields). Later slices add variations, edge cases, and polish on top.
- **No layer-only tickets by default.** Don't split out "add the migration" or "build the model" on their own — fold the schema a slice needs into that slice. The exception is genuinely standalone groundwork that is large or risky on its own (e.g. a backfill on a big table, a new external integration) — call it out as such and agree it with the user.
- **Self-contained.** It makes sense without reading the feature document; it links to that document for wider context, and to the architecture document for the shared design it builds against.
- **Blocked-by only when real.** Add a dependency only when one ticket can't be built without the other already existing — not just because it's later in the working order.

## Ticket description

Use this structure for the Linear issue description (markdown). Omit a section only if it would genuinely be empty.

```markdown
## Context

Why this ticket exists and where it fits in the feature, in two or three sentences.

Part of: [<Feature document title>](<feature document URL>)
Architecture: [<Feature name> — Architecture](<architecture document URL>)

## Gaps

List outstanding questions and gaps that need resolving before work on the ticket can begin.

## Behaviour

What the user (or system) can do once this ships. Plain language, specific — roles, inputs, what happens, what they see.

## Acceptance criteria

- [ ] Observable, checkable statements of done — one behaviour each.
- [ ] Include the error, empty, and permission cases that belong to this slice.

## Out of scope

- Things a reader might reasonably expect here but that are deliberately left to another ticket (name it) or deferred.

## Technical notes

- The architecture components this ticket introduces or uses, by their names in the architecture document.
- Relevant existing files, models, and patterns found during investigation.
- Risks or open questions to settle during this ticket's own clarification phase.
- Guidance, not a prescribed implementation — the approach is decided when the ticket is worked.

## Sources

- The parts of the supplied material (brief, notes, prototypes, designs) that apply to this ticket, quoted or linked.
```

## Feature document

The Linear document created in the project, linked from every ticket.

```markdown
# <Feature name>

Epic branch: epic/<feature_snake_name>
Architecture: [<Feature name> — Architecture](<architecture document URL>)

## Summary

What the feature is, who it's for, and why — from the brief.

## Sources

- Each piece of supplied material, with a link or a short description of what it was (e.g. "Kickoff meeting notes, 2026-10-01").

## Decisions

- The feature decision log from planning: what was decided and why, including scope calls.

## Tickets

| Ticket | Title | Blocked by |
| --- | --- | --- |
| ENG-1234 | ... | — |

## Out of scope / deferred

- Everything explicitly left out of this feature, so it isn't lost.

## Deployment tasks

```
None yet.
```
```

### Deployment tasks

Everything that has to be run when the feature's merged work is deployed: database migrations, rake tasks, data backfills, and any other step beyond deploying the code. It's one deduplicated list for the whole feature, built up as tickets merge, so whoever deploys runs it top to bottom.

- **One command per line**, written as it runs on the deployed app (`bin/rails db:migrate`), never with a Docker or worker prefix. A step that isn't a command (a new environment variable or credential) is one short line saying what to set, without its value.
- **No duplicates.** A line already in the list isn't added again. `bin/rails db:migrate` appears once, however many tickets add migrations.
- **Order.** `bin/rails db:migrate` comes first, since other tasks usually depend on the schema; everything else follows in the order tickets merged.
- **Only merged work.** A ticket's tasks are added when it reaches QA or Done, not when its PR opens: an unmerged PR has nothing to deploy.
- **After a deploy**, the developer removes the lines that were run. A later ticket adds a command again if it needs it again.

In auto mode only the orchestrator writes this section (see `skills/orchestrate/SKILL.md`): workers run in parallel, and one writer means no edit overwrites another. Workers record their own ticket's tasks instead, per `skills/ticket-workflow/SKILL.md`.
