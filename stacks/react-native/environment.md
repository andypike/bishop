# Running commands in a React Native project

Everything runs **on the host**, from the repo root, with the Node version and package manager the project pins. There's no container and no database: the test suite mocks the API and native modules, so it needs nothing running.

## Detect the setup (part of Phase 2 — Investigation)

1. **Package manager** — from the lockfile: `yarn.lock` → Yarn, `package-lock.json` → npm, `pnpm-lock.yaml` → pnpm, `bun.lock` / `bun.lockb` → Bun. A `packageManager` field in `package.json` pins its version. Use it for every install and script; never mix managers, or the lockfile changes under you.
2. **Node** — compare `node -v` with `.nvmrc` (or `engines.node` in `package.json`). If the major version differs, stop and ask the developer to switch (`nvm use`) and restart the session: a different Node can resolve different packages and change test results.
3. **Commands** — read `package.json` scripts and any `justfile` / `Makefile` for the project's test, lint, typecheck and format commands, and use those. Note what each covers: lint and format scripts often only cover `app/` and `App.tsx`, not test helpers outside it.
4. **Dependencies installed** — `node_modules` exists and matches the lockfile. If it doesn't, ask before installing.

## Gotchas

- **Environment variables in tests.** Some projects inline `process.env` values into the code at transform time (a Babel plugin such as `transform-inline-environment-variables`), and Jest caches the transformed files. A test that reads one then depends on the shell it ran from — the developer's `.env`, loaded by direnv, for example. CI runs without a `.env`, so a test must set any variable it relies on itself; one that passes only with the local `.env` is a bug to fix, not to work around.
- **Shared caches.** Never run cache-reset commands (`just reset-caches`, `expo start --clear`, deleting `$TMPDIR/metro-*` or `$TMPDIR/haste-map-*`) — other sessions and workers may be using them.
- **Nothing that builds or publishes.** No `expo start`, `expo run:*`, `expo prebuild`, `eas build`, `eas update` or `eas submit`, and no project recipes that wrap them. Builds and updates belong to the developer (see "Deployment tasks" in `stack.md`). `settings/worker.json` denies the EAS commands to workers.
- **Run from the repo root.** Some test suites shell out with paths relative to the working directory.

## Worker mode (auto mode)

Several workers run at once, each in its own git worktree. Nothing is shared at test time except the CPU, so keeping workers apart means:

- **its own `node_modules`**, installed in the worktree from the lockfile when the ticket is claimed;
- **its own Jest cache**, in the ticket's state directory, so transformed files (and any inlined environment values) never leak between worktrees;
- **a share of the CPU**: Jest's `--maxWorkers` and Stryker's `--concurrency` are the machine's cores divided by the maximum active workers, capped at 8 and no less than 2.

### Working it out (orchestrator, at preflight)

1. **Package manager and install command** — per "Detect the setup". The orchestrator installs into a worktree without changing directory, so record the form that takes the path: `npm ci --prefix <worktree>`, `yarn install --frozen-lockfile --cwd <worktree>` (Yarn 1), `yarn --cwd <worktree> install --immutable` (Yarn 2+), `pnpm --dir <worktree> install --frozen-lockfile`, or `bun install --frozen-lockfile --cwd <worktree>`.
2. **Node** — `node -v` in the orchestrator's session must match the project's `.nvmrc` major version: workers inherit it. Every stack in a project shares the orchestrator's Node, so two repos needing different Node majors can't run in one orchestrator session.
3. **Commands** — the test, lint, typecheck and format commands, per "Detect the setup", and the paths each covers.
4. **Job count** — the number of CPU cores (`sysctl -n hw.ncpu` on macOS, `nproc` on Linux) divided by the maximum active workers, capped at 8, no less than 2. Used for both `--maxWorkers` and Stryker's `--concurrency`.
5. **Gitignored files** — list them in the main checkout with `git ls-files --others --ignored --exclude-standard`, skipping `node_modules`, build output (`ios/`, `android/`, `.expo/`, `dist/`, `build/`), caches and editor folders. Leave out `.env` files too: tests mustn't depend on them (see Gotchas). Copy whatever configuration is left — often nothing.

### Preflight checks

Run as part of the orchestrator's preflight (`references/preflight.md`), after the tool check in `quality-gates.md`:

- **Node** — the session's Node major version matches the project's. ❌ otherwise: say which version to switch to, and that the orchestrator session has to be restarted under it.
- **Install** — a frozen install succeeds in a scratch worktree of the epic branch (create it with `git worktree add`, run the install command, run the test suite once from the scratch worktree's root, then remove it — the test run may ask the developer's permission, which is fine at preflight). ❌ with the error if either fails: every claim would fail the same way. Report how long the install and the suite took; that's the per-ticket overhead.
- **Gitignored files** — list the files to copy into each new worktree, per item 5 above. Show the list so the developer can spot anything missing or anything that shouldn't be copied.

**Smoke test command**, for preflight's headless smoke test: `node -v && npx jest --version`, from the main checkout. If it fails, check whether the worker's sandbox can run Node.

### Project state

What preflight records for this stack in `project.md`:

- the package manager, its install command, and the Node major version;
- the test, lint, typecheck and format commands;
- the job count;
- the files to copy into each worktree.

### At claim

Once the orchestrator has created a ticket's worktree (or the epic review's):

1. Copy in the files listed in `project.md`.
2. Run the recorded install command for the worktree, alone, from the orchestrator's session (it needs the network, which workers' sandboxes don't allow). If it fails, don't start the worker: report it, and leave the ticket claimed so the next tick retries.

### Worker prompt

The orchestrator puts this block in the worker's prompt, after the list of inputs, filled in from `project.md`:

```markdown
Environment: run every command on the host, from your worktree, with <package manager>. Dependencies are already installed; never install, add or remove packages yourself — a dependency change is a sensitive change for the plan. Node <major> is active.

- Jest: always pass `--cacheDirectory <state dir>/jest-cache --maxWorkers <jobs>`.
- Stryker: pass `--concurrency <jobs>`.
- Commands: test `<test command>`, lint `<lint command>`, typecheck `<typecheck command>`, format `<format command>`.

Never run `expo start`, `expo run`, `expo prebuild`, EAS commands, cache resets, or project recipes that wrap them.
```

### Using it (worker)

- Run each command from the worktree root, with the flags in your prompt.
- If a ticket's approved plan includes a dependency change, park with `agent:needs-input` before making it: the developer adds the package on the branch (`npx expo install <package>` picks the version the SDK expects) and swaps to `agent:answered`.
- Leave `ios/` and `android/` alone: they're generated, and gitignored.

### Cleaning up (orchestrator)

Nothing beyond the orchestrator's own clean-up: `node_modules` and the copied files go with the worktree, and the Jest cache and Stryker files with the ticket's state directory.
