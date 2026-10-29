# UI tests of the iPhone app

XCTest UI tests that start the real app on an iPhone simulator, with the bundled production web build, and look at it the way a person does: through the screen and the accessibility tree. CI runs them on every build of the IPA; the report, with screenshots of every step, is a branch of the repository.

## Running them

### GitHub Actions

The `build` job of [`.github/workflows/ios.yml`](../../.github/workflows/ios.yml) runs [`ios/run-ui-tests.sh`](../run-ui-tests.sh) after `Build IPA` and `Upload IPA`. Then, whatever the outcome:

- the report becomes the single commit of the branch `ios-test-results/<branch>`, for example `ios-test-results/liquidgram` for the default branch; GitHub shows its `README.md` with the table of results, the contact sheet and the screenshots;
- the run page gets notices with the counts and the links to the report and to its contact sheet, and an error annotation per failed test with its message, or one with the compiler errors when the tests did not build.

`Publish release` runs only on the default branch and only when the UI tests passed, so a failing test keeps the previous `ios-latest` release. The IPA artifact is uploaded either way.

A manual run (Actions › Build iOS app › Run workflow) takes an optional `ui_tests` input with comma-separated `-only-testing` filters, such as `LiquidgramUITests/CoreTests`; such a run never publishes a release. Its optional `legacy_ref` input names a Git revision of the loopback version, such as `367787807452c0d776e8ad10a9d9bc331a2e0d2a` (the last commit before the custom scheme), for the migration test.

### On a Mac

Requirements: Xcode 16 or newer, Node.js and an iOS simulator runtime.

```bash
bash ios/build-ipa.sh                     # the web build in ios/Liquidgram/WebApp and the Xcode project
bash ios/run-ui-tests.sh                  # report in dist-ios/ui-tests, result bundles in dist-ios/ui-tests-work
UI_TESTS_ONLY=UsabilityTests,-UsabilityTests/testAppStaysPortrait bash ios/run-ui-tests.sh
```

| Variable | Effect |
| --- | --- |
| `UI_TESTS_ONLY` | Comma-separated tests to run: a class or `Class/test`, with or without the `LiquidgramUITests/` prefix. An entry that starts with `-` is skipped instead, alone or within the selected classes. A selection that runs no test fails the script. The `ui_tests` input of a manual run takes the same form, also from the command line: `gh api -X POST repos/<owner>/<repo>/actions/workflows/ios.yml/dispatches -f ref=<branch> -f 'inputs[ui_tests]=UsabilityTests,-UsabilityTests/testAppStaysPortrait'` |
| `UI_TESTS_DARK` | Comma-separated tests for the dark mode pass, in the same form, instead of `DARK_MODE_TESTS` in the script (`CoreTests/testDemoAccount` and `UsabilityTests/testStatusBarStripMatchesTheme`). The pass runs those that `UI_TESTS_ONLY` selects |
| `UI_TESTS_SKIP_DARK` | `1` skips the dark mode pass |
| `UI_TESTS_DEVICE` | A simulator to use by name |
| `UI_TESTS_WORK_DIR` | Where the result bundles go |

In Xcode, the `Liquidgram` scheme's Test action runs the same tests (Product › Test); copy `Fixtures/liquidgram-selftest-worker.js` into `ios/Liquidgram/WebApp` first, or the self-test's `worker` check fails.

`UI_TESTS_ONLY` takes comma-separated `-only-testing` filters, `UI_TESTS_DEVICE` picks a simulator by name, `UI_TESTS_SKIP_DARK=1` skips the dark mode run, and `UI_TESTS_LEGACY_REF=<revision>` runs the migration test first. In Xcode, the `Liquidgram` scheme's Test action runs the same tests (Product › Test); copy `Fixtures/liquidgram-selftest-worker.js` into `ios/Liquidgram/WebApp` first, or the self-test's `worker` check fails.

### What the script does

1. Picks an iPhone simulator on the newest installed iOS runtime from `xcrun simctl list -j`: an iPhone 17 Pro or 16 Pro if there is one, else the newest Pro, else any iPhone.
2. Turns off the hardware keyboard of the simulator before it boots, so the software keyboard shows, boots it, and sets a fixed status bar for the screenshots.
3. Builds the app and the tests once (`xcodebuild build-for-testing`, Debug, no signing), with `Fixtures/liquidgram-selftest-worker.js` added to the web build of this build only.
4. Installs the app and grants it the microphone, the camera and the photos (`xcrun simctl privacy`), so recording tests never stop at a system prompt.
5. Runs the selected tests in light mode, then the dark mode tests again with `xcrun simctl ui <udid> appearance dark`, each pass with a result bundle, without parallel testing and with a time limit per test.
6. Exports the attachments (`xcrun xcresulttool export attachments`) and the results (`xcrun xcresulttool get test-results tests`), collects the app's log from the simulator (`log show` for the subsystem `org.liquidgram.messenger`) and keeps the last 300 lines of each `xcodebuild` output.
7. [`Tools/report.mjs`](Tools/report.mjs) writes the report, downscales the screenshots with `sips -Z 1200` and draws the contact sheet.

4. With `UI_TESTS_LEGACY_REF`, runs [`Tools/seed-legacy-app.sh`](Tools/seed-legacy-app.sh): it builds the app at that revision, which served the web app from `http://127.0.0.1:47821`, installs it in place of the test build, runs it for 20 seconds with the demo account and `Fixtures/legacy-seed.js`, and quits it. Then `TransportTests/testLegacyDataMovesToAppOrigin` runs alone (the `migration` pass), over that data.
5. Runs all tests in light mode, then `CoreTests/testDemoAccount` again in dark mode (`xcrun simctl ui <udid> appearance dark`), each with a result bundle, without parallel testing and with a time limit per test.
6. Exports the attachments (`xcrun xcresulttool export attachments`) and the results (`xcrun xcresulttool get test-results tests`), collects the app's log from the simulator (`log show` for the subsystem `org.liquidgram.messenger`) and keeps the last 300 lines of each `xcodebuild` output.
7. [`Tools/report.mjs`](Tools/report.mjs) writes the report and downscales the screenshots with `sips -Z 1200`.

The script exits with 1 when a test failed, the tests did not build or no test ran.

## The report

| Path | Content |
| --- | --- |
| `README.md` | `summary.md`, the contact sheet, then the screenshots of each test |
| `summary.md` | Status, device, a table of the tests (pass, status, duration, failure message), the self-test checks |
| `summary.json` | The same data for scripts; the workflow's annotations come from it |
| `contact-sheet.png` | Every screenshot of the run in one image, in report order, with the test and the step under each one and a band above it: green for a passed test, red for a failed one, orange for the screenshot of the failure |
| `screenshots/` | `<Class>-<test>-<step>.png`, steps of the dark run end with `-dark`, the screen at a failure starts with `failure-` |
| `ax/` | Accessibility trees (`app.debugDescription`) of failed tests only: the one taken at the failure and those the test asked for at chosen steps |
| `logs/` | `app.log` from the simulator, `xcodebuild-*.log` and `build-for-testing.log` tails, the self-test reports |

[`known-issues.json`](known-issues.json) lists failures that are known on the current base. The report marks a failed test as a known issue when all its failed self-test checks are listed there; the test still fails, so the entry goes away with the fix.

## The tests

Every test starts the app with `-LiquidgramResetState YES` unless it tests persistence, waits up to a minute for a cold start of the web app, and attaches named screenshots at its key moments that stay even when it passes. `launchApp` turns the simulator back to portrait first, in case a failed test left it turned.

### `CoreTests`: the app since its first version

| Test | Checks |
| --- | --- |
| `testColdStartShowsApiKeysScreen` | A clean install shows the API keys screen of the web app (the API ID and API hash fields and the description, found through the web view's accessibility); no "not supported" page and no `liquidgram.startupError` |
| `testWebAppSelfTest` | Every check of [`Fixtures/selftest.js`](Fixtures/selftest.js) passes, see below |
| `testKeyboardKeepsFocusedFieldVisible` | Typing digits into the API ID field: the software keyboard is up and the field is above it |
| `testDemoAccount` | The demo account shows its chats; a chat opens; the composer takes typed text (nothing is sent) and stays above the keyboard. Runs in light and dark mode |
| `testDemoAccountSurvivesRestart` | After the home button and a restart without the reset and without seeding, the chats of the demo account are still there: the website data store keeps them on disk and the page keeps its origin |

### `UsabilityTests`: what the first user of the app reported

The user of v1 found the interface shifted, many buttons dead, the gestures bad. These tests check the behavior that the fixes give the app: the page below the status bar, a page that shrinks above the keyboard instead of sliding up, portrait only on iPhone. A control of a top row that starts below the status bar also starts at most 24 pt below the top of the page: a lower one means that the page adds a top inset of its own to the shell's. Each test checks everything it can before it fails and lists every problem it found in its failure message, with the frames involved, so one run of a broken build shows all of them. A tap on a control goes to the center of its frame like a finger, also where XCUITest itself would refuse it, such as under the status bar. The tests that measure the page inside or need page code launch with `Fixtures/ui-probe.js`.

| Test | Checks |
| --- | --- |
| `testChatListTopRowWorks` | Open menu, the search field and Ghost mode start below the status bar; Open menu opens the main menu, which a tap outside closes; the search field takes the focus with the keyboard and Return to chat list leaves it; Ghost mode shows its toast |
| `testChatTopRowWorks` | Back, the title and More options of a chat start below the status bar; More options opens the chat menu; the title opens the profile, whose Back returns to the chat; Back returns to the chat list |
| `testProfileTopRowWorks` | Back and Edit of a profile start below the status bar; Edit opens the contact editor and Back returns from it; Back closes the profile |
| `testSettingsTopRowWorks` | Go back, Search, Edit profile and More options of the settings start below the status bar; More options opens its menu (Log Out, never tapped); Search opens the settings search; Edit profile opens the profile editor; Go back returns from each and finally to the chat list |
| `testKeyboardKeepsChatLayout` | With the keyboard up in a chat: the page ends at the top of the keyboard (its bar of predictions included), the header did not move, the composer sits at most 24 pt above the keyboard, the newest message is between the header and the composer, and the page has no scroll offset. Once the keyboard hides, every frame is back where it was; after two more keyboard cycles too, the page never scrolled (`scrollTop`, `scrollY`, `visualViewport.pageTop` and `offsetTop` stayed 0), and the root element, `--vh` and the visual viewport match the window height |
| `testDraggingMessagesHidesKeyboard` | A drag down on the messages hides the keyboard |
| `testAppStaysPortrait` | With the simulator turned to landscape the window and the page stay portrait; the test turns the simulator back before it fails |
| `testStatusBarStripMatchesTheme` | The page starts below the status bar, and the strip above it has the page's theme color (`<meta name="theme-color">`) in two rows of pixels across the screen: at its top and right above the page. Runs in light and dark mode |
| `testPageIsActiveBeforeFirstTap` | Right after the start, before any tap, the page does not treat itself as being in the background (`body.in-background`), which would stop its animations |
| `testAttachMenuAndEmojiPanelFitOnScreen` | The attach menu opens with its items between the status bar and the home indicator, and a tap outside closes it; the tabs of the emoji panel are above the home indicator and the composer above the panel |
| `testMediaViewerOpensAndCloses` | A tap on the photo of the demo account opens the media viewer, whose Close button starts below the status bar and closes it |
| `testLongPressOnMessageOpensMenu` | A long press on a message opens its menu on screen, and the first tap on Reply closes the menu and starts a reply. `GestureTests` checks the other gestures |
| `testDelayedWindowOpenShowsInAppBrowser` | A `window.open` that the page calls 1.5 s after a tap, like flows that wait for the server first, opens the in-app browser: its Close or Done button or the address shows, or, where XCUITest cannot see into Safari's view, a view covers the page while the app stays in front |

### `RoundVideoTests`: the native round video recorder

`Fixtures/round-video.js` opens the recorder from the page through the bridge, as the composer does, and reports what the page got; the test drives the recorder on screen. The simulator has no camera, so the first two tests pass `-LiquidgramFakeRoundVideo YES`, which gives the recorder generated frames and silence and makes the app report the recorded file as `liquidgram.roundVideo.testReport`. The checks of each test become a table in the report, like the self-test's.

| Test | Checks |
| --- | --- |
| `testRecordsAndSendsRoundVideo` | Recording starts by itself; the flash, the camera switch and view-once work while it records. After Send the page has a `/__liquidgram/media/` path, 480 × 480, view-once and the duration, and a second request during the recording got `null`. The file is a 480 × 480 H.264 High profile video with CABAC and mono 48 kHz AAC in an MP4 with the movie header first, of the duration the page got, with at least 15 frames per second and at most 250 KB per second, and its first frame decodes. When `AppSchemeHandler` serves the page, the page's fetch is a 480 × 480 `video/mp4` Blob of the file's size, a range request is `206`, and the path is `404` after `releaseMedia`. The app deletes the file once the page released it |
| `testCancelDiscardsRecording` | Cancel gives the page `null` and leaves no file |
| `testRecorderExplainsMissingCamera` | Without the generated camera the simulator has no camera: the recorder says "No camera", and Close gives the page `null` |

### `FeatureTests`: the native features of version 2

They follow the shared v2 contract, so on a build without these features they fail at the first missing element, which their failure message names.

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
| `testKeyboardHasNoFormToolbar` | The keyboard of a web field comes without WebKit's toolbar with the Previous, Next and Done buttons |

### `TransportTests`: the custom scheme

The app serves the web app at `liquidgram-web://app/` and streams media through it; see [Media streaming](../README.md#media-streaming) and [Data of version 1](../README.md#data-of-version-1).

| Test | Checks |
| --- | --- |
| `testMediaStreamsFromPage` | With the demo account and `Fixtures/media-api.js`, `Fixtures/stream-check.js` plays a video through the whole chain: the stream asks the web app's own `loadMediaPart`, which downloads through its API. With a synthetic `loadMediaPart` in its place, it checks the 0-1 probe, open, unaligned and suffix ranges, `416`, a whole file without a range, `HEAD`, 12 parallel requests with at most four parts loading at once, the content type guard, a failed part and a stopped request; then music that starts before all of its parts arrived, a seek to 80 % and a video with a seek |
| `testLegacyDataMovesToAppOrigin` | Only in the `migration` pass: after the loopback version ran with the demo account, this build starts over its data; the chats show, and `Fixtures/migration-check.js` finds the session, the API keys, the web app's cached state and every value of `legacy-seed.js` in the app's origin, and the migration's outcome says it moved them; 10 seconds after the start, the app removes the old origin's data and says so with `liquidgram.migration.legacyDataRemoved` |

The lock tests pass `-LiquidgramFakeAuthenticationDelay`, so the faked Face ID takes seconds instead of 0.3: an XCUITest launch returns only once the app is idle, when a short fake would already have opened the lock. The app lock reads the delay from `TestHooks.fakeAuthenticationDelay`.

### `RecordingTests`: the record button

The record button of a chat works as in Telegram's apps. The tests run the offline demo account with `Fixtures/fake-capture.js`, so a recording starts without the microphone and the round video recorder that the simulator lacks, and nothing is sent.

| Test | Checks |
| --- | --- |
| `testTapSwitchesBetweenVoiceAndVideo` | A tap on the record button switches it to video messages ("Record video message") with the hint "Hold to record video…" and opens no microphone; a second tap switches back |
| `testHoldRecordsVoiceAndSlidesCancelOrLock` | Holding the button records a voice message: sliding left closes the microphone again and leaves no recording; sliding up locks the recording, which keeps its trash button after the finger lifts, and the trash button ends it |

### `GestureTests`: gestures as in Telegram for iPhone

The swipes are drags of `XCUICoordinate` at a set speed, which reach the web app as touch events.

| Test | Checks |
| --- | --- |
| `testSwipeBackFromEdgeClosesChat` | A quick swipe from 4 points off the left edge of a chat brings back the chat list: another chat and the menu button of the list on screen |
| `testSwipeBackFromMiddleClosesChat` | The same swipe from 30 percent of the width |
| `testSlowShortSwipeSpringsBack` | A slow swipe to a quarter of the width that rests before the finger lifts leaves the same chat open, with its messages on screen and the chat list off screen; the click that WebKit sends when a finger that rested lifts opens no other chat |
| `testSwipeBackClosesProfile` | The title in the chat header opens the profile; a quick swipe from its left edge brings back the chat. Skipped while the header is under the status bar, which takes the tap |
| `testChatListRightSwipeKeepsChatList` | A right swipe on the chat list keeps its menu button, opens no search tabs and brings up no keyboard |
| `testLongPressOpensMessageMenu` | A one-second press on a message opens its menu with Reply rather than Quote & Reply, so the press selected no text; the first tap on it puts the reply above the composer (its Cancel button) |
| `testSwipeToReply` | A message dragged 140 points to the left puts the reply above the composer |

## The self-test

`Fixtures/selftest.js` is the body of an async function that `TestHooks` runs in the page through `callAsyncJavaScript` once the web app reports `appReady`, or 5 seconds after the first load of a page that never does, like the API keys screen. Each check has a 10-second limit. The JSON report becomes the accessibility value of `liquidgram.selftest.result`, the test attaches it, and the report shows it as a table.

| Check | Passes when |
| --- | --- |
| `bridge` | `__liquidgramNative.platform` is `ios` and `bridge.js` ran (`isBridgeInstalled`) |
| `notificationBridge` | `window.Notification` is the class of `bridge.js`, not a native one, with `requestPermission` and a valid `permission` |
| `noServiceWorker` | No service worker controls the page and none is registered |
| `appOrigin` | The page's origin is `liquidgram-web://app` |
| `secureContext` | `isSecureContext` is true for the app's origin |
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
| `round-video.js` | `RoundVideoTests`, as the self-test script: opens the round video recorder from the page and reports what the page got |
| `offline-api.js` | `Launch(shouldSeedDemoAccount: true)` or `Launch(shouldStayOffline: true)`: replaces the GramJS worker, the only part of the web app that connects to Telegram, with one that never answers, so a stored session stays on its cached state and nothing reaches Telegram |
| `demo-account.js` | `Launch(shouldSeedDemoAccount: true)`: writes a signed-in session to `localStorage` (`account1`, `tt-global-state` with chats and messages dated relative to now) and API keys of the valid form, which the web app needs before it shows its main screen; offline, the keys are never used. The chat with Катя Дизайн has a photo, drawn on a canvas and stored as its `blobUrl` like a photo the web app has just sent, so the media viewer opens it without a download |
| `ui-probe.js` | `Launch(fixtures: ["ui-probe"])`: publishes the page's measurements as the accessibility label of a tiny element, `liquidgram-probe {json}` (viewport sizes, scroll offsets and their highest values since the start, safe-area insets, `--vh`, the theme color, the focused element, `body.in-background`), and adds two nearly transparent buttons at the left edge that run page code: `liquidgram-probe-blur` takes the focus from the focused field and `liquidgram-probe-open-later` calls `window.open` 1.5 s after the tap |
| `selftest.js` | `Launch(shouldRunSelfTest: true)`: the self-test |
| `fake-capture.js` | `Launch(fixtures: ["fake-capture"])`: `getUserMedia` for audio returns a quiet tone, and a nearly transparent text "Test microphone: opened N, live M" counts the opened streams and the tracks the page has not stopped; until bridge.js has the round video recorder, it provides one that cancels, so the page offers video messages |
| `liquidgram-selftest-worker.js` | Not injected: served from the web root for the `worker` check |
| `media-api.js` | `TransportTests/testMediaStreamsFromPage`: like `offline-api.js`, but the worker answers `initApi`, pings and `downloadMedia` for the files a check puts into `window.__liquidgramTestMedia` |
| `stream-check.js` | The self-test of `testMediaStreamsFromPage`; its report is attached as `selftest-report-stream` |
| `legacy-seed.js` | Injected into the loopback version by `Tools/seed-legacy-app.sh`: a `localStorage` marker and an IndexedDB record with values that JSON cannot hold |
| `migration-check.js` | The self-test of `testLegacyDataMovesToAppOrigin`; its report is attached as `selftest-report-migration` |

A connected session asks for the notification permission after its first tap. The offline demo account never gets there, since the web app subscribes only after its first sync with Telegram, but `allowNotificationsIfAsked()` answers the system prompt if it ever shows, as it would block every later step.

## Writing tests

- Subclass `LiquidgramUITestCase` and mark test methods `@MainActor`, as the XCUI classes are main-actor isolated. Keep a test class's own constants and helpers `private`: a member of the base class with the same name as a member of a subclass does not compile.
- Find web content through `webView` with `findElement(in:labelContaining:)`, `findStaticText(in:containing:)` and `findTextInput(in:labeled:)`; find native views by accessibility identifier with `findNativeElement(_:)`. A chat of the list is one button whose label holds the whole row.
- Web content enters the accessibility tree before the web app shows it, and keeps screens that slid away, like the chat list under an opened chat: wait with `waitForHittable(_:_:)` before a tap or a screenshot, and with `waitForChatRow(titled:_:)` for a row of the chat list. Several elements can have the same label, such as Back in a chat and in its profile; query them all and take the one on screen.
- The `frame` of an element that is gone fails the test; check `exists` before reading it from an element found earlier.
- Wait with `waitFor`, `waitForHittable` and `waitForDisappearance`; on a timeout they attach a screenshot and the accessibility tree before failing. `attachAccessibilityTree(_:)` keeps a tree only when the test fails.
- Name screenshots `NN-what-is-shown`; the report orders them by time and the dark run adds `-dark`. Add a test to `DARK_MODE_TESTS` in `run-ui-tests.sh` when its result depends on the appearance.
- Without a Mac, the sources type-check on Linux against stand-ins of UIKit and XCTest with the SDK's signatures and main-actor isolation; that catches wrong names and types, though not the behavior.
