# React Native Upgrade Gotchas

Breakages found in past upgrades that any Expo / React Native app could hit. Read by the `react-native-upgrade` skill in Phase 2; added to in Phase 9.

Each entry has:

- **SDK**: the Expo SDK hop (or RN/library version) where it bites.
- **Trigger**: what to grep for in a project to know the entry applies.
- **Symptom → cause → fix.**
- **Seen in**: the project and upgrade record it came from, so the full story can be read there.

An entry describes behaviour of a library, config key, SDK or toolchain, never one app's code. When a later upgrade shows an entry is fixed upstream or wrong, correct or delete it rather than adding a contradicting one.

---

## Architecture

### Reanimated 4 requires the New Architecture
- **SDK**: 54
- **Trigger**: `newArchEnabled: false` in app config; `react-native-reanimated/plugin` in `babel.config.js`.
- **Symptom**: `expo install --fix` recommends Reanimated 4.x, which only runs on the New Architecture.
- **Fix**: `newArchEnabled: true`; add `react-native-worklets` (Reanimated 4's peer dependency, version from `expo install`); change the Babel plugin to `react-native-worklets/plugin`. Going straight to the New Architecture at SDK 54 rather than delaying it is recommended: SDK 55 removes the Legacy Architecture anyway, and in Pitstop it also cleared a map performance regression seen on the Legacy Architecture.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #1–2.

### `newArchEnabled` is ignored
- **SDK**: 55
- **Trigger**: `newArchEnabled` in app config.
- **Fix**: remove it. The Legacy Architecture is gone and the key is silently ignored.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #8; ICS Pro Coach, `expo-58-2026-10.md` config changes.

`react-native-worklets` warns about an unmet peer dependency on `@react-native/metro-config`. It's harmless when Metro config comes from `expo/metro-config`.

---

## App config and plugins

### Top-level `notification` removed
- **SDK**: 55
- **Trigger**: `notification:` at the top level of `app.config.ts` / `app.json`.
- **Symptom**: TypeScript error `'notification' does not exist in type 'ExpoConfig'`.
- **Fix**: move `icon` / `color` into the plugin: `["expo-notifications", { icon, color }]`.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #7; ICS Pro Coach, `expo-58-2026-10.md` config changes.

### Plugins that need an explicit `plugins` entry
- **SDK 53**: `@react-native-community/datetimepicker`, `expo-tracking-transparency`.
- **SDK 55**: `expo-image`, `expo-web-browser`.
- **SDK 56**: `expo-status-bar`.
- **Trigger**: the package in `dependencies` but not in `plugins`. `expo-doctor` usually reports these too.
- **Seen in**: Pitstop, `expo-53-2026-03.md` config changes; `expo-57-2026-07.md` #9. ICS Pro Coach, `expo-58-2026-10.md` config changes.

### Legacy Google Maps config breaks `pod install`
- **SDK**: 55 (`react-native-maps` ≥ 1.22)
- **Trigger**: `ios.config.googleMapsApiKey` or `android.config.googleMaps` in app config, with `react-native-maps`.
- **Symptom**: `pod install` fails with `No podspec found for 'react-native-google-maps'`.
- **Cause**: Expo's built-in `withMaps` hardcodes a pod name that `react-native-maps` renamed to a `react-native-maps/Google` subspec ([react-native-maps#5710](https://github.com/react-native-maps/react-native-maps/issues/5710)).
- **Fix**: remove the legacy keys and use the library's plugin: `["react-native-maps", { iosGoogleMapsApiKey, androidGoogleMapsApiKey }]`.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #6.

### `@expo/metro-config` is a sub-export of `expo`
- **SDK**: 53
- **Trigger**: `@expo/metro-config` in `metro.config.js` or `package.json`.
- **Fix**: import from `expo/metro-config` and remove the package.
- **Seen in**: Pitstop, `expo-53-2026-03.md`.

### Packages Expo used to hoist must become direct dependencies
- **SDK**: 55–56
- **Trigger**: `babel-preset-expo` named in `babel.config.js`, or the `expo-font` plugin in app config, without the package in `package.json`.
- **Symptom**: Jest fails with `Cannot find module 'babel-preset-expo'`. Prebuild fails with `PluginError: Failed to resolve plugin for module expo-font`. tsc fails with missing types from `expo-modules-core`.
- **Cause**: after an SDK hop, npm nests these under `node_modules/expo/node_modules`. They had only resolved because npm happened to hoist them. The placement is baked into the lockfile, so a clean install reproduces it.
- **Fix**: `npx expo install babel-preset-expo expo-font`. For anything else that's nested, run `npm dedupe` and delete the stale `node_modules/expo/node_modules/*` lockfile entries before reinstalling.
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #2, #4.

### `expo install --fix` needs a second pass
- **SDK**: 55–58
- **Symptom**: after `expo install expo@^N` and one `--fix`, dev dependencies (`jest-expo`, `@types/react`, `babel-preset-expo`) are still on the previous SDK.
- **Fix**: run `npx expo install --fix` again until it reports nothing. `expo install expo@^N` also writes a caret range; change it to `~`.
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` other notes.

### React Native Firebase ≤26 skips `FirebaseApp.configure()` on SDK 58
- **SDK**: 58
- **Trigger**: `@react-native-firebase/app` below 27.
- **Symptom**: no build error. The plugin doesn't recognise SDK 58's scene-based `AppDelegate` (`return super.application(...)`), so it silently leaves out `FirebaseApp.configure()`.
- **Fix**: React Native Firebase ^27, which installs Firebase's iOS SDK with Swift Package Manager and needs `expo-build-properties` `ios.useFrameworks: "dynamic"`. After prebuild, check that `FirebaseApp.configure()` is in the `AppDelegate`. Dynamic frameworks then expose pods with incomplete podspecs (see "iOS native builds").
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #6.

### SDK 58 default behaviour changes
- **SDK**: 58
- **expo-notifications**: notifications that arrive while the app is open are now shown unless `setNotificationHandler` returns otherwise. To keep the old silent behaviour, set a handler that returns `false` for `shouldShowBanner`, `shouldShowList`, `shouldPlaySound` and `shouldSetBadge`.
- **R8**: the Android template now sets `android.enableMinifyInReleaseBuilds=true`. To keep it off until it's been tested, set `expo-build-properties` `android.enableMinifyInReleaseBuilds: false`.
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #12.

### RN 0.88 needs Metro package exports
- **SDK**: 58 (RN 0.88)
- **Trigger**: `unstable_enablePackageExports = false` in `metro.config.js`.
- **Symptom**: bundling fails with `Unable to resolve module react-native/react-private-interface`, then `@react-native/asset-utils`. Jest and tsc pass; only Metro fails.
- **Fix**: remove the override. A custom `resolveRequest` for `react-native` alone isn't enough, because `@react-native/*` needs exports too. Run `npx expo export` for both platforms after every hop to catch Metro resolution failures before EAS does.
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #10.

### Smaller config notes
- `android.useLegacyPackaging: false` enables 16 KB page alignment (Play Store requirement for new native libraries). Added at SDK 53.
- `expo-doctor` prefers `.expo/` over `.expo/*` in `.gitignore`.
- `expo-doctor`'s React Native Directory check reports false positives for maintained but unlisted packages. Silence them per package with `expo.doctor.reactNativeDirectoryCheck.exclude` in `package.json`, not by turning the check off.

---

## Library APIs

### `expo-localization`: `locale` / `isRTL` crash on Android
- **SDK**: 53
- **Trigger**: `Localization.locale`, `Localization.isRTL`.
- **Symptom**: iOS fine; Android crashes at startup.
- **Fix**: `const first = Localization.getLocales()[0]`, then `first?.languageTag ?? "en"` and `first?.textDirection === "rtl"`.
- **Seen in**: Pitstop, `expo-53-2026-03.md` #1.

### `expo-notifications`: new required handler fields
- **SDK**: 53
- **Trigger**: `setNotificationHandler`.
- **Fix**: return `shouldShowBanner` and `shouldShowList` alongside the existing fields.
- **Seen in**: Pitstop, `expo-53-2026-03.md` #5.

### `expo-notifications`: `removeNotificationSubscription` removed
- **SDK**: 54
- **Trigger**: `removeNotificationSubscription`.
- **Fix**: call `.remove()` on the subscription returned by `add…Listener`.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #3.

### React 19 types
- **SDK**: 53 (React 19, `@types/react` 19)
- **Trigger**: `useRef<T>()` with no initial value, `RefObject<T>`, `NodeRequire` for image requires, a bare `JSX` type.
- **Fix**: `useRef<T | null>(null)`; `RefObject<T | null>`; `number` for `require()`d images; `import { type JSX } from "react"`.
- **Seen in**: Pitstop, `expo-53-2026-03.md` #4.

### `react-native-maps`: iOS polyline colour and Android marker size
- **SDK**: 53 (`react-native-maps` 1.20)
- **Symptom**: with `PROVIDER_GOOGLE`, `strokeColor` is ignored on iOS (the route renders blue), and `Marker icon=` renders oversized on Android.
- **Fix**: pass `strokeColors={[colour]}` (the array form reaches `GMSStyleSpan`), and render the marker image as a child `<Image>` with an explicit size. `react-native-maps-routes` can't pass `strokeColors` through, so Pitstop replaced it with `react-native-maps-directions`.
- **Seen in**: Pitstop, `expo-53-2026-03.md` #2–3.

### React Native and Jest API removals
- **RN 0.85 (SDK 56)**: `StyleSheet.absoluteFillObject` removed; use `absoluteFill`.
- **RN 0.88 (SDK 58)**: `StatusBar` `backgroundColor` and `translucent` removed. Both did nothing under the edge-to-edge mode that's mandatory since SDK 55, so drop them.
- **Jest 30 (SDK 58)**: `toBeCalledWith` and the other `toBe…` aliases removed; use `toHaveBeenCalledWith` etc. Snapshot files are rewritten for a new header link.
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #5.

### iOS: variable fonts tie with their sibling fonts
- **Trigger**: a variable font (`fvar` table) bundled through `expo-font` that shares a family name with other bundled fonts or its own named versions. The tell is a filename such as `*_Medium-LC.ttf` alongside static files of the same family.
- **Symptom**: upright text draws with the wrong version of the font, for example high contrast instead of normal contrast. It differs by iOS version: iOS 27 differs from 26.
- **Cause**: React Native on iOS doesn't use the exact font it's given. It takes that font's family and picks the closest-weight face whose italic setting matches the text style. Apple doesn't mark a variable font's versions as italic, so versions with the same weight tie, and React Native takes whichever iOS lists first. This code is unchanged from RN 0.81 to 0.88.
- **Fix**: on iOS, set `fontVariationSettings` (supported from RN 0.88) to pin every axis, e.g. `"'wght' 600, 'CNTR' 0, 'ital' 0"`. To list a font's axes and named versions, load it with CoreText: a short Swift script calling `CTFontManagerRegisterFontsForURL` and then `NSFontManager.availableMembers(ofFontFamily:)`.
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #14.

---

## Testing

### `@testing-library/react-hooks` deprecated
- **Trigger**: `@testing-library/react-hooks` in `package.json`.
- **Fix**: import `renderHook` and `waitFor` from `@testing-library/react-native`; replace `waitForNextUpdate()` / `waitForValueToChange()` with `waitFor(() => expect(…))`.
- **Seen in**: Pitstop, `expo-53-2026-03.md` #6.

### RNTL 12 can't render under the New Architecture with React 19
- **SDK**: 54
- **Trigger**: `@testing-library/react-native` 12.x.
- **Symptom**: every `render()` fails with `Element type is invalid: expected a string … but got: object` from `detectHostComponentNames`.
- **Fix**: upgrade to `^13.3`. Stop at 13 unless you want a separate migration (see RNTL 14 below), since 14 touches every test file. 13 also infers `renderHook` prop types more strictly, so an `initialProps` callback may need a parameter annotation.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #4.

### RNTL 14: async APIs and React Native's text rule
- **Trigger**: `@testing-library/react-native` 14.x (React 19+, RN 0.78+, Node ^22.13 or 24+).
- **Dependencies**: remove `react-test-renderer` (and any `overrides` entry for it) and `@types/react-test-renderer`; add `test-renderer` on the line matching the React minor (`~1.3` for React 19.3). Import `TestInstance` from `test-renderer` in place of `ReactTestInstance`.
- **Async**: `render`, `renderHook`, `rerender`, `unmount`, `fireEvent` and `act` return promises. The `rntl-v14-async-functions` codemod adds the awaits, but doesn't follow helpers defined in test files; pass them with `--param customRenderFunctions=…`. It downloads and runs code from the codemod registry, so if that's not allowed, a TypeScript-compiler script that adds `await` and marks the enclosing function `async` does the same job. Check by hand anything that lands in an `async` callback of `forEach` or `expect(() => …)`, where nothing waits for the promise.
- **Symptom**: after the awaits, tests asserting a brief loading state fail (`expected true, received false` on `loading`, or `queryByText("Loading: true")` is null).
- **Cause**: awaiting `render` flushes resolved mocks before returning, so the request has already finished. Under v13 these assertions only passed because they ran before it did.
- **Fix**: for tests about the in-flight state, hold the mock open: `mockReturnValue(new Promise(() => {}))`, or keep the `resolve` and call it after the loading assertion. Otherwise assert the settled state.
- **Symptom**: `Invariant Violation: Text strings must be rendered within a <Text> component`, from test components and mocks that render bare strings (e.g. `jest.fn(() => <View>Icon</View>)`, or a stray `;` after a closing JSX tag).
- **Fix**: wrap the text in `<Text>`, or make icon mocks text-free (`<View testID="…" />`) so their text doesn't collide with `getByText` regexes. The check is always on and matches device behaviour.
- **Also**: snapshots with several root elements print as a fragment (`<>…</>`) instead of an array; update them once that's confirmed as the only difference.
- **Seen in**: ICS Pro Coach, PR #772 (follow-up to `expo-58-2026-10.md`).

### `waitFor(() => value)` doesn't wait
- **Trigger**: `waitFor(() => ` with a callback that returns a value instead of asserting.
- **Symptom**: intermittent failures after an RNTL bump. State hasn't settled, or mock call counts are stale.
- **Cause**: `waitFor` only retries while the callback throws, so returning `false` counts as a pass on the first check. Older timing hid this latent bug.
- **Fix**: `waitFor(() => expect(value).toBe(true))`. Under fake timers each retry advances the clock, so assertions on exact `Date.now()`-derived values should flush with `act(async () => {})` instead.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #5.

### `@react-native/jest-preset` no longer bundled
- **SDK**: 56
- **Symptom**: `jest-expo` warns about an unmet peer `@react-native/jest-preset`.
- **Fix**: add it as a devDependency pinned to the exact installed `react-native` version. Re-pin it at every hop; otherwise npm warns ERESOLVE about overriding a peer dependency.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #10; ICS Pro Coach, `expo-58-2026-10.md` other notes.

### Worklets 0.7+ needs an explicit Jest mock
- **SDK**: 55
- **Trigger**: `react-native-reanimated` 4, directly or through `@gorhom/bottom-sheet`.
- **Symptom**: `[Worklets] Native part of Worklets doesn't seem to be initialized`.
- **Fix**: `jest.mock("react-native-worklets", () => require("react-native-worklets/src/mock"))` in the Jest setup file.
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #1.

### Reanimated needs its Jest resolver
- **SDK**: 58
- **Symptom**: ``[Reanimated] `setCSSEventHandler` is not available in JSReanimated``.
- **Cause**: jest-expo resolves `.native.ts` files, so Reanimated's native initialisers run against the mocked worklets module. `react-native-reanimated/mock` goes down the same path.
- **Fix**: `resolver: "react-native-reanimated/jest/resolver"` in the Jest config, together with the worklets mock above. The resolver on its own fails with `getUIRuntimeHolder is not supported on web`.
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #7.

### `react-native-date-picker` 5 needs its native module in Jest
- **Trigger**: `react-native-date-picker` 5 with `modal`.
- **Symptom**: `Invariant Violation: new NativeEventEmitter() requires a non-null argument`.
- **Fix**: stub `NativeModules.RNDatePicker` with `openPicker`, `closePicker`, `addListener` and `removeListeners` as `jest.fn()`s in the setup file.
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #11.

---

## TypeScript

### TS 6: `baseUrl` deprecated, and removing it drops ambient `@types`
- **SDK**: 56 (TypeScript 6.0.3 arrives with SDK 56's `expo install --fix`)
- **Trigger**: `baseUrl` in `tsconfig.json`.
- **Symptom**: a deprecation warning. Once `baseUrl` is removed, test files report hundreds of `Cannot find name 'describe' / 'expect'` errors.
- **Fix**: remove `baseUrl`; prefix every `paths` entry with `./`; add `"types": ["jest", "node"]`; convert any bare imports that resolved through `baseUrl` (e.g. `app/foo`) to an alias or a relative path. `@typescript-eslint/*` below 8.72 declares a `typescript <6.0.0` peer dependency, so npm fails with ERESOLVE; bump it to `^8.72.1`, which still supports ESLint 8.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #16; ICS Pro Coach, `expo-58-2026-10.md` #3.

### RN 0.87 strict TypeScript API
- **SDK**: 58 (RN 0.87+)
- **Trigger**: `StyleSheet.create<Style>` with an `interface Style`; typed `ScrollView` / `FlatList` refs; deep imports of types such as `ViewToken`.
- **Symptom**: a large number of `TS2344 Type 'Style' does not satisfy the constraint '____Styles_Internal'` errors, about 180 in one app. Interfaces don't get implicit index signatures.
- **Fix**: to defer the migration, add `"customConditions": ["react-native", "react-native-legacy-deep-imports"]` to `tsconfig.json`. React Native removes this opt-out after 0.89. The real fix is a `type` alias or `satisfies` for style types; do it as a separate PR.
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` config changes (tsconfig.json) and "What Was Left".

---

## Android native builds

These failures only show up in a full Android compile, which usually means EAS. They tend to arrive one at a time, each hidden behind the previous one. After fixing one, grep every native module in `node_modules` for the same pattern.

### RN 0.86: `MapBuilder.build()` returns a read-only `Map`
- **SDK**: 57 (RN 0.86)
- **Trigger**: `grep -rl "MapBuilder" node_modules/*/android node_modules/@*/*/android`, in Kotlin files that declare a `MutableMap` return.
- **Symptom**: `Return type mismatch: expected 'MutableMap<String, Any>?', actual 'Map<String, Any>'`.
- **Fix**: `patch-package` the library, appending `.toMutableMap()`. Known affected: `react-native-blurhash` ≤ 2.1.3 (no upstream fix as of 2026-07).
- **Seen in**: Pitstop, `expo-57-2026-07.md` #11.

### RN 0.86: bare `currentActivity` unresolved
- **SDK**: 57 (RN 0.86)
- **Trigger**: unqualified `currentActivity` in a Kotlin module extending `ReactContextBaseJavaModule`.
- **Symptom**: `Unresolved reference 'currentActivity'`, often followed by `runOnUiThread` errors.
- **Cause**: the base class was rewritten in Kotlin, so the Java getter-as-property interop no longer applies.
- **Fix**: upgrade to a version that qualifies it (`reactApplicationContext.currentActivity`), or patch the library. Known affected: `react-native-google-mobile-ads` < 16.4. Check the next entry before choosing a version.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #12.

### Kotlin metadata mismatch: pin the library, not the toolchain
- **Trigger**: `Module was compiled with an incompatible version of Kotlin. The binary version of its metadata is X, expected version is Y`.
- **Cause**: a library ships an AAR compiled with a newer Kotlin than the SDK's default (e.g. `play-services-ads` 25.x needs Kotlin 2.3; SDK 57 defaults to 2.1.20).
- **Fix**: pin the library to the last version that bundles an older dependency (e.g. `react-native-google-mobile-ads` exactly `16.0.0` → `play-services-ads` 24.6.0). Raising `android.kotlinVersion` project-wide through `expo-build-properties` looks like it works, but it breaks modules that apply the Kotlin plugin the legacy way (`lottie-react-native`), because they still compile with an older compiler against the new stdlib.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #13.

### `compileSdk` 36
- **Symptom**: `Dependency 'androidx.core:core:1.18.0' requires … compile against version 36 or later`.
- **Fix**: set `compileSdkVersion: 36` and `buildToolsVersion: "36.0.0"` through `expo-build-properties`. For `targetSdkVersion`, see "Play Store target API level" under Store submission.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #14.

### Autolinking drops imports for libraries that register several packages
- **SDK**: 57 (RN 0.86; [facebook/react-native#55653](https://github.com/facebook/react-native/issues/55653))
- **Trigger**: a library whose `react-native.config.js` registers more than one package.
- **Symptom**: `PackageList.java: error: cannot find symbol new <SecondPackage>()`.
- **Fix**: `patch-package` the library's `react-native.config.js` so it registers only the packages the app uses. Known affected: `react-native-appsflyer` (`PCAppsFlyerPackage`, the optional Purchase Connector). Recheck upstream before each upgrade, since the patch may no longer be needed.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #15.

### AGP 9 rejects `proguard-android.txt`
- **SDK**: 58 (RN 0.88, AGP 9, Gradle 9.4)
- **Trigger**: `grep -rl "proguard-android.txt" node_modules/*/android node_modules/@*/*/android`.
- **Symptom**: `getDefaultProguardFile('proguard-android.txt') is no longer supported since it includes -dontoptimize`. It fails even with minification off, because the release `buildType` is still evaluated.
- **Fix**: upgrade the library, or `patch-package` it to use `proguard-android-optimize.txt`. Known affected: `react-native-blob-util` < 0.24.12 (fixed upstream) and `react-native-date-picker` ≤ 5.0.13 (unfixed as of 2026-10).
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #9.

---

## iOS native builds

Local Xcode often can't build the newest SDK (SDK 56+ needs Xcode ≥ 26.4), so these may only show up on EAS.

### Dynamic frameworks expose pods with missing system frameworks
- **Trigger**: `useFrameworks: "dynamic"`, which React Native Firebase 27+ requires.
- **Symptom**: `Undefined symbols for architecture arm64: _<Symbol>` in one pod's target, followed by an `ld` failure.
- **Cause**: with dynamic frameworks every pod links as its own library and must declare every system framework it uses. Static linking hid these omissions, because the app's final link supplied the frameworks. A quoted `#import "X/X.h"` in a `.mm` file doesn't trigger clang's automatic linking.
- **Fix**: `patch-package` the podspec to add the framework to `s.frameworks`. Check it with `pod install` and the pod's `.xcconfig` linker flags (`OTHER_LDFLAGS`). Known affected: `react-native-image-picker` 8.x (`UniformTypeIdentifiers` for `UTTypeImage`; unfixed in 8.3.1).
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #13.

---

## Store submission

Neither store checks these at build time, so they show up as rejections after EAS has gone green. Check the generated `ios/*/Info.plist` and Android Gradle config from `npx expo prebuild --clean`, not just app config: config plugins add purpose strings and permissions of their own.

### Play Store target API level
- **Trigger**: `targetSdkVersion` in `expo-build-properties`. An explicit pin overrides React Native's default and is left behind when the SDK moves on.
- **Symptom**: Play Console rejects the upload for targeting an old API level. Each August, Play requires new apps and updates to target the previous year's Android release: API 36 (Android 16) from August 2026.
- **Fix**: remove the pin so RN's default applies (36 from RN 0.86), or raise it. A higher target turns on that Android version's behaviour changes (for 36: enforced edge-to-edge, predictive back), so smoke-test on it.
- **Seen in**: Pitstop, `expo-57-2026-07.md` #14 (pinned to 35, rejected); ICS Pro Coach, `expo-58-2026-10.md` #15 (default 36, no change).

### App Review rejects vague purpose strings
- **Trigger**: every `NS*UsageDescription` in the generated `Info.plist`, including plugin defaults such as "Allow $(PRODUCT_NAME) to use your location." and hand-written ones such as "This app requires access to the camera".
- **Symptom**: rejected under guideline 5.1.1, because the purpose string doesn't clearly explain why the app needs the data.
- **Fix**: say what the app does with the access and give an example, e.g. "Pitstop uses your location to show nearby garages on the map… For example, we use it to sort garages by how far away they are from you."
- **Seen in**: Pitstop (`4b76e21`); ICS Pro Coach, `expo-58-2026-10.md` #15.

### Plugins declare features the app doesn't use
- **Trigger**: `expo-location` (adds Always location and motion strings by default), `expo-secure-store` (adds a Face ID string by default), and any other plugin built on `createPermissionsPlugin`.
- **Symptom**: App Review rejects the app for requesting access to features it doesn't offer, typically right after an SDK bump changes a plugin's defaults.
- **Fix**: set each unused option to `false` (e.g. `locationAlwaysPermission: false`, `faceIDPermission: false`) and check it's gone from the generated `Info.plist`. But keep any string whose API the compiled binary still references, even if the app never calls it. `expo-location`'s iOS code uses `CMMotionActivityManager`, and Pitstop was rejected again after setting `motionUsagePermission: false`, until the string was restored.
- **Seen in**: Pitstop (`4e19b51`, `ffc51f2`); ICS Pro Coach, `expo-58-2026-10.md` #15.

---

## Package manager

### npm 11.6.2 strips optional peers, and EAS `npm ci` fails
- **Trigger**: Jest 30 (SDK 58) or anything else that pulls in `@napi-rs/wasm-runtime`, used with npm 11.6.2. That npm ships with Node 24.13.0, and running `npx` outside `nvm use` can pick up an older one.
- **Symptom**: EAS fails with `npm ci` EUSAGE `Missing: @emnapi/core… / @emnapi/runtime… from lock file`. Local installs work fine.
- **Cause**: npm 11.6.2 leaves optional peer dependencies out of the lockfile and strips them on every `npm install`. 11.6.3+ records them, and newer `npm ci` requires them.
- **Fix**: `npx npm@latest install --package-lock-only`, set `engines.npm` to `>=11.6.3`, and upgrade the global npm.
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #8.

### patch-package 6 can't read lockfile v3
- **Symptom**: `Cannot read properties of undefined (reading 'dependencies')` when creating a patch.
- **Fix**: `patch-package` ^8.
- **Seen in**: ICS Pro Coach, `expo-58-2026-10.md` #9.

---

## Security pins

- `axios` 1.14.x broke request cancellation in tests ([axios#10585](https://github.com/axios/axios/issues/10585)). It was fixed by 1.18, so a pin below 1.14 can be lifted. Seen in Pitstop, both records.
