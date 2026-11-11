# Stack Selection

Every ticket is worked in one tech stack, and the stack decides which style guide, quality tools and environment apply. The supported stacks are the folders in `stacks/` that hold a `stack.md`; see [`stacks/README.md`](../stacks/README.md) for what each one provides.

Once the stack is chosen, "the stack's style guide", "the stack's quality gates" and "the stack's environment" mean `stacks/<id>/style-guide.md`, `stacks/<id>/quality-gates.md` and `stacks/<id>/environment.md`.

## Where a stack is recorded

- **The feature document** — a `Stacks:` line under `Epic branch:`, naming each stack the feature uses and the GitHub repo it lives in. Separate several with ` · `:

  ```
  Stacks: rails — acme/shop
  ```

- **Each ticket** — one label from the single-select `stack` label group: `stack:<id>`, for example `stack:rails`. `feature-planning` sets it when it creates the ticket. The group has one label per supported stack, each described with the stack's name; whoever finds one missing (preflight, `feature-planning`) creates it.

## Choosing a ticket's stack

Take the first of these that gives an answer:

1. **The ticket's `stack:<id>` label.**
2. **The feature document's `Stacks:` line**, when it names a single stack.
3. **Detection** — check the repo root against the Detection section of every stack's `stack.md`. Exactly one match: that's the stack.
4. **Ask** the developer (`AskUserQuestion`), offering every supported stack, when detection matches none or more than one. If none of them fits, stop: the plugin doesn't support this project's stack, and a quality gate with no tools would mean nothing.

Then **announce** it in one line and carry on — don't ask for confirmation: `Stack: Ruby on Rails (from the ticket's label)`, or `(detected: Gemfile with rails, config/application.rb)`. The developer corrects it if it's wrong.

**Check the repo matches.** When the `Stacks:` line names a repo for the ticket's stack, this checkout's `origin` must be that repo. When there's no `Stacks:` line but the stack came from the label, run detection: this repo must be detected as that stack. If either check fails, the ticket belongs somewhere else: stop and say which stack and repo it's for — usually a sibling folder of this one — so the developer can open the session there. Never work a ticket in the wrong repo.

## In auto mode

The orchestrator chooses each ticket's stack when it claims it, by steps 1 and 2 above, or else from the stack recorded in `project.md` at preflight. A ticket in a project whose `Stacks:` line names more than one stack must carry a `stack:*` label; without one it isn't claimed, and preflight warns about it.

The worker is told its stack in its prompt and doesn't choose again. It still checks the repo matches; if it doesn't, it parks with `agent:needs-input`.
