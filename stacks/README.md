# Stacks

The workflows in this plugin are the same whatever a project is built with: Linear, the plan gate, small TDD slices, the quality gate, the correctness check, and auto mode. What differs between tech stacks lives here, one folder per stack. A workflow never names a stack's tools; it reads them from the stack's files.

Each ticket is worked in exactly one stack, chosen per [`references/stack-selection.md`](../references/stack-selection.md).

## Supported stacks

| Stack | ID | Folder |
|---|---|---|
| Ruby on Rails | `rails` | [`rails/`](./rails/) |
| React Native (Expo) | `react-native` | [`react-native/`](./react-native/) |

## What a stack provides

A folder named after the stack's ID — lowercase, hyphenated (`rails`, `react-native`) — holding four files. Each must have the sections listed, under these headings, because the workflows refer to them by name. [`rails/`](./rails/) is the worked example.

### `stack.md` — identity, and what the stack changes in planning and delivery

- **ID** — its Linear label `stack:<id>` and its name in a feature document's `Stacks:` line.
- **Detection** — the files and contents that identify a repo as this stack, specific enough that a repo of another stack never matches. Used by `references/stack-selection.md`.
- **Sensitive changes** — what needs a developer's say-so when the plan didn't include it (escalation trigger 4), on top of the ones every stack shares.
- **Deployment tasks** — what counts as a deploy-time step, how each is written, what comes first, and how Phase 8 checks the list against the diff.
- **Architecture** — the style guide sections the architecture document walks and what each decides, the stack's shared files, the diagrams that usually apply, and example components. Used by `references/architecture.md`.

### `style-guide.md` — what good code looks like

Applied while implementing, walked as a checklist in the quality gate, and the starting point for a feature's architecture. Seed it from a respected source, then tune it as reviews surface preferences. End it with a **Quality gate philosophy** section pointing at `references/quality-gates.md`.

### `quality-gates.md` — the stack's tools

How the gate is judged is generic, in [`references/quality-gates.md`](../references/quality-gates.md). This file holds:

- **Checks** — a table of the tools: kind (must pass, baseline-compared, or mutation), what's recorded, and when each is clean.
- **Metrics** — the lines the results take in the final comment and the PR body.
- **Preflight check** — the auto mode check that every tool is installed.
- **Tool detection**, **Baseline capture**, and **After implementation** — the exact commands and how to read each one's output.

### `environment.md` — where and how commands run

- **Detect the setup** — how Phase 2 works out where commands run (on the host, in a container) and how to wrap them.
- For auto mode, under **Worker mode**: how parallel workers are kept apart, then:
  - **Preflight checks** — what preflight verifies about the environment, and the **smoke test command** run by a headless agent;
  - **Project state** — what preflight records in `project.md`;
  - **At claim** — setup after a worker's worktree is created;
  - **Worker prompt** — the block the orchestrator adds to a worker's prompt;
  - **Cleaning up** — what's undone once the ticket reaches QA or Done.

## Adding a stack

1. Create `stacks/<id>/` with the four files above, every section filled in.
2. Add it to the table above.
3. Nothing else: stack selection finds the new folder, and preflight and `feature-planning` create its `stack:<id>` label in Linear the first time it's needed.
