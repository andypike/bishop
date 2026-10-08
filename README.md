# Bishop - Not bad for a human.

A Claude Code plugin for working Linear tickets in Ruby on Rails codebases: read the ticket, investigate the code, clarify the approach before writing anything, implement in small reviewed TDD batches (on a per-ticket branch, with a commit after each reviewed slice), then run a quality gate (tests, RuboCop, RubyCritic, mutation testing, style guide, code review) and a correctness-vs-ticket check before calling it done.

Before that, it can also help plan a new feature: give it a detailed brief plus any supporting material (docs, files, prototypes, meeting notes), and it investigates the codebase, proposes vertical-slice tickets, fleshes them out with you one at a time, and creates them in a Linear project — ready to work one by one.

Tickets can be worked interactively, with a developer reviewing each step, or in **auto mode**: an orchestrator works through a Linear project's released tickets with headless agents in parallel, one git worktree and one set of databases per ticket. The agent stops for a developer only to approve its plan, when something genuinely needs a decision, or when a quality check still fails after two retries. It then opens a PR for review. Linear is the dashboard: ticket statuses and an `agent` label group show where every ticket is and which ones need a developer.

See `skills/feature-planning/SKILL.md` and `skills/ticket-workflow/SKILL.md` for the full workflows.

## Prerequisites

- A Linear MCP connector configured in the Claude Code session (used to read and create tickets, create feature documents, and post comments).
- Target project uses RSpec or Minitest, and ideally already has RuboCop and RubyCritic configured (the workflow will ask before adding either).
- [Evilution](https://github.com/marinazzio/evilution) for mutation testing — used instead of `mutant`, which requires a paid license for private code. Add `gem "evilution", group: :test` to the target project's Gemfile.
- The project runs in Docker via `docker-compose`/`docker compose`. All Ruby/Rails commands (tests, RuboCop, RubyCritic, Evilution) run inside the container, never on the host — see `references/docker.md`.

## What's in here

- `skills/feature-planning/SKILL.md` — breaks a new feature down into Linear tickets (with blocked-by relations and a feature document in the project).
- `skills/ticket-workflow/SKILL.md` — the staged workflow for working a single ticket.
- `agents/correctness-checker.md` — subagent that checks the final diff against the original ticket and decision log. Runs on Opus at high effort.
- `agents/code-review-runner.md` — subagent that runs the built-in `code-review` skill against the diff. Also runs on Opus at high effort, so review quality doesn't depend on the main session's model.
- `style-guide/rails-style-guide.md` — the style guide this workflow enforces, applied the same way across every project. Seeded from thoughtbot's Rails AI rules, edited to taste. Tune it whenever code review surfaces a preference that isn't written down yet — that's how review overhead goes down over time.
- `references/quality-gates.md` — exact commands and how baseline-vs-after comparison works for each tool.
- `references/docker.md` — detecting the Docker Compose setup and wrapping every command to run inside the container, including the per-worker container and databases used in auto mode.
- `references/ticket-template.md` — the ticket and feature document structure `feature-planning` writes, and what makes a ticket a good single slice.
- `references/git.md` — the epic branch, ticket branches (`<TICKET-ID>_brief_summary`), per-slice commits, pushing, and opening the PR. Merging stays with the developer.
- `references/agent-status.md` — auto mode's Linear statuses and `agent` labels: what each means, who sets it, and how a developer responds.
- `references/escalation.md` — when an auto mode agent stops for a developer, and what its Linear comments contain.
- `skills/orchestrate/SKILL.md` — auto mode's orchestrator: claims released tickets, starts and resumes agents, and cleans up after merge. Run on a loop.
- `references/preflight.md` — the checks the orchestrator runs on a project before starting any work.
- `settings/worker.json` — permissions and sandbox rules for headless auto mode agents.
- `settings/orchestrator.json` — permissions for the orchestrator's session.
- `bin/start-worker` — starts or resumes one auto mode agent in the background.

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

- [ ] **Docker** is running (Docker Desktop, OrbStack, or similar).
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

- [ ] **Test and quality tools** in the Gemfile: RSpec or Minitest, RuboCop, RubyCritic, and Evilution.
- [ ] **Per-worker databases**: each environment has one database, and its name can be changed per worker, either through an environment variable read in `config/database.yml` or by `DATABASE_URL`. See `references/docker.md`.
- [ ] **Shared services written by tests** can be separated per worker. For example, search index names can take a per-worker suffix. Otherwise the project runs one agent at a time. See `references/docker.md`.
- [ ] **Recommended**: in the repo's GitHub settings, "Automatically delete head branches", so merged ticket branches clean themselves up.

### Planning for auto mode

Run `feature-planning` from inside the project's repo. It creates the Linear project, the feature document and its epic branch, and the tickets. Tickets are created without the `agent:claimable` label: a developer releases each one to agents by moving it to Todo and adding `agent:claimable`.

### Running auto mode

From the project's main checkout:

```bash
claude --settings /path/to/bishop/settings/orchestrator.json
```

```
/loop 5m /bishop:orchestrate "<Linear project name>"
```

Add `max_workers: <n>` after the project name to change how many agents run at once (default 2). The first tick runs preflight and asks you to confirm the Linear GitHub automation; after that, keep the session open and work from Linear. Filter the project by the `agent:awaiting-approval`, `agent:needs-input`, `agent:gate-failed` and `agent:error` labels, plus the In Review status, to see what needs you.

The orchestrator stops its loop by itself once every ticket in the project is in QA, Done or Canceled and its worktrees and databases are cleaned up. If a ticket is rejected after that, start it again.

## Iterating on the plugin

Edits to `SKILL.md` files and agents aren't picked up by a running session: run `/reload-plugins` to reload skills, agents, hooks, and MCP/LSP servers without restarting. Reference files, the style guide, and `settings/worker.json` are read from disk each time they're used, so edits to them apply straight away.
