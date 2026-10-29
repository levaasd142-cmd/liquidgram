# UI tests of the iPhone app

XCTest UI tests that start the real app on an iPhone simulator, with the bundled production web build and the local server, and look at it the way a person does: through the screen and the accessibility tree. CI runs them on every build of the IPA; the report, with screenshots of every step, is a branch of the repository.

## Running them

### GitHub Actions

The `build` job of [`.github/workflows/ios.yml`](../../.github/workflows/ios.yml) runs [`ios/run-ui-tests.sh`](../run-ui-tests.sh) after `Build IPA` and `Upload IPA`. Then, whatever the outcome:

- the report becomes the single commit of the branch `ios-test-results/<branch>`, for example `ios-test-results/liquidgram` for the default branch; GitHub shows its `README.md` with the table of results and the screenshots;
- the run page gets a notice with the counts and an error annotation per failed test with its message, or one with the compiler errors when the tests did not build.

`Publish release` runs only on the default branch and only when the UI tests passed, so a failing test keeps the previous `ios-latest` release. The IPA artifact is uploaded either way.

A manual run (Actions › Build iOS app › Run workflow) takes an optional `ui_tests` input with comma-separated `-only-testing` filters, such as `LiquidgramUITests/CoreTests`; such a run never publishes a release.

### On a Mac

Requirements: Xcode 16 or newer, Node.js and an iOS simulator runtime.

```bash
bash ios/build-ipa.sh                     # the web build in ios/Liquidgram/WebApp and the Xcode project
bash ios/run-ui-tests.sh                  # report in dist-ios/ui-tests, result bundles in dist-ios/ui-tests-work
UI_TESTS_ONLY=LiquidgramUITests/CoreTests bash ios/run-ui-tests.sh
```

`UI_TESTS_ONLY` takes comma-separated `-only-testing` filters, `UI_TESTS_DEVICE` picks a simulator by name, `UI_TESTS_SKIP_DARK=1` skips the dark mode run. In Xcode, the `Liquidgram` scheme's Test action runs the same tests (Product › Test); copy `Fixtures/liquidgram-selftest-worker.js` into `ios/Liquidgram/WebApp` first, or the self-test's `worker` check fails.

### What the script does

1. Picks an iPhone simulator on the newest installed iOS runtime from `xcrun simctl list -j`: an iPhone 17 Pro or 16 Pro if there is one, else the newest Pro, else any iPhone.
2. Turns off the hardware keyboard of the simulator before it boots, so the software keyboard shows, boots it, and sets a fixed status bar for the screenshots.
3. Builds the app and the tests once (`xcodebuild build-for-testing`, Debug, no signing), with `Fixtures/liquidgram-selftest-worker.js` added to the web build of this build only.
4. Runs all tests in light mode, then `CoreTests/testDemoAccount` again in dark mode (`xcrun simctl ui <udid> appearance dark`), each with a result bundle, without parallel testing and with a time limit per test.
5. Exports the attachments (`xcrun xcresulttool export attachments`) and the results (`xcrun xcresulttool get test-results tests`), collects the app's log from the simulator (`log show` for the subsystem `org.liquidgram.messenger`) and keeps the last 300 lines of each `xcodebuild` output.
6. [`Tools/report.mjs`](Tools/report.mjs) writes the report and downscales the screenshots with `sips -Z 1200`.

The script exits with 1 when a test failed or the tests did not build.

## The report

| Path | Content |
| --- | --- |
| `README.md` | `summary.md` followed by the screenshots of each test |
| `summary.md` | Status, device, a table of the tests (pass, status, duration, failure message), the self-test checks |
| `summary.json` | The same data for scripts; the workflow's annotations come from it |
| `screenshots/` | `<Class>-<test>-<step>.png`, steps of the dark run end with `-dark`, failed waits start with `failure-` |
| `ax/` | The accessibility trees the tests attached (`app.debugDescription`), at chosen steps and at every failed wait |
| `logs/` | `app.log` from the simulator, `xcodebuild-*.log` and `build-for-testing.log` tails, the self-test reports |

[`known-issues.json`](known-issues.json) lists failures that are known on the current base. The report marks a failed test as a known issue when all its failed self-test checks are listed there; the test still fails, so the entry goes away with the fix.

## The tests

Every test starts the app with `-LiquidgramResetState YES` unless it tests persistence, waits up to a minute for a cold start of the web app, and attaches named screenshots that stay even when it passes.

### `CoreTests`: the app since its first version

| Test | Checks |
| --- | --- |
| `testColdStartShowsApiKeysScreen` | A clean install shows the API keys screen of the web app (the API ID and API hash fields and the description, found through the web view's accessibility); no "not supported" page and no `liquidgram.startupError` |
| `testWebAppSelfTest` | Every check of [`Fixtures/selftest.js`](Fixtures/selftest.js) passes, see below |
| `testKeyboardKeepsFocusedFieldVisible` | Typing digits into the API ID field: the software keyboard is up and the field is above it |
| `testDemoAccount` | The demo account shows its chats; a chat opens; the composer takes typed text (nothing is sent) and stays above the keyboard. Runs in light and dark mode |
| `testDemoAccountSurvivesRestart` | After the home button and a restart without the reset and without seeding, the chats of the demo account are still there: the website data store keeps them on disk and the page keeps its origin |

### `FeatureTests`: the native features of version 2

They follow the shared v2 contract, so on a build without these features they fail at the first missing element, which their failure message names. The two layout tests check bugs that the screenshots of the v1 app show: its headers sit under the status bar, and typing in a chat scrolls the header away.

| Test | Checks |
| --- | --- |
| `testAppLockOpensAndLocksAgainAfterBackground` | `-appLockEnabled YES -appLockDelay 0 -LiquidgramFakeAuthentication success`: the lock (`liquidgram.lock`) shows at launch, its button (`liquidgram.lock.unlock`) can be tapped, the chats appear after the faked Face ID; after the home button and a return the lock shows again and opens again |
| `testAppLockStaysLockedWhenAuthenticationFails` | With `failure` the lock stays, also after a tap on the unlock button, and the web app cannot be touched |
| `testPrivacyShieldCoversAppWhileInactive` | With Notification Center open over the app, `liquidgram.privacyShield` covers it; it goes away when the app is active again. A last screenshot shows the app switcher, without an assertion, since the gesture that opens it is not reliable |
| `testQuickActionOpensSavedMessages` | `-LiquidgramTestAction openSavedMessages` opens Saved Messages with its message on screen |
| `testQuickActionFocusesSearch` | `openSearch` focuses the chat search, so the keyboard comes up |
| `testQuickActionOpensNewMessage` | `newMessage` opens the contacts picker ("Search contacts") |
| `testQuickActionTogglesGhostMode` | `toggleGhostMode` shows the "Ghost mode is on/off" toast |
| `testDeepLinkOpensSettings` | `XCUIApplication.open(liquidgram://settings)` opens the web app's settings |
| `testLiquidgramSettingsShowIPhoneSection` | Settings › Liquidgram has a section that mentions the iPhone; screenshot after scrolling to it |
| `testHeadersStayBelowStatusBar` | The headers of the chat list and of an opened chat start below the status bar, which the page extends under (`viewport-fit=cover`) |
| `testChatHeaderStaysVisibleWhileTyping` | With the keyboard up in a chat, its header stays on screen instead of the whole page scrolling up |
| `testKeyboardHasNoFormToolbar` | The keyboard of a web field comes without WebKit's toolbar with the Previous, Next and Done buttons |

The lock tests pass `-LiquidgramFakeAuthenticationDelay`, so the faked Face ID takes seconds instead of 0.3: an XCUITest launch returns only once the app is idle, when a short fake would already have opened the lock. The app lock reads the delay from `TestHooks.fakeAuthenticationDelay`.

### `ShellTests`: the native shell around the page

| Test | Checks |
| --- | --- |
| `testKeyboardResizesPageAndRestoresIt` | The web view starts below the status bar. In a chat, the keyboard leaves the header where it was, the web view ends at the top of the keyboard and the composer rests on it; after a tap on a message closes the keyboard, the web view, the header and the composer are back where they were. Screenshots of the chat list, the chat, the keyboard up and the keyboard hidden |
| `testIPhoneStaysInPortrait` | With the simulator turned to landscape, the app's window stays in portrait |
| `testWindowOpenedLateShowsInAppBrowser` | A button that a test script adds to the page opens a web page 1.5 seconds after its tap, as the web app does for links that wait for Telegram first; the in-app browser covers the page instead of WebKit's pop-up blocker dropping the window |

## The self-test

`Fixtures/selftest.js` is the body of an async function that `TestHooks` runs in the page through `callAsyncJavaScript` once the web app reports `appReady`, or 5 seconds after the first load of a page that never does, like the API keys screen. Each check has a 10-second limit. The JSON report becomes the accessibility value of `liquidgram.selftest.result`, the test attaches it, and the report shows it as a table.

| Check | Passes when |
| --- | --- |
| `bridge` | `__liquidgramNative.platform` is `ios` and `bridge.js` ran (`isBridgeInstalled`) |
| `notificationBridge` | `window.Notification` is the class of `bridge.js`, not a native one, with `requestPermission` and a valid `permission` |
| `noServiceWorker` | No service worker controls the page and none is registered |
| `secureContext` | `isSecureContext` is true for `http://127.0.0.1:47821` |
| `webCrypto` | `crypto.subtle` computes the SHA-256 of `abc` |
| `localStorage`, `indexedDb` | A value can be written and read back; IndexedDB opens, puts and gets |
| `webAssembly` | A small module compiles and its `add(2, 3)` returns 5 |
| `worker` | A module worker from the app's origin answers a message |
| `fetchIndex` | `fetch('./')` is 200 with HTML |
| `rangeRequest` | A `Range` request for the page's module script in `assets/` is 206 with the right `Content-Range` and the same bytes as the file |
| `userAgentMobile`, `userAgentLiquidgram` | The user agent has `Mobile/` (the web app tells phones apart by it) and `Liquidgram` |
| `appRendered` | `#root` has an element of the web app |
| `compatTest` | `compatTest.js` passed |
| `noPageErrors` | No uncaught error or unhandled rejection since the first script, as recorded by `Fixtures/page-errors.js` |

The page details under the table show the user agent, the viewport, the color scheme, `backdrop-filter` support and whether a `blob:` worker starts. It does not: the production Content-Security-Policy has `worker-src 'self'`, which WebKit does not match to `blob:` URLs, so the `worker` check uses an echo worker served from the app's origin, the way the web app runs GramJS and its other workers. `run-ui-tests.sh` adds that worker to the web build of the test app only.

## Fixtures

The tests pass scripts to the app through the launch environment (`TestHooks.swift`):

| Fixture | Use |
| --- | --- |
| `page-errors.js` | Every launch: records uncaught errors from document start, for the `noPageErrors` check |
| `offline-api.js` | `Launch(shouldSeedDemoAccount: true)` or `Launch(shouldStayOffline: true)`: replaces the GramJS worker, the only part of the web app that connects to Telegram, with one that never answers, so a stored session stays on its cached state and nothing reaches Telegram |
| `demo-account.js` | `Launch(shouldSeedDemoAccount: true)`: writes a signed-in session to `localStorage` (`account1`, `tt-global-state` with chats and messages dated relative to now) and API keys of the valid form, which the web app needs before it shows its main screen; offline, the keys are never used |
| `selftest.js` | `Launch(shouldRunSelfTest: true)`: the self-test |
| `liquidgram-selftest-worker.js` | Not injected: served from the web root for the `worker` check |

A connected session asks for the notification permission after its first tap. The offline demo account never gets there, since the web app subscribes only after its first sync with Telegram, but `allowNotificationsIfAsked()` answers the system prompt if it ever shows, as it would block every later step.

## Writing tests

- Subclass `LiquidgramUITestCase` and mark test methods `@MainActor`, as the XCUI classes are main-actor isolated.
- Find web content through `webView` with `findElement(in:labelContaining:)`, `findStaticText(in:containing:)` and `findTextInput(in:labeled:)`; find native views by accessibility identifier with `findNativeElement(_:)`. A chat of the list is one button whose label holds the whole row.
- Web content enters the accessibility tree before the web app shows it, and keeps screens that slid away, like the chat list under an opened chat: wait with `waitForHittable(_:_:)` before a tap or a screenshot, and with `waitForChatRow(titled:_:)` for a row of the chat list.
- Wait with `waitFor`, `waitForHittable` and `waitForDisappearance`; on a timeout they attach a screenshot and the accessibility tree before failing.
- Name screenshots `NN-what-is-shown`; the report orders them by time and the dark run adds `-dark`.
