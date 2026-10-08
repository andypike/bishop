# Git Conventions

This workflow handles the epic branch, ticket branches, per-slice commits, pushing the ticket branch, and opening the PR. Merging is always the developer's.

## Epic branch

Every feature's work lands on its own **epic branch**, `epic/<feature_snake_name>` (e.g. `epic/csv_export`), created from the up-to-date root branch (`main`, falling back to `master`). `feature-planning` picks the name and records it in the feature document as `Epic branch: epic/<name>`; the feature document is the source of truth for which epic a ticket belongs to. Linear's GitHub automation moves a ticket to QA when its PR merges into `epic/*`, so the `epic/` prefix is load-bearing.

To create a missing epic branch:

```bash
git fetch origin <root-branch>
git push origin origin/<root-branch>:refs/heads/epic/<name>
```

A ticket with no feature document has no epic: base its branch on the root branch instead, and say so at the Phase 5 branch gate.

## Branch naming

`<TICKET-ID>_<brief_snake_case_summary>`, e.g. `ENG-1234_allow_user_searching`.

- `<TICKET-ID>` exactly as it appears in Linear (e.g. `ENG-1234`). Linear links the PR to the ticket from this ID in the branch name.
- Summary: lowercase, words joined with underscores, short (roughly 3-6 words) — enough to identify the ticket at a glance, not the full title.

### Rejected tickets (rework)

A rejected ticket already has a branch, and that work has already been merged into the epic for someone to test — so the rework needs its **own new branch**, never the original one.

`<TICKET-ID>_feedback_<brief_snake_case_summary>`, e.g. `ENG-123_feedback_alter_sort_order`.

- Same ticket ID as the original branch, so the two stay associated.
- `feedback` prefixes the summary, making it obvious at a glance that this branch is reacting to rejection rather than the first implementation.
- Summary describes the rework, not the original ticket — what the rejection asks for.
- If the ticket is rejected again, disambiguate with a different summary, not a counter (e.g. `ENG-123_feedback_fix_empty_state`).

## Before any changes (start of Phase 5)

Nothing gets written — not even a test file — until this is settled:

1. Check the current branch: `git branch --show-current`.
2. If it already matches the expected name for this piece of work, continue — already on the right branch. For a fresh ticket that means it starts with `<TICKET-ID>_`; for a rejected ticket it means it starts with `<TICKET-ID>_feedback_`. Being on the *original* `<TICKET-ID>_` branch does **not** count as already correct for rework — a new feedback branch is still needed.
3. Otherwise, **gate**: ask the developer whether to create the ticket branch now.
4. If approved:
   - Check for uncommitted changes (`git status`). If there are any, stop and ask rather than switching branches or losing them.
   - Find the epic branch from the feature document. If it doesn't exist on `origin`, **gate**: ask whether to create it (see [Epic branch](#epic-branch)).
   - Update the epic branch so the new branch starts from current code:
     ```bash
     git fetch origin <epic-branch>
     git checkout <epic-branch>
     git pull --ff-only origin <epic-branch>
     ```
     `--ff-only` fails loudly rather than silently creating a merge commit or diverging — if it fails, stop and ask.
   - Create and switch to the ticket branch: `git checkout -b <TICKET-ID>_<summary>` (or `<TICKET-ID>_feedback_<summary>` for a rejected ticket).

**Auto mode:** the orchestrator settles the branch before the worker starts, by creating a worktree on it:

```bash
git fetch origin <epic-branch>
git worktree add --no-track -b <ticket-branch> <worktree-path> origin/<epic-branch>
```

`--no-track` matters: without it the ticket branch tracks the epic, so a bare `git push` would target the epic.

If the ticket branch already exists locally (a ticket re-claimed after an error), attach it instead: `git worktree add <worktree-path> <ticket-branch>`. The worker only verifies the branch, per Phase 5.

## End of each TDD slice

After the implementation review gate in Phase 5 (step 5), before moving to the next slice:

1. **Gate**: ask the developer whether to commit this slice's changes.
2. If approved:
   - Re-check the current branch is still the one settled at the start of Phase 5 for this ticket. If not, stop and ask — don't commit blind.
   - Stage only the files touched by this slice, not a broad `git add -A`.
   - Commit with a short, specific message: `<TICKET-ID>: <what this slice does>`.
3. Move to the next slice.

**Auto mode:** commit every slice without the gate, with the same branch re-check and staging. If the branch re-check fails, park with `agent:needs-input`. Parking mid-implementation adds a WIP commit, per `references/escalation.md`.

## Pushing

Push only the ticket branch, and only forward:

```bash
git push -u origin <ticket-branch>
```

Run it exactly like that: **alone**, with no pipe, redirect, or `&&`. `git push`, `git fetch`, and `gh` reach GitHub only because the sandbox exempts commands that *start* with them; `git push … | tail` no longer matches, runs sandboxed, and fails with "Broken pipe". The same applies to every `gh` command below.

The epic, root, and every other branch are read-only to this workflow. If a push is rejected, stop — interactive mode asks the developer; auto mode parks with `agent:needs-input`.

Interactive mode pushes at the Phase 8 gate. Auto mode pushes when it parks after implementation has started, and at the end of Phase 8.

## Opening the PR

Write the body to a file (auto mode: `<state dir>/pr-body.md`; interactive: under `$TMPDIR`), then:

```bash
gh pr create --base <epic-branch> --head <ticket-branch> --title "<TICKET-ID>: <ticket title>" --body-file <body file>
```

Run it alone, as with `git push` above.

PR body template:

```markdown
Closes <TICKET-ID> — <Linear ticket URL>

## Summary
<what was implemented, briefly>

## Quality metrics (baseline → after)
- Tests: <examples, pass/fail, coverage>
- RuboCop: <offences>
- RubyCritic: <score>
- Mutation score: <score>

## Code review findings
- **Fixed**: <one line each>
- **Added**: <scope added during review>
- **Rejected**: <finding, and what was verified>
- **Already approved**: <finding that matched an earlier decision>

## Correctness check
<verdict; "No gaps found" when clean>

## Assumptions
<every assumption logged on the ticket; "None" if none>
```
