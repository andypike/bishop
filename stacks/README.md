# Stacks

The workflows in this plugin are the same whatever a project is built with: Linear, the plan gate, small TDD slices, the quality gate, the correctness check, and auto mode. What differs between tech stacks lives here, one folder per stack. A workflow never names a stack's tools; it reads them from the stack's files.

Each ticket is worked in exactly one stack, chosen per [`references/stack-selection.md`](../references/stack-selection.md).

## Supported stacks

| Stack | ID | Folder |
|---|---|---|
| Ruby on Rails | `rails` | [`rails/`](./rails/) |

## What a stack provides

A folder named after the stack's ID — lowercase, hyphenated (`rails`, `react-native`) — holding these files:

| File | What it holds | Read by |
|---|---|---|
| `stack.md` | The stack's name and ID, and how to detect it in a repo. | stack selection |
| `style-guide.md` | What good code looks like in this stack. Same role for every stack: applied while implementing, walked as a checklist in the quality gate, and the starting point for a feature's architecture. | ticket-workflow, feature-planning, epic review |
| `quality-gates.md` | The stack's tools: how to detect them, the baseline and after-implementation commands, and how to read each one's output. How the gate is judged is generic, in [`references/quality-gates.md`](../references/quality-gates.md). | ticket-workflow, epic review |
| `environment.md` | Where and how commands run (on the host, in a container), how auto mode keeps parallel workers apart, and what to clean up afterwards. | ticket-workflow, orchestrator, preflight |

### `stack.md`

```markdown
# <Stack name>

- **ID**: `<id>` — also its Linear label, `stack:<id>`, and its name in a feature document's `Stacks:` line.

## Detection

The files and contents that identify a repo as this stack, specific enough that a repo of another stack never matches.
```

## Adding a stack

1. Create `stacks/<id>/` with the four files above. Write the style guide the way the Rails one was written: seed it from a respected source, then tune it as reviews surface preferences.
2. Add it to the table above.
3. Nothing else: stack selection finds the new folder, and preflight and `feature-planning` create its `stack:<id>` label in Linear the first time it's needed.
