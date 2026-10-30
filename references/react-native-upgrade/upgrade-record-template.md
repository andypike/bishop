# Upgrade Record Template

The format for `docs/upgrades/expo-<N>-<YYYY-MM>.md` in the target project, written in Phase 9 of `react-native-upgrade`. The next upgrade reads these first, so the reasons behind each fix, pin and deferral matter more than the details of the change.

~~~markdown
# Expo <N> Upgrade — <Month YYYY>

**Branch**: `<branch>`
**Ticket**: <ticket ID, or omit the line>
**Completed**: <YYYY-MM-DD>

## Overview

Upgraded from Expo SDK <from> → <to>, React Native <from> → <to>, React <from> → <to>.
<One paragraph: the route taken (which hops), anything picked up from the previous record's deferred list, and the headline problems.>

---

## Package Changes

### Core

| Package | Before | After |
|---|---|---|
| `expo` | | |
| `react` | | |
| `react-native` | | |
| `typescript` | | |
| `@types/react` | | |
| `jest-expo` | | |

### <Group: Expo packages / Firebase / Navigation / Native modules / Tooling>

| Package | Before | After | Note |
|---|---|---|---|

### Added / Removed

- `<package>` — why.

---

## Breaking Changes & Fixes

### 1. <Short title> (SDK <N>)

**Symptom**: <what was seen: the error text or behaviour, and on which platform>
**Root cause**: <why it happened>
**Fix** ([path](../../path)):

```ts
// Before
// After
```

<Other approaches tried and why they were dropped. Record failed attempts: they are the gotchas the next upgrade most needs.>

---

## Configuration Changes

### app.config.ts
### babel.config.js / metro.config.js / tsconfig.json / jest config

---

## Security Patches

**Fixed**: <package> — <vulnerability>, <how it reaches the shipped app>, <mechanism: override/resolution/upgrade>.
**Accepted**: <packages> — dev/build-only, with the reason.

---

## What Was Left for the Next Upgrade

- <Deferred package or follow-up> — why, and what to check next time.
- <Verification not done (e.g. a platform not built), and who is doing it.>
- <Pins and patches to recheck upstream.>
~~~
