# Liquidgram UI tests

**Failed**: 30 passed, 3 failed, 0 skipped.

- Device: iPhone 17 Pro, iOS 26.2
- Branch: `ios-v2-scratch/native-shell-usability` at `8936934`
- Run: https://github.com/levaasd142-cmd/liquidgram/actions/runs/40931366357
- Generated: 2026-10-29T18:57:16.539Z

## Tests

| Test | Pass | Status | Duration | Failure |
| --- | --- | --- | --- | --- |
| `CoreTests/testColdStartShowsApiKeysScreen` | light | Passed | 37.0 s |  |
| `CoreTests/testDemoAccount` | light | Passed | 31.0 s |  |
| `CoreTests/testDemoAccountSurvivesRestart` | light | Passed | 40.0 s |  |
| `CoreTests/testKeyboardKeepsFocusedFieldVisible` | light | Passed | 34.5 s |  |
| `CoreTests/testWebAppSelfTest` | light | Passed | 12.8 s |  |
| `FeatureTests/testAppLockOpensAndLocksAgainAfterBackground` | light | Passed | 23.8 s |  |
| `FeatureTests/testAppLockStaysLockedWhenAuthenticationFails` | light | Passed | 19.6 s |  |
| `FeatureTests/testDeepLinkOpensSettings` | light | Passed | 33.9 s |  |
| `FeatureTests/testKeyboardHasNoFormToolbar` | light | Passed | 16.6 s |  |
| `FeatureTests/testLiquidgramSettingsShowIPhoneSection` | light | Passed | 19.7 s |  |
| `FeatureTests/testPrivacyShieldCoversAppWhileInactive` | light | Passed | 25.6 s |  |
| `FeatureTests/testQuickActionFocusesSearch` | light | Passed | 46.1 s |  |
| `FeatureTests/testQuickActionOpensNewMessage` | light | Passed | 10.2 s |  |
| `FeatureTests/testQuickActionOpensSavedMessages` | light | Passed | 12.9 s |  |
| `FeatureTests/testQuickActionTogglesGhostMode` | light | Passed | 11.2 s |  |
| `ShellTests/testIPhoneStaysInPortrait` | light | Passed | 12.4 s |  |
| `ShellTests/testKeyboardResizesPageAndRestoresIt` | light | Passed | 29.3 s |  |
| `ShellTests/testWindowOpenedLateShowsInAppBrowser` | light | Passed | 40.7 s |  |
| `UsabilityTests/testAppStaysPortrait` | light | Passed | 21.9 s |  |
| `UsabilityTests/testAttachMenuAndEmojiPanelFitOnScreen` | light | Failed | 65.2 s | UsabilityTests.swift:625: failed - The panels of the composer: The Emoji tab of the emoji panel at (126, 833, 34×34) is not entirely between the status bar and y 840; The Stickers tab of the emoji panel at (184, 833, 34×34) is not entirely between the status bar and y 840; The GIFs tab of the emoji panel at (242, 833, 34×34) is not entirely between the status bar and y 840 |
| `UsabilityTests/testChatListTopRowWorks` | light | Passed | 30.1 s |  |
| `UsabilityTests/testChatTopRowWorks` | light | Passed | 36.4 s |  |
| `UsabilityTests/testDelayedWindowOpenShowsInAppBrowser` | light | Passed | 22.2 s |  |
| `UsabilityTests/testDraggingMessagesHidesKeyboard` | light | Failed | 31.6 s | UsabilityTests.swift:468: failed - The keyboard stayed up after a drag down on the messages from y 225 to y 425 |
| `UsabilityTests/testKeyboardKeepsChatLayout` | light | Failed | 41.0 s | UsabilityTests.swift:443: failed - The chat with the keyboard: The page scrolled during the keyboard cycles: highest pageTop 0.0, offsetTop 335.0, scrollTop 0.0, scrollY 0.0 |
| `UsabilityTests/testLongPressOnMessageOpensMenu` | light | Passed | 63.6 s |  |
| `UsabilityTests/testMediaViewerOpensAndCloses` | light | Passed | 21.1 s |  |
| `UsabilityTests/testPageIsActiveBeforeFirstTap` | light | Passed | 14.2 s |  |
| `UsabilityTests/testProfileTopRowWorks` | light | Passed | 29.5 s |  |
| `UsabilityTests/testSettingsTopRowWorks` | light | Passed | 31.6 s |  |
| `UsabilityTests/testStatusBarStripMatchesTheme` | light | Passed | 11.9 s |  |
| `CoreTests/testDemoAccount` | dark | Passed | 41.7 s |  |
| `UsabilityTests/testStatusBarStripMatchesTheme` | dark | Passed | 16.4 s |  |

## Self-test (light)

| Check | Result | Detail |
| --- | --- | --- |
| `bridge` | ok | version 1.0.0, notification permission default |
| `notificationBridge` | ok | permission default |
| `noServiceWorker` | ok | service workers are unavailable |
| `secureContext` | ok | http://127.0.0.1:47821 |
| `webCrypto` | ok | SHA-256 digest matches |
| `localStorage` | ok | write, read and remove work |
| `indexedDb` | ok | open, put and get work |
| `webAssembly` | ok | a module compiles and runs |
| `worker` | ok | a module worker from the app's origin answered (secure context true) |
| `fetchIndex` | ok | status 200, text/html; charset=utf-8 |
| `rangeRequest` | ok | /assets/index-B4-Me6xY.js: 206 with bytes 100-1123/159267 |
| `userAgentMobile` | ok | Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Liquidgram |
| `userAgentLiquidgram` | ok | Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Liquidgram |
| `appRendered` | ok | Transition full-height is-auth |
| `compatTest` | ok | passed |
| `noPageErrors` | ok | none since the page started |

<details><summary>Page details</summary>

```json
{
  "url": "http://127.0.0.1:47821/",
  "userAgent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Liquidgram",
  "language": "en-US",
  "viewport": "402x812 at 3x",
  "colorScheme": "light",
  "backdropFilter": true,
  "blobWorker": "blocked: Error: worker error: the script did not load",
  "authScreen": true
}
```

</details>

Folders: [`screenshots/`](screenshots), [`ax/`](ax) (accessibility trees of failed tests), [`logs/`](logs) (app log, xcodebuild output, self-test reports).
