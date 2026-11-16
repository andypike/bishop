# React Native (Expo)

- **ID**: `react-native` — also its Linear label, `stack:react-native`, and its name in a feature document's `Stacks:` line.

Expo-managed React Native apps written in TypeScript, tested with Jest. The app talks to a backend — usually a Rails app in a sibling repo — over its API; backend work is a separate ticket in the backend's own stack.

## Detection

A repo is React Native when its root has both:

- a `package.json` whose `dependencies` include `react-native` (an Expo app also lists `expo`);
- an Expo config: `app.json`, `app.config.ts` or `app.config.js`.

A Rails app with a JavaScript front end has a `package.json` too, but never `react-native` in it.

## Sensitive changes

Changes that need a developer's say-so when the approved plan didn't include them (escalation trigger 4 in `references/escalation.md`), on top of the ones every stack shares:

- adding, removing or upgrading a dependency — any of them can bring native code, which needs a new build rather than an over-the-air update;
- the Expo config (`app.config.*`, `app.json`), config plugins, `eas.json`, `patches/`, or the runtime version policy;
- app permissions: camera, location, notifications, photos, tracking, and their purpose strings;
- the shape of data persisted on the device (stored state, cache keys): a change can wipe or break what existing users have saved;
- the API the app expects from the backend, beyond what the architecture document's API contract says.

## Deployment tasks

What merged work needs to reach users, beyond its JavaScript:

- **A new build** — anything that changes native code or configuration: a new or upgraded dependency with native code, the Expo config or its plugins, permissions, the Expo SDK. One line saying why: `New build: adds expo-camera (native module)`. Without one, the change ships as an over-the-air update.
- **EAS environment variables or secrets** — a new or changed value, the profiles it applies to, and never the value itself: `EAS env: set EXPO_PUBLIC_SUPPORT_URL for staging and production`.
- **Backend first** — when the ticket relies on a backend change, name the backend ticket: `Needs ENG-1234 deployed first`.

Order: `New build` lines first, since they decide how the release goes out; then environment variables; then everything else.

Builds and over-the-air updates stay with the developer, who decides when to make them; agents never run `eas build`, `eas update` or `eas submit`. **Ticket PRs never change build numbers** (`ios.buildNumber`, `android.versionCode`), even when the project's README says to bump them on every PR: tickets merge into one epic in parallel, and every PR would conflict on the same lines. The developer bumps them when they make a build.

In Phase 8, check the list against the diff: any change to `package.json` dependencies, the Expo config, `eas.json` or `patches/` means a `New build` line.

## Architecture

How `references/architecture.md` applies to a React Native feature.

**Style guide sections** — walk these against the feature, and record in the document's **Style guide** section how each one shapes the design:

- **Screens & Navigation** — the new screens, which navigator or stack each belongs to, its route name and params, and how users reach it (including deep links).
- **Components** — which pieces are shared components and which belong to one screen; the shared ones by name.
- **State & Data Fetching** — where the feature's data lives (the project's existing state approach: its store, context or hooks), what's persisted on the device, and which hook or store action fetches what.
- **API & Backend** — the endpoints the app calls, the API types and mappers they need, and the error cases the app handles. When the feature spans the backend too, this is the API contract the backend tickets build against.
- **Styling** — new theme tokens, if any; everything else uses the existing ones.
- **User-facing Copy** — where the feature's strings live (the project's translation file, if it has one).
- **Native & Config** — permissions, native modules, config changes, and whether the feature needs a new build.

**Shared files** — files every ticket may edit, which get a convention instead of an owner: navigation route lists and param types, the API client's index and type files, component barrels (`index.ts`), theme tokens, the translation file, and `app.config.*`.

**Diagrams** — a screen flow `flowchart` of how users move between the feature's screens; a `sequenceDiagram` for any flow that round-trips to the backend or an external service (sign-in, payments, uploads); a `stateDiagram-v2` for anything with a status.

**Example components**, as the document's Components table lists them:

| Component | Layer | Responsibility | Introduced by |
| --- | --- | --- | --- |
| `OrdersScreen` | screen (`Account` stack) | lists the user's orders | ENG-1234 |
| `OrderCard` | shared component | one order's summary | ENG-1234 |
| `useOrders` | hook | fetches and refreshes orders | ENG-1234 |
| `orders` API | API service + mapper | `GET /api/orders` → `Order[]` | ENG-1234 |
