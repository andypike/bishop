# Agent Status in Linear

Linear is the source of truth for every ticket worked in auto mode. A ticket's **status** says where the work is; exactly one label from the `agent` group says where the agent is. The orchestrator, a worker, or a developer can read any ticket and know who acts next.

## Statuses

| Status | Set by | Meaning |
|---|---|---|
| Todo | developer / `feature-planning` | Ready to be worked — by an agent only once it is claimable (below). |
| In Progress | orchestrator, on claim | A worker owns the ticket. |
| In Review | Linear's GitHub integration, when the PR opens | PR awaiting developer review. |
| QA | Linear's GitHub integration, when the PR merges into `epic/*` | Merged; the orchestrator cleans up and ignores it from here. |
| Done | developer, after QA passes | Finished; ignored. |
| Rejected | developer, after QA fails | Rework — by an agent only once it is claimable (below). |

## Claimable tickets

Todo and Rejected also hold work that isn't for agents: client actions, or a rejection the developer is still investigating. So the developer releases a ticket to agents explicitly, with the `agent:claimable` label. The orchestrator claims a ticket only when all four hold:

1. It belongs to **the Linear project the orchestrator was started for**. Several projects can be in flight at once; one orchestrator works one project and its epic branch, never tickets from another project.
2. Its status is **Todo** or **Rejected**.
3. It carries **`agent:claimable`**.
4. It is **unblocked**: every one of its `blockedBy` tickets is in QA or Done, since both mean the blocker's code is on the epic branch.

The Linear MCP returns `blockedBy` as IDs only, so read the blockers' statuses from a single project-wide issue listing rather than fetching each one.

For a Rejected ticket, the developer first adds the rejection details as comments, then marks it claimable — the worker treats those comments as the rework's scope.

## The `agent` label group

A single-select label group named `agent` on the team. 🔴 marks the states where a developer acts next.

| Label | Set by | Meaning |
|---|---|---|
| `agent:claimable` | developer | Released to agents; the orchestrator may claim it. |
| `agent:planning` | orchestrator, on claim | Worker is investigating and drafting the plan. |
| `agent:awaiting-approval` 🔴 | worker | Plan posted; waiting for developer sign-off. |
| `agent:plan-approved` | developer | Plan signed off; resume the worker. |
| `agent:working` | worker | Implementing and running the quality gate. |
| `agent:needs-input` 🔴 | worker | An escalation trigger fired; the question is in a comment. |
| `agent:gate-failed` 🔴 | worker | The quality gate still fails after two retries; details are in a comment. |
| `agent:error` 🔴 | orchestrator | The worker crashed twice; the log path is in a comment. |
| `agent:answered` | developer | Developer has responded to a 🔴 state or a plan; resume the worker. |
| `agent:pr-open` | worker | PR created and linked; developer reviews and merges. |

## Changing the label: always a swap

Linear rejects adding a second label from a single-select group (`400: Only one label in a group can be applied to an issue`), so every change is a **swap**:

1. Read the ticket's current labels.
2. In one `save_issue` call, pass `removeLabels: [<current agent:* label>]` and `addLabels: [<new agent:* label>]`.

Always use `addLabels` / `removeLabels`. The `labels` field replaces the ticket's whole label set and would wipe unrelated labels such as `Bug`.

A failed swap means the label changed since you read it — usually a developer acting at the same moment. Re-read the ticket and decide again from its current state; the developer's label wins.

## Parking

When a worker needs a developer, it **parks** the ticket: post the comment first, then swap to the 🔴 label, then exit. Comment-then-label means a 🔴 label always has its context waiting beneath it. What each comment contains is defined in `references/escalation.md`.

## Developer responses

The developer swaps the label in the Linear UI (picking a label from the group replaces the current one):

- **Approve the plan**: swap to `agent:plan-approved`. Any comments added alongside are amendments to the plan.
- **Ask for a revised plan, answer a question, or unblock a failed gate** (by guidance or by fixing the branch yourself): comment, then swap to `agent:answered`.

The orchestrator resumes any ticket labelled `agent:plan-approved` or `agent:answered`. On resume, the worker reads every comment posted since it parked; those comments are binding.

## Clean-up

When a ticket reaches QA or Done, the orchestrator removes its `agent:*` label. A ticket later moved to Rejected therefore starts unlabelled, and stays with the developer until they mark it `agent:claimable` again.
