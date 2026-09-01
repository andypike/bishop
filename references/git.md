# Git Conventions

Branching and per-slice commits are handled by this workflow. Pushing and opening a PR are not — those stay manual.

## Branch naming

`<TICKET-ID>_<brief_snake_case_summary>`, e.g. `ENG-1234_allow_user_searching`.

- `<TICKET-ID>` exactly as it appears in Linear (e.g. `ENG-1234`).
- Summary: lowercase, words joined with underscores, short (roughly 3-6 words) — enough to identify the ticket at a glance, not the full title.

## Before any changes (start of Phase 5)

Nothing gets written — not even a test file — until this is settled:

1. Check the current branch: `git branch --show-current`.
2. If it already starts with `<TICKET-ID>_`, continue — already on the right branch.
3. Otherwise, **gate**: ask the developer whether to create the ticket branch now.
4. If approved:
   - Check for uncommitted changes (`git status`). If there are any, stop and ask rather than switching branches or losing them.
   - Determine the root branch: prefer `main`, fall back to `master`, check for epic branch for large feature work (check `git show-ref --verify --quiet refs/heads/main`, or the remote default via `git symbolic-ref refs/remotes/origin/HEAD`).
   - Update the root branch so the new branch starts from current code:
     ```bash
     git fetch origin <root-branch>
     git checkout <root-branch>
     git pull --ff-only origin <root-branch>
     ```
     `--ff-only` fails loudly rather than silently creating a merge commit or diverging — if it fails, stop and ask.
   - Create and switch to the ticket branch: `git checkout -b <TICKET-ID>_<summary>`.

## End of each TDD slice

After the implementation review gate in Phase 5 (step 5), before moving to the next slice:

1. **Gate**: ask the developer whether to commit this slice's changes.
2. If approved:
   - Re-check the current branch still starts with `<TICKET-ID>_` for this ticket. If not, stop and ask — don't commit blind.
   - Stage only the files touched by this slice, not a broad `git add -A`.
   - Commit with a short, specific message: `<TICKET-ID>: <what this slice does>`.
3. Move to the next slice.

## Still out of scope

Pushing to remote and opening a PR remain manual. This workflow creates the branch and commits locally, nothing more.
