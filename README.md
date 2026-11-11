# Bishop - Not bad for a human.

A Claude Code plugin for working Linear tickets: read the ticket, investigate the code, clarify the approach before writing anything, implement in small reviewed TDD batches (on a per-ticket branch, with a commit after each reviewed slice), then run a quality gate (tests, linters, mutation testing, style guide, code review) and a correctness-vs-ticket check before calling it done.

The workflow is the same whatever the project is built with; each tech stack brings its own style guide, quality tools and environment from `stacks/`. Ruby on Rails and React Native (Expo) are supported today. Each ticket is worked in one stack, chosen from its `stack:*` label in Linear or detected from the repo.

Before that, it can also help plan a new feature: give it a detailed brief plus any supporting material (docs, files, prototypes, meeting notes), and it investigates the codebase, proposes vertical-slice tickets, fleshes them out with you one at a time, designs the feature's architecture with you (following the style guide, with diagrams), and creates it all in a Linear project — ready to work one by one or in parallel.

Tickets can be worked interactively, with a developer reviewing each step, or in **auto mode**: an orchestrator works through a Linear project's released tickets with headless agents in parallel, one git worktree per ticket, kept apart as its stack needs (for Rails, its own databases). The agent stops for a developer only to approve its plan, when something genuinely needs a decision, or when a quality check still fails after two retries. It then opens a PR for review. Linear is the dashboard: ticket statuses and an `agent` label group show where every ticket is and which ones need a developer.

See `skills/feature-planning/SKILL.md` and `skills/ticket-workflow/SKILL.md` for the full workflows.

It also upgrades Expo / React Native apps: one SDK hop at a time with a checkpoint commit after each, guided by the project's own `docs/upgrades/` history and a shared list of gotchas from past upgrades. Each upgrade writes its own record and adds what it learned to that shared list. See `skills/react-native-upgrade/SKILL.md`.

Once a feature is planned, it can write the client's Statement of Work: it asks for the fee, VAT, payment terms, people and dates, takes the scope and exclusions from the Linear project, and publishes a Kyan-branded SoW as a Design artifact of A4 pages, ready to export to PDF. The page breaks fall between sections and are chosen by measuring the content. See `skills/statement-of-work/SKILL.md`.

## Prerequisites

- A Linear MCP connector configured in the Claude Code session (used to read and create tickets, create feature documents, and post comments).
- For each stack the project uses, what `stacks/<stack>/` asks for. For Rails:
  - Target project uses RSpec or Minitest, and ideally already has RuboCop and RubyCritic configured (the workflow will ask before adding either).
  - [Evilution](https://github.com/marinazzio/evilution) for mutation testing — used instead of `mutant`, which requires a paid license for private code. Add `gem "evilution", group: :test` to the target project's Gemfile.
  - The project runs in Docker via `docker-compose`/`docker compose`. All Ruby/Rails commands (tests, RuboCop, RubyCritic, Evilution) run inside the container, never on the host — see `stacks/rails/environment.md`.
- For React Native (Expo, TypeScript):
  - Jest with the `jest-expo` preset and React Native Testing Library, TypeScript, ESLint and Prettier.
  - [Stryker](https://stryker-mutator.io/) for mutation testing — experimental. It's installed once per machine in `~/.bishop/tools/stryker`, not in the project (auto mode's preflight installs it); see `stacks/react-native/quality-gates.md`.
  - Commands run on the host, under the Node version in `.nvmrc` — see `stacks/react-native/environment.md`. Builds and over-the-air updates stay with the developer.

The prerequisites above are for the ticket workflows. `react-native-upgrade` runs on the host and needs no Linear or Docker. It needs the Node version from the project's `.nvmrc`, and ideally Xcode and the Android SDK. Whatever can't be built locally is verified with EAS builds.

## What's in here

- `skills/feature-planning/SKILL.md` — breaks a new feature down into Linear tickets (with blocked-by relations, a feature document, and an architecture document in the project).
- `skills/ticket-workflow/SKILL.md` — the staged workflow for working a single ticket.
- `skills/statement-of-work/SKILL.md` — writes a client-facing Statement of Work for a planned Linear project and publishes it as a Design artifact.
- `references/statement-of-work/sow-template.dc.html` — the Kyan SoW layout the skill fills in (one A4 Design board).
- `agents/correctness-checker.md` — subagent that checks the final diff against the original ticket and decision log. Runs on Opus at high effort.
- `agents/code-review-runner.md` — subagent that runs the built-in `code-review` skill against the diff. Also runs on Opus at high effort, so review quality doesn't depend on the main session's model.
- `stacks/` — everything specific to a tech stack, one folder per stack, so the workflows themselves don't depend on one. `stacks/README.md` lists the supported stacks, what each must provide, and how to add one.
- `references/stack-selection.md` — how each ticket's stack is chosen (its `stack:*` label, the feature document's `Stacks:` line, or detection) and announced.
- `stacks/rails/` and `stacks/react-native/` — each stack's detection and delivery rules (`stack.md`), style guide, quality tools and environment.
- `stacks/rails/style-guide.md` — the Rails style guide this workflow enforces, applied the same way across every project. Seeded from thoughtbot's Rails AI rules, edited to taste. Tune it whenever code review surfaces a preference that isn't written down yet — that's how review overhead goes down over time.
- `references/quality-gates.md` — how the quality gate is judged: baseline vs after, and when each check runs.
- `stacks/rails/quality-gates.md` — the Rails tools: exact commands and how to read each one's output.
- `stacks/rails/environment.md` — detecting the Docker Compose setup and wrapping every command to run inside the container, including the per-worker container and databases used in auto mode.
- `references/ticket-template.md` — the ticket and feature document structure `feature-planning` writes, and what makes a ticket a good single slice.
- `references/architecture.md` — the feature's architecture document: what it settles, how it's built from the style guide, its Mermaid diagrams, and how tickets follow it.
- `references/git.md` — the epic branch, ticket branches (`<TICKET-ID>_brief_summary`), per-slice commits, pushing, and opening the PR. Merging stays with the developer.
- `skills/react-native-upgrade/SKILL.md` — upgrades an Expo / React Native app's SDK and libraries, hop by hop, then writes an upgrade record.
- `references/react-native-upgrade/gotchas.md` — breakages from past upgrades that any app could hit, indexed by SDK. Every upgrade reads it, and adds what it learns.
- `references/react-native-upgrade/upgrade-record-template.md` — the format of the `docs/upgrades/` record each upgrade leaves in the project.
- `references/agent-status.md` — auto mode's Linear statuses and `agent` labels: what each means, who sets it, and how a developer responds.
- `references/escalation.md` — when an auto mode agent stops for a developer, and what its Linear comments contain.
- `skills/orchestrate/SKILL.md` — auto mode's orchestrator: claims released tickets, starts and resumes agents, and cleans up after merge. Run on a loop.
- `references/preflight.md` — the checks the orchestrator runs on a project before starting any work.
- `settings/worker.json` — permissions and sandbox rules for headless auto mode agents.
- `settings/orchestrator.json` — permissions for the orchestrator's session.
- `bin/start-worker` — starts or resumes one auto mode agent in the background.
- `references/epic-review.md` — the optional code review of a whole epic once its tickets have all merged, and how its findings get fixed.
- `bin/wait-for-worker` — waits for one auto mode agent to exit (used by the epic review).
- `bin/agent-status` — a live view of where each auto mode agent is, from the progress logs they keep.
- `apps/menubar/` — a macOS menu bar app showing the same, with Linear status, notifications and links.

## Using it in a project

While developing:

```bash
claude --plugin-dir /path/to/bishop
```

Once shared with the team, install from a marketplace:

```
/plugin marketplace add <bishop-repo-url>
/plugin install bishop@<marketplace-name>
```

Then in a session, plan a feature ("let's plan the CSV export feature into tickets in the Reporting project") or just name a ticket: "let's work on ENG-1234."

## Auto mode setup

Everything auto mode needs, once per machine, Linear team and project. The orchestrator's preflight check verifies the project items before it starts any work, and reports anything missing with instructions.

### Your machine

- [ ] **Docker** is running (Docker Desktop, OrbStack, or similar), for Rails projects.
- [ ] **GitHub CLI** (`gh`) is installed and signed in with push access to the project's repo: `gh auth status`.
- [ ] **Claude Code** is signed in. Every agent runs under your account, so with a Claude plan, auto mode uses your plan's usage limits, and running agents in parallel uses them up faster.
- [ ] **The Linear connector** is connected in Claude Code: `claude mcp list` shows Linear as connected.

### Your Linear team

- [ ] **Statuses**: Todo, In Progress, In Review, **QA**, Done, and **Rejected**. QA and Rejected usually need adding.
- [ ] **GitHub integration** connected for the project's repo, with these automations (team settings → Issue statuses & automations):
  - PR opened → **In Review**
  - PR merged into `epic/*` → **QA** (a branch-specific rule)
- [ ] **The `agent` label group**: preflight creates it if it's missing.

Linear links a PR to its ticket from the ticket ID in the branch name (`ENG-123_add_export`), so no extra setup is needed for that.

### Your project's repo

- [ ] **Test and quality tools** for the project's stack, per its `quality-gates.md`. For Rails, in the Gemfile: RSpec or Minitest, RuboCop, RubyCritic, and Evilution. For React Native, in `package.json`: Jest with `jest-expo`, React Native Testing Library, TypeScript, ESLint and Prettier.
- [ ] **Node** (React Native): the machine switches Node per directory from each project's `.nvmrc`, in every shell, not just interactive ones. With mise, see "Node versions" in `stacks/react-native/environment.md`.
- [ ] **Per-worker databases** (Rails): each environment has one database, and its name can be changed per worker, either through an environment variable read in `config/database.yml` or by `DATABASE_URL`. See `stacks/rails/environment.md`.
- [ ] **Shared services written by tests** (Rails) can be separated per worker. For example, search index names can take a per-worker suffix. Otherwise the project runs one agent at a time. See `stacks/rails/environment.md`.
- [ ] **Recommended**: in the repo's GitHub settings, "Automatically delete head branches", so merged ticket branches clean themselves up.

### Planning for auto mode

Run `feature-planning` from inside the project's repo. It creates the Linear project, the feature document and its epic branch, the architecture document, and the tickets. Auto mode won't start on a project without an architecture document, because agents working in parallel build against it; for a project planned before that existed, ask `feature-planning` to add one. Tickets are created without the `agent:claimable` label: a developer releases each one to agents by moving it to Todo and adding `agent:claimable`.

### Running auto mode

From the client folder that holds the project's repos side by side (a project can span repos, such as a Rails backend and a React Native app), or from the repo's own checkout for a single-repo project:

```bash
cd ~/code/<client>
claude --settings /path/to/bishop/settings/orchestrator.json
```

```
/loop 5m /bishop:orchestrate "<Linear project name>"
```

Add `max_workers: <n>` after the project name to change how many agents run at once (default 2). The first tick runs preflight and asks you to confirm the Linear GitHub automation; after that, keep the session open and work from Linear. As tickets merge, the orchestrator adds each one's deployment tasks (migrations, rake tasks, anything else to run at deploy time) to the **Deployment tasks** section of the feature document, without duplicates, so the list is ready when you deploy the epic. Filter the project by the `agent:awaiting-approval`, `agent:needs-input`, `agent:gate-failed` and `agent:error` labels, plus the In Review status, to see what needs you.

To see where each running agent is (its phase, slice, or quality check), run this in another terminal. It refreshes itself every 10 seconds, and flags an agent that has logged nothing for 20 minutes as `quiet`:

```bash
/path/to/bishop/bin/agent-status        # all projects; or pass one project's folder under ~/.bishop/projects
```

### Menu bar app (macOS)

`apps/menubar` is a small menu bar app with the same view, plus what's waiting on you in Linear. Build it with `apps/menubar/build.sh` (needs Xcode or its command line tools), copy `build/Agent Status.app` to `/Applications`, and open it.

- **The icon** is a dot with how many tickets need you beside it: **red** when something needs you (a plan to approve, a question, a failed gate, an agent error, or a PR to review), **amber** when something looks stuck (an agent quiet for 20 minutes, or an orchestrator that hasn't ticked for 15), **green** while agents are working, and **grey** otherwise.
- **Click it** for every ticket the agents hold, grouped by project and most urgent first: the ticket, why it needs you, its latest progress line, an estimated progress bar from its phase and slice, and links that open the ticket in Linear and, once there is one, its PR. Click a row for its last five progress lines and a link to its worktree.
- **Notifications** when a ticket turns red or an agent goes quiet; clicking one opens the ticket, or the PR when it's ready for review.

It only reads files under `~/.bishop`: each worker's `progress.md`, and the `status.json` the orchestrator writes every tick with labels, statuses and links. It never calls Linear or changes anything. `AgentStatus --print` (the binary inside the app) prints the same view in the terminal.

Each agent merges the latest epic into its branch before it starts implementing, so it builds on tickets that merged while its plan waited for approval. Agents always merge, never rebase, so nothing is force-pushed.

If a ticket's PR stops merging cleanly because another ticket merged first, the orchestrator resumes that ticket's agent to merge the epic into its branch and resolve the conflicts, keeping both tickets' changes. It re-runs the tests, pushes, and comments on the ticket with how each file was resolved. It parks with `agent:needs-input` instead when a conflict needs a decision.

The orchestrator stops its loop by itself once every ticket in the project is in QA, Done or Canceled and its worktrees and databases are cleaned up. If a ticket is rejected after that, start it again.

When it stops, it offers to **review the whole epic**. Each ticket's PR was reviewed alone, so this looks for what only shows across tickets. It runs the `code-review` skill at `xhigh` effort over the epic's full diff, then shows you the findings with a recommendation for each. By default the recommended ones are fixed: an agent fixes them test first in a worktree, runs the quality gate, and the orchestrator pushes the commits straight onto the epic branch (fast-forward only). You can instead fix all of them, pick which to fix, or defer them, recording deferred findings as unreleased Linear tickets, in the feature document, or not at all. To review an epic at another time, run `/bishop:orchestrate "<Linear project name>" review`.

## Iterating on the plugin

Edits to `SKILL.md` files and agents aren't picked up by a running session: run `/reload-plugins` to reload skills, agents, hooks, and MCP/LSP servers without restarting. Reference files, the style guide, and `settings/worker.json` are read from disk each time they're used, so edits to them apply straight away.
