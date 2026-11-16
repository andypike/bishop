---
name: react-native-upgrade
description: Upgrade an Expo / React Native app's dependencies — Expo SDK, React Native, React, and the libraries around them — one SDK hop at a time with a checkpoint commit per hop, using the project's own upgrade history and Bishop's shared gotchas to avoid known breakages, then write an upgrade record. Use when the user wants to upgrade Expo, React Native, or a mobile app's packages, or bring a React Native project up to date.
---

# React Native Upgrade

A staged workflow for taking an Expo / React Native app from its current SDK to a target SDK with every step verified and recorded. It pauses for the developer at the gates marked **Gate**. Follow the phases in order; don't skip ahead.

Every upgrade feeds the next one. Two sources of history, both read before anything changes:

- **The project's own history**: `docs/upgrades/*.md` in the target repo — what broke last time here, what was deferred, which packages are pinned and why.
- **Bishop's shared gotchas**: [`references/react-native-upgrade/gotchas.md`](../../references/react-native-upgrade/gotchas.md) — lessons from every project's upgrades, indexed by SDK version, so a breakage found once is avoided everywhere.

The upgrade record written in Phase 9 follows [`references/react-native-upgrade/upgrade-record-template.md`](../../references/react-native-upgrade/upgrade-record-template.md).

## Phase 1 — Preflight

Establish what this machine can and can't verify before planning around it.

- **Package manager**: from the lockfile (`package-lock.json` → npm, `yarn.lock` → Yarn, `pnpm-lock.yaml` → pnpm, `bun.lock*` → Bun). Use it for every install, audit and script run; never mix managers.
- **Node**: compare `node -v` against `.nvmrc` / `engines`. If they differ, stop and ask the developer to switch (`nvm use`) before going further — installs under the wrong Node produce a different lockfile.
- **Scripts**: read `package.json` scripts and any `justfile` / `Makefile` for the project's check, lint, typecheck, format and test commands. Use those, not generic equivalents.
- **Native tooling**: check for Xcode (`xcodebuild -version`), an iOS simulator runtime (`xcrun simctl list runtimes`), the Android SDK (`$ANDROID_HOME`, `~/Library/Android/sdk`), a JDK, and the EAS CLI.
- **Who runs EAS builds**: ask the developer whether you trigger `eas build` or they do. Default to them.
- **Working tree**: clean, on an up-to-date root branch. Create the upgrade branch: `upgrade/expo-<target>-<YYYY-MM>`, or the developer's naming if the project's history shows a different convention.

**Completion**: a short preflight summary listing package manager, Node version, the commands you'll use, and — explicitly — which platforms can be built locally and which can only be verified on EAS or by the developer. The developer should know from this summary what "verified" will mean for this upgrade.

## Phase 2 — History

Read every file in `docs/upgrades/`, then `gotchas.md` in full.

**Completion**: a list of
- **Deferred work** from the last upgrade record (packages intentionally held back, follow-ups like "rerun the Android build"), each marked as in or out of scope for this cycle.
- **Pins with reasons** (exact versions, `overrides` / `resolutions`, `patches/`), each with whether its reason still holds or needs rechecking now.
- **Applicable gotchas**: every entry in `gotchas.md` whose SDK range overlaps this upgrade's path *and* whose trigger exists in this project (a config key, a library, a code pattern). Grep for each trigger; list the hits.

If `docs/upgrades/` doesn't exist, say so — this upgrade's record will start it.

## Phase 3 — Baseline

Record the state before touching anything, so every later failure can be classified as new or pre-existing:

- The project's check command (format, lint, typecheck) and the full test suite — pass/fail counts and the names of any failures.
- `npx expo-doctor@latest` output.
- The package manager's audit, summarised by severity.
- The outdated list (`npm outdated` / `yarn outdated` / equivalent).
- The latest stable Expo SDK: `npm view expo dist-tags`. `latest` is stable; `next` and `canary` are not targets unless the developer asks.

**Completion**: baseline results written to the scratchpad and summarised in the conversation. A pre-existing failure is fixed separately or explicitly accepted by the developer before Phase 5 — never carried silently into the upgrade, where it becomes indistinguishable from a regression.

## Phase 4 — Plan

Build the upgrade plan as one table and present it:

| Step | Change | Notes / known gotchas |
|---|---|---|
| SDK hop 1 | Expo 54 → 55 (RN, React, `expo-*` follow) | gotchas.md entries that hit at this hop |
| … | | |
| Non-Expo majors | each library outside Expo's pinning, one row each | breaking changes from its changelog |
| Deferred | anything held back, with the reason | |

- **One hop per SDK version.** Never jump several SDKs at once: when something breaks, the hop that broke it must be obvious.
- Packages Expo pins (anything `expo install --fix` manages) move with their SDK hop. Packages outside its control (Firebase, navigation, UI libraries, tooling) are upgraded after the final hop, one per commit.
- Read the Expo SDK changelog and the React Native release notes for every hop now, and list breaking changes that touch this project in the Notes column.
- Large tooling migrations (ESLint flat config, a Prettier major that reformats the codebase) go in a separate PR unless the developer says otherwise — a whole-codebase reformat buries the upgrade diff.

**Gate**: the developer approves the plan, including what's deferred.

## Phase 5 — SDK hops

For each hop, in order:

1. `npx expo install expo@^<N>.0.0`, then `npx expo install --fix`. Review the `package.json` diff before moving on: list what changed, and check every pin from Phase 2 survived or was deliberately moved.
2. Apply the gotchas for this hop from Phase 2's list, and the breaking changes from Phase 4's notes.
3. Run `npx expo-doctor@latest`; resolve what it reports or record why not.
4. Run the check command and the full test suite. Fix one area at a time (types, deprecated APIs, tests), re-running after each. A test failing only after the hop is a regression until proven otherwise — read the cause before changing the test.
5. `npx expo export --platform ios` and `--platform android`. Jest and tsc don't exercise Metro's module resolution, so bundling failures otherwise surface only on EAS.
6. `npx expo prebuild --clean`, then `pod install` in `ios/` and, if the Android SDK exists, `./gradlew :app:assembleDebug` in `android/`. These catch config-plugin and native breakage before app code is the suspect. `ios/` and `android/` stay out of the commit unless the project checks them in.
7. Commit a checkpoint: `Upgrade to Expo SDK <N>`, with the notable fixes in the body.

**Completion per hop**: checks and tests at least as good as baseline, prebuild clean, and a commit. Log each breakage as you fix it — symptom, root cause, fix — for Phase 9; reconstructing these afterwards loses the root causes.

## Phase 6 — Non-Expo majors

Upgrade each remaining library from the plan on its own: read its changelog, upgrade, fix, run checks and tests, commit. If a major turns into a rewrite (e.g. a test library whose API becomes async across hundreds of files), stop and offer the developer a choice: the highest minor that fixes what's needed, or a separate PR.

## Phase 7 — Native verification

Local builds verify far less than they appear to; Android release builds in particular fail on Kotlin/Gradle issues that nothing short of a full compile reveals. So:

- Recommend the developer run an **EAS Android release build** as early as the final hop is committed, not at the end — Android failures tend to come one at a time, each surfacing only after the previous is fixed.
- For each EAS failure the developer pastes, find the root cause before fixing (`npm pack <lib>@<version>` and reading its native source is often the fastest route), check the same pattern in every other native module in `node_modules`, and prefer the narrowest fix: a version pin or a `patch-package` patch to one library beats a project-wide toolchain change (see the Kotlin entry in `gotchas.md`).
- Ask the developer to smoke-test on device/simulator for both platforms, naming the areas this upgrade's changes touched.
- **Store readiness**: from the generated native projects, list the Android `targetSdkVersion` and every `NS*UsageDescription` in `Info.plist`. Check each against `gotchas.md`'s "Store submission" section: the target SDK meets Play's current requirement, every purpose string says what the access is for with an example, and no string declares a feature the app doesn't use. Neither store checks these until submission.

**Completion**: EAS builds green on both platforms, or the outstanding failures recorded as deferred with the developer's agreement.

## Phase 8 — Security

Run the audit and compare with baseline. Fix high/critical findings that have a path into the shipped app (runtime dependencies), using the package manager's mechanism (`overrides` for npm, `resolutions` for Yarn) or an upgrade of the direct parent. For dev/build-only findings, list them as reviewed and accepted with the reason; forcing major versions of build tooling's transitive dependencies can break the toolchain for a vulnerability that never ships. Run tests after each fix; commit.

## Phase 9 — Record

1. Write `docs/upgrades/expo-<N>-<YYYY-MM>.md` from the template. Every breakage from Phase 5–7 gets its symptom, root cause and fix; every pin and deferral its reason.
2. **Feed Bishop**: for each breakage that isn't specific to this project's code — a library, config key, SDK or toolchain behaviour any app could hit — propose an addition or correction to `references/react-native-upgrade/gotchas.md`, in that file's format. Name the project only by its gotchas label from the record (`App A`), never the client's or app's name, and leave out anything that would identify it, such as what the app does. Show the developer the proposed entries; with approval, write them to Bishop on a branch of their choosing.
3. Push the branch and open the PR, its body summarising the record and linking to it. Merging is the developer's.

**Gate**: the developer reviews the record and the gotchas additions.
