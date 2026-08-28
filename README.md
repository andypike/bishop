# bishop

A Claude Code plugin for working Linear tickets in Ruby on Rails codebases: read the ticket, investigate the code, clarify the approach before writing anything, implement in small reviewed TDD batches, then run a quality gate (tests, RuboCop, RubyCritic, mutation testing, style guide, code review) and a correctness-vs-ticket check before calling it done.

See `skills/ticket-workflow/SKILL.md` for the full workflow.

## Prerequisites

- A Linear MCP connector configured in the Claude Code session (used to read tickets and post comments).
- Target project uses RSpec or Minitest, and ideally already has RuboCop and RubyCritic configured (the workflow will ask before adding either).
- [Evilution](https://github.com/marinazzio/evilution) for mutation testing — used instead of `mutant`, which requires a paid license for private code. Add `gem "evilution", group: :test` to the target project's Gemfile.
- The project runs in Docker via `docker-compose`/`docker compose`. All Ruby/Rails commands (tests, RuboCop, RubyCritic, Evilution) run inside the container, never on the host — see `references/docker.md`.

## What's in here

- `skills/ticket-workflow/SKILL.md` — the staged workflow.
- `agents/correctness-checker.md` — subagent that checks the final diff against the original ticket and decision log. Runs on Opus at high effort.
- `agents/code-review-runner.md` — subagent that runs the built-in `code-review` skill against the diff. Also runs on Opus at high effort, so review quality doesn't depend on the main session's model.
- `style-guide/rails-style-guide.md` — the style guide this workflow enforces, applied the same way across every project. Seeded from thoughtbot's Rails AI rules, edited to taste. Tune it whenever code review surfaces a preference that isn't written down yet — that's how review overhead goes down over time.
- `references/quality-gates.md` — exact commands and how baseline-vs-after comparison works for each tool.
- `references/docker.md` — detecting the Docker Compose setup and wrapping every command to run inside the container.

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

Then in a session, just name a ticket: "let's work on ENG-1234."
