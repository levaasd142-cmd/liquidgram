# Liquidgram UI tests

**Failed**: 20 passed, 1 failed, 0 skipped.

- Device: iPhone 17 Pro, iOS 26.2
- Branch: `ios-v2/fix-native-shell` at `f9c3b7e`
- Run: https://github.com/levaasd142-cmd/liquidgram/actions/runs/40936206346
- Generated: 2026-10-29T19:24:12.261Z

## Tests

| Test | Pass | Status | Duration | Failure |
| --- | --- | --- | --- | --- |
| `CoreTests/testColdStartShowsApiKeysScreen` | light | Passed | 40.1 s |  |
| `CoreTests/testDemoAccount` | light | Passed | 33.9 s |  |
| `CoreTests/testDemoAccountSurvivesRestart` | light | Passed | 38.9 s |  |
| `CoreTests/testKeyboardKeepsFocusedFieldVisible` | light | Passed | 14.4 s |  |
| `CoreTests/testWebAppSelfTest` | light | Passed | 13.0 s |  |
| `FeatureTests/testAppLockOpensAndLocksAgainAfterBackground` | light | Failed | 12.4 s | FeatureTests.swift:70: XCTAssertTrue failed - The unlock button cannot be tapped |
| `FeatureTests/testAppLockStaysLockedWhenAuthenticationFails` | light | Passed | 16.9 s |  |
| `FeatureTests/testChatHeaderStaysVisibleWhileTyping` | light | Passed | 19.2 s |  |
| `FeatureTests/testDeepLinkOpensSettings` | light | Passed | 73.3 s |  |
| `FeatureTests/testHeadersStayBelowStatusBar` | light | Passed | 22.3 s |  |
| `FeatureTests/testKeyboardHasNoFormToolbar` | light | Passed | 11.7 s |  |
| `FeatureTests/testLiquidgramSettingsShowIPhoneSection` | light | Passed | 17.3 s |  |
| `FeatureTests/testPrivacyShieldCoversAppWhileInactive` | light | Passed | 22.8 s |  |
| `FeatureTests/testQuickActionFocusesSearch` | light | Passed | 14.8 s |  |
| `FeatureTests/testQuickActionOpensNewMessage` | light | Passed | 14.2 s |  |
| `FeatureTests/testQuickActionOpensSavedMessages` | light | Passed | 9.6 s |  |
| `FeatureTests/testQuickActionTogglesGhostMode` | light | Passed | 8.7 s |  |
| `ShellTests/testIPhoneStaysInPortrait` | light | Passed | 15.5 s |  |
| `ShellTests/testKeyboardResizesPageAndRestoresIt` | light | Passed | 25.8 s |  |
| `ShellTests/testWindowOpenedLateShowsInAppBrowser` | light | Passed | 20.3 s |  |
| `CoreTests/testDemoAccount` | dark | Passed | 42.8 s |  |

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

Folders: [`screenshots/`](screenshots), [`ax/`](ax) (accessibility trees the tests attached), [`logs/`](logs) (app log, xcodebuild output, self-test reports).
