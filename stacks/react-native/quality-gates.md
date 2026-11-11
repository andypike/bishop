# React Native Quality Gates

The React Native tools, commands, and how to read each one's output. How the gate is judged — baseline vs after, when each check runs, experimental checks, and knowing a run has finished — is in [`references/quality-gates.md`](../../references/quality-gates.md); read that first.

**Commands below use `npx` for readability.** Run them as [`environment.md`](./environment.md) says: on the host, from the repo root, with the project's package manager (`yarn jest`, `npx jest`, …), and in auto mode with the Jest and Stryker flags from your prompt. Where the project has its own script for a check (`yarn lint`, `just check`), use the paths it covers, but run the tool directly when you need JSON output.

## Checks

| Check | Kind | Recorded | Clean when |
|---|---|---|---|
| Tests: Jest (`jest-expo` preset) with React Native Testing Library | must pass | test count, pass/fail, line coverage % | the full suite is green |
| TypeScript: `tsc --noEmit` | baseline-compared | error count | no more errors than the baseline |
| ESLint | baseline-compared | error count, warning count | no more errors, and no more warnings, than the baseline |
| Prettier | baseline-compared | files needing formatting | no more than the baseline; every changed file is formatted |
| Complexity: ESLint's complexity rules | baseline-compared, **experimental** | violation count | no more than the baseline |
| Stryker | mutation, scoped to the diff, **experimental** | mutation score, survivors | every meaningful survivor is killed; equivalent mutants are recorded as such |

## Metrics

The lines the quality metrics take in the final Linear comment and the PR body, each baseline → after:

```markdown
- Tests: <tests, pass/fail, coverage>
- TypeScript: <errors>
- ESLint: <errors> errors, <warnings> warnings
- Prettier: <files needing formatting>
- Complexity (experimental): <violations>
- Mutation score (experimental): <score>, <survivors> survivors, <duration>
```

## Preflight check

Run as part of the orchestrator's preflight (`references/preflight.md`), before the checks in `environment.md`:

- **Test and quality tools** — `package.json` includes `jest` with the `jest-expo` preset, `@testing-library/react-native`, `typescript`, `eslint` and `prettier`. ❌ for each one missing, giving the developer two ways forward: add it, or skip that tool for this project. Jest can't be skipped. The complexity check needs nothing installed: it uses ESLint's built-in rules.
- **Stryker** — installed in the plugin's tools folder, not the project (see "Stryker" below). 🔧 If `~/.bishop/tools/stryker/node_modules/.bin/stryker` is missing, install it with the command there. If the install fails, ⚠️: mutation testing is reported as not run until it's installed.

## Tool detection (Investigation phase)

Check the project for:

- Jest and its config (`jest.config.js` or `jest` in `package.json`), the `jest-expo` preset, and React Native Testing Library. Note the RNTL major version: from v14, `render`, `renderHook`, `fireEvent` and `act` are async and must be awaited.
- TypeScript (`tsconfig.json`), and whether `strict` is on.
- ESLint (`eslint.config.*` flat config, or `.eslintrc*`) and its major version, and Prettier (`.prettierrc*`).
- Stryker: installed in `~/.bishop/tools/stryker` (see "Stryker" below), never in the project.

If ESLint or Prettier is missing, **stop and ask** the developer before adding it as a dev dependency — don't silently change `package.json`. If Stryker isn't installed, give the developer the install command below; it's experimental, so skipping it is a reasonable answer.

## Baseline capture (kicked off in background during Investigation/Q&A)

Run against the unchanged codebase, in parallel with the Q&A conversation:

- **Tests + coverage**: `npx jest --ci --coverage --coverageReporters=json-summary --coverageReporters=text-summary --collectCoverageFrom='app/**/*.{ts,tsx}'` (adjust the glob to where the source lives). Record the test count, pass/fail, and line coverage from `coverage/coverage-summary.json`. Passing `--collectCoverageFrom` makes coverage count untested files too, so it's comparable before and after. Write coverage outside the repo with `--coverageDirectory`: `<state dir>/coverage` in auto mode, plus the flags from your prompt; `$TMPDIR/coverage` otherwise.
- **TypeScript**: `npx tsc --noEmit -p .` — record the number of `error TS` lines (0 on a healthy project).
- **ESLint**: the lint script's paths, with `--format json` (ESLint 8 also needs the script's `--ext`): `npx eslint App.tsx app --format json`. Record the total `errorCount` and `warningCount`.
- **Prettier**: the format script's glob with `--list-different`: `npx prettier "app/**/*.{js,jsx,json,md,ts,tsx}" --list-different`. Record how many files it lists.
- **Complexity (experimental)**: see below.

Mutation testing is **not** part of the baseline — there's no diff yet to mutate against.

## After implementation (Quality gate phase)

- **Tests**: the full suite must be green; record coverage the same way.
- **Prettier autofix**: `npx prettier --write <changed files>`, then the baseline's `--list-different` again. Every changed file must be formatted.
- **ESLint autofix**: `npx eslint --fix <changed files>`, then the baseline's JSON run. `--fix` applies the rules' automatic fixes, never their suggestions; whatever remains is reported. Neither count may exceed the baseline.
- **TypeScript**: the same `tsc` run; no more errors than the baseline.
- **Complexity** and **Stryker**: below.
- **Style guide checklist**: walk the changed files against [`style-guide.md`](./style-guide.md).

### Complexity (experimental)

Measures how hard the code is to follow, as RubyCritic does for Rails, using ESLint's built-in rules — so it needs nothing installed and leaves the project's config alone. Run ESLint a second time with only these rules switched on, on top of the project's config:

```bash
npx eslint App.tsx app --format json \
  --ignore-pattern '**/*.test.ts' --ignore-pattern '**/*.test.tsx' \
  --rule 'complexity: [warn, 10]' \
  --rule 'max-depth: [warn, 4]' \
  --rule 'max-params: [warn, 4]' \
  --rule 'max-lines-per-function: [warn, {max: 80, skipBlankLines: true, skipComments: true}]'
```

Test files are left out: nested `describe` / `it` / `act` callbacks and long `describe` blocks are how Jest tests are written, and on a real app they were three quarters of the violations. Count only the messages whose `ruleId` is one of those four; the project's own lint results are the ESLint check's business. Record the total, and list the violations in files this ticket changed. A new violation in a function this ticket wrote is worth fixing even when the total hasn't gone up; one in untouched code isn't this ticket's job.

The thresholds are a first guess, still being tuned. Note any violation that looks wrong (a long but simple screen component tripping `max-lines-per-function`, say) so the thresholds can be adjusted.

### Stryker (experimental mutation testing)

Scoped to only the files/lines changed for this ticket, since we care about coverage of the change, not the whole file history.

**Installed outside the project, once per machine.** Stryker isn't added to the project's `package.json`. Projects often pin shared packages with `resolutions` / `overrides` for security (`ajv` below 7, `@babel/core` below 8, for example), and Stryker installed into such a project gets the pinned versions and fails to start. Installed in its own folder it keeps its own dependencies, and still runs the project's own Jest and config. TypeScript is installed beside it because Stryker reads the project's `tsconfig.json`:

```bash
npm install --prefix ~/.bishop/tools/stryker @stryker-mutator/core@10.1.1 @stryker-mutator/jest-runner@10.1.1 typescript
```

Write a Stryker config for the run outside the repo — the ticket's state directory in auto mode, `$TMPDIR` otherwise — so nothing in the project changes:

```json
{
  "testRunner": "jest",
  "jest": { "projectType": "custom", "configFile": "jest.config.js", "enableFindRelatedTests": true },
  "coverageAnalysis": "off",
  "reporters": ["json", "clear-text"],
  "jsonReporter": { "fileName": "<state dir>/stryker-report.json" },
  "incremental": true,
  "incrementalFile": "<state dir>/stryker-incremental.json",
  "timeoutMS": 60000,
  "concurrency": <jobs>
}
```

`coverageAnalysis` is `off` because Stryker's per-test coverage wraps Jest's test environment, and Expo's lazily loaded globals then fail every suite at teardown (`You are trying to require a file outside of the scope of the test code`). With it off, `enableFindRelatedTests` still limits each mutant to the tests related to the file.

Then run it from the repo root, with one `--mutate` entry per changed range, and delete its temporary folder afterwards:

```bash
~/.bishop/tools/stryker/node_modules/.bin/stryker run <config file> --mutate 'app/hooks/useOrders.ts:12-48,app/helpers/price.ts:5-30'
rm -rf .stryker-tmp
```

Stryker copies the project into `.stryker-tmp/` while it runs. It removes the copies after a run that finishes, but not after one that crashes, and the folder isn't gitignored: delete it every time, and never commit it.

- **Ranges enclose whole functions**: widen each diff hunk to the function, hook or component it's in, as with Evilution for Rails.
- **Leave out `styles.ts` files and copy files**: mutating style values and strings produces survivors no test should catch. Mutate logic: hooks, helpers, mappers, stores, services, and components' behaviour.
- **Read the JSON report**: each file's mutants and their `status` — `Killed`, `Survived`, `NoCoverage`, `Timeout`, `RuntimeError`, `CompileError`. `Survived` and `NoCoverage` are gaps to judge, as for Evilution: kill each meaningful one with a test, or record why it's equivalent.
- **Run it strictly alone**: no other check alongside it.
- **Re-running after killing survivors**: run the same command again; `incremental` skips mutants whose code and tests haven't changed.
- **Record** the score, survivor count, duration and concurrency for every run. These are being tuned. For scale, on a real app (2026-11-11) a 50-line function produced 83 mutants and took 109s at `concurrency 4`, running about 150 related tests per mutant; the same command again, with nothing changed, reused every result and took 11s.

If Stryker can't run (it fails to start, every mutant errors, or `total` is 0), that's a tool problem, not a quality failure — record what happened and what you tried, report mutation testing as not run, and carry on. Note any config change that made it work, so it can be written up here.
