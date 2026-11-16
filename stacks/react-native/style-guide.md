# React Native Style Guide

This is the single style guide `bishop` applies to every Expo / React Native project it's used on — not one guide per codebase. It's a living document: tune it whenever a code review surfaces something you'd rather see written differently. As it matures, you should need to review less and less by hand.

Seeded from React's Rules of React (https://react.dev/reference/rules), React Native Testing Library's guiding principles (https://callstack.github.io/react-native-testing-library/), typescript-eslint's recommended rules, and Expo's documentation (https://docs.expo.dev), then shaped by the conventions the team's existing apps already share. Treat everything here as a starting point to argue with, not gospel.

## General guidance

- Prefer readability over complexity.
- Extract variables, functions and hooks where required to improve readability.
- Keep components, hooks and functions small and focused on a single responsibility.

## Working in codebases that don't already follow this

Some projects predate this guide and won't meet it. That's expected — the goal is to raise quality as you go, not to block on a codebase's starting point. When touching existing code:

- New/changed code follows this guide, even if it's locally inconsistent with the surrounding file.
- Don't copy an existing anti-pattern just to "match the file." Matching formatting/naming conventions that are neutral is fine; propagating a real anti-pattern (business logic in a component, an effect that only derives state, a silenced lint rule) is not.
- Architecture is the exception: follow the project's existing choices of state management, data fetching, navigation and styling. Replacing one is a decision for the feature's architecture document, never something a ticket does on its own.

## Code Comments

- Code comments are a smell, not a goal. They should be rare. The code, its names, the tests, and the commit message carry the meaning. A comment is the last resort once none of those can.
- Before writing a comment, prefer these in loose order. There's weight to the order, but it's not absolute. Apply each only where it makes sense, and don't force an earlier one when a later one already tells the story (a manufactured extraction is its own smell):
  1. **Rename** — a clearer function, variable, component or type name that states the intent.
  2. **Extract** — pull a confusing expression into a well-named function or hook that names the concept.
  3. **Test** — let a well-written test tell the story of the behaviour and its edge cases.
  4. **Commit message** — explain the *why* and the history there, not in the source.
- Only then write a comment. Typically when the rationale matters but a commit message is too far removed from the code for someone to find it when they need it — a workaround for a platform bug, say, with a link to the issue.
- **The one exception: props of shared components get a short JSDoc comment each.** They show up in editor hovers wherever the component is used, which is where someone needs them. Keep each to a line, and say what the prop does, not its type.
- Favour explaining *why* over *what*. No narration, no TODO/changelog/decision-log comments, no commented-out code.

## Components

- Function components only. Name them in PascalCase; suffix their props interface with `Props` (`OrderCardProps`) and destructure props in the signature.
- One component per folder: `Name/index.tsx`, its styles in `Name/styles.ts`, and its tests in `Name/Name.test.tsx`. Sub-components that only it uses live in folders inside it.
- **Named exports only.** The exception is `styles.ts`, which default-exports its styles.
- Components render; they don't decide. Business logic, data fetching and calculations go in hooks, helpers or the project's store, so they can be tested without rendering anything.
- Screens are thin: they compose components and hooks, and read their route params. A screen that grows logic is missing a hook.
- Never define a component inside another component: it's recreated on every render, losing its state. Move it out, or to its own folder.
- Long or unbounded lists use `FlatList` / `SectionList`, never `ScrollView` with `map`. List keys are stable IDs, never array indexes.
- Don't export a type or function from a component's file unless something else uses it.

## Hooks & Effects

- Components and hooks are pure: the same props and state always render the same output, and nothing is mutated during render. Never mutate props, state or values from a store directly.
- Call hooks at the top level only — never in conditions, loops or after an early return.
- An effect is for synchronising with something outside React: a subscription, a timer, a native API. If a value can be worked out from props or state, work it out during render instead of storing it with an effect.
- Every effect lists all its dependencies. A missing-dependency warning is fixed, never disabled — usually by moving a function inside the effect or deriving the value differently.
- Clean up what an effect starts: unsubscribe, clear timers, and ignore the result of a request that finishes after the component has gone.
- Use `useCallback` for functions passed to child components and `useMemo` for expensive calculations. Don't wrap everything else: it adds noise without saving anything.
- A custom hook's name starts with `use` and says what it gives you (`useOrders`, not `useOrdersLogic`).

## Screens & Navigation

- Follow the project's navigation setup. New routes go in its route list (usually an enum), with their params typed in the matching param list; screens take the project's typed screen props.
- Navigate through the typed navigation hooks and route names, never string literals.
- Route params carry IDs and small values, not whole objects: the screen loads what it needs, so a deep link or a restored session works the same way.
- Every screen that loads data shows a loading state, an empty state and an error state.

## State & Data Fetching

- Use the project's existing state approach (its store, contexts or hooks). Never add a state management or data fetching library within a ticket.
- Data from the backend and UI state are kept apart: a screen's open/closed or selected state doesn't belong in the store holding API data.
- Anything persisted on the device (stored state, cached responses) has a shape existing users already have saved. Changing that shape needs a plan for their data, and is a sensitive change.

## API & Backend

- Components and hooks never call `fetch` or the HTTP client directly; every request goes through the project's API service layer.
- API types describe the backend's payloads exactly as sent (usually snake_case). A mapper converts each one into the app's own type (camelCase), and the rest of the app only ever sees the app's type.
- Every mapper and API service function has tests, including the failure cases.
- Failures are handled the project's way (a result type, `null`, an error value) and always reach the user as something they can understand or act on — never a silent empty screen.
- Endpoints, payloads and error responses follow the feature's API contract in the architecture document exactly. A mismatch is raised, not worked around.
- Base URLs and other environment values come from the project's config module, never hard-coded.

## TypeScript

- No `any` in new code. Use `unknown` and narrow it, or write the type.
- Write types explicitly where they aren't obvious from the code; let inference handle the rest.
- No non-null assertions (`!`) or casts (`as`) to silence the compiler; fix the type instead. `@ts-expect-error` is the rare exception, with a comment saying why, on the single line that needs it. Never `@ts-ignore`.
- PascalCase for types, interfaces, enums and enum members; camelCase for functions, variables and properties. Use whole words in names.
- Use type aliases to name complex types rather than repeating them.
- Import through the project's path aliases (`@components`, `@hooks`) rather than long relative paths.

## Styling

- Styles live in the component's `styles.ts`, built with `StyleSheet.create`, typed with the project's style type.
- Colours, spacing, font sizes and fonts come from the project's theme tokens. No hard-coded hex values or one-off sizes; if a token is missing, add it to the theme.
- No inline style objects, except for values computed at render time (a width from props, say), merged with the static style.
- Respect the user's accessibility settings: text scales with the system font size, and nothing must depend on an animation finishing — with Reduce Motion on, an entering animation may never run, leaving content invisible.

## Accessibility

- Every touchable has an accessibility role and a label that says what it does, not what it looks like.
- Images that carry meaning have a label; decorative ones are hidden from screen readers.
- Touch targets are at least 44×44 points.

## Native & Config

- Add dependencies with `npx expo install <package>`, which picks the version matching the Expo SDK. A new dependency is a sensitive change.
- Native configuration goes in the Expo config (`app.config.*`) and config plugins. Never edit `ios/` or `android/`: they're generated by prebuild.
- Every permission has a purpose string that says what the app does with the access, with an example — vague ones get the app rejected by Apple.
- Ticket PRs never change build numbers (`ios.buildNumber`, `android.versionCode`); the developer bumps them when making a build.
- Platform differences use `Platform.select` or `.ios.tsx` / `.android.tsx` files, and both platforms' behaviour is tested.

## Security

- Everything in the JavaScript bundle is public, including every `EXPO_PUBLIC_` variable. Never put a secret, a private API key or a credential in the app.
- Tokens and other credentials go in secure storage (the project's secure storage service, built on the Keychain / Keystore), never in AsyncStorage or the persisted store.
- Never log tokens, passwords or personal data, including through analytics events.
- Treat deep link and push notification data as user input: validate it before navigating or acting on it.
- Open external links the way the project does (often an in-app browser helper), and only over HTTPS.

## Testing

- Must use TDD. Write tests first and follow red, green, refactor.
- Test behaviour, not implementation. Structure each test as Arrange, Act, Assert, with a name that says what the user or caller sees.
- Tests sit next to the code they test, as `<name>.test.ts` / `<Name>.test.tsx`.
- Every hook, helper, mapper and API service function has tests for each public behaviour, and every branch in a conditional has at least one test.
- Render tests use React Native Testing Library and query the way a user finds things: by role, label or visible text first (`getByRole`, `getByLabelText`, `getByText`). Use `testID` only when nothing a user perceives identifies the element. A `testID` is a test hook only — never used for styling or logic.
- Follow the project's RNTL version: from v14, `render`, `fireEvent`, `renderHook` and `act` are awaited.
- Mock only the boundaries: the API service layer, native modules, external services (analytics, crash reporting), and navigation hooks. Never mock the project's own UI components or styles. Give components the real context providers they need, with test values.
- Test a screen's loading, empty and error states, not just the happy path.
- Tests must not depend on the developer's machine. A test that reads an environment variable or config value sets it (or mocks the config module) itself; CI has no `.env`. Control time with Jest's fake timers or a date mock, never the real clock.
- No snapshot tests of rendered components: they pin markup instead of behaviour, and get updated without being read. Assert what matters.
- Never test private functions directly. Never mock the thing under test.

## User-facing Copy

- If the project has a translation file, every string a user reads lives there and is fetched with the project's translation helper — in components, hooks, error messages and alerts alike. Keys mirror where they're used (`screens.orders.empty`), so a key is findable from the code and vice versa.
- If the project has no translation file, follow its convention and keep each string in the component that shows it, not scattered through helpers.
- Tests assert the literal text the user sees, not the translation key: a missing key can make both sides of a key-based assertion match.

## Linting

- A lint error or warning is a signal to change the code, not the configuration. Never silence a rule with `eslint-disable` to get a clean run. Editing the ESLint or TypeScript config is a project-wide decision to raise with the developer, not something to do mid-ticket.
- Unused function parameters take an underscore prefix (`_event`), never a disable comment.
- The rare genuine exception gets an inline disable *with* a comment saying why, narrowed to the single line — never a whole file.
- Formatting is Prettier's job. Don't hand-format against it, and don't change its config.

## Quality gate philosophy

There are no fixed numeric thresholds for coverage, TypeScript, ESLint or complexity in this guide — see `references/quality-gates.md` for how baseline-vs-after comparison works instead. This file governs *what good code looks like*; that one governs *how we verify it got better*.
