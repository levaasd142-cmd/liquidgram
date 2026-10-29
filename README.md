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

## Screenshots

### `CoreTests/testColdStartShowsApiKeysScreen (light)`

<img src="screenshots/CoreTests-testColdStartShowsApiKeysScreen-01-api-keys-screen.png" width="260" alt="01-api-keys-screen" title="01-api-keys-screen">

[01-api-keys-screen](screenshots/CoreTests-testColdStartShowsApiKeysScreen-01-api-keys-screen.png)

### `CoreTests/testDemoAccount (light)`

<img src="screenshots/CoreTests-testDemoAccount-01-chat-list.png" width="260" alt="01-chat-list" title="01-chat-list">
<img src="screenshots/CoreTests-testDemoAccount-02-chat.png" width="260" alt="02-chat" title="02-chat">
<img src="screenshots/CoreTests-testDemoAccount-03-composer-with-keyboard.png" width="260" alt="03-composer-with-keyboard" title="03-composer-with-keyboard">

[01-chat-list](screenshots/CoreTests-testDemoAccount-01-chat-list.png) · [02-chat](screenshots/CoreTests-testDemoAccount-02-chat.png) · [03-composer-with-keyboard](screenshots/CoreTests-testDemoAccount-03-composer-with-keyboard.png)

### `CoreTests/testDemoAccountSurvivesRestart (light)`

<img src="screenshots/CoreTests-testDemoAccountSurvivesRestart-01-chat-list-before-restart.png" width="260" alt="01-chat-list-before-restart" title="01-chat-list-before-restart">
<img src="screenshots/CoreTests-testDemoAccountSurvivesRestart-02-chat-list-after-restart.png" width="260" alt="02-chat-list-after-restart" title="02-chat-list-after-restart">

[01-chat-list-before-restart](screenshots/CoreTests-testDemoAccountSurvivesRestart-01-chat-list-before-restart.png) · [02-chat-list-after-restart](screenshots/CoreTests-testDemoAccountSurvivesRestart-02-chat-list-after-restart.png)

### `CoreTests/testKeyboardKeepsFocusedFieldVisible (light)`

<img src="screenshots/CoreTests-testKeyboardKeepsFocusedFieldVisible-01-keyboard-up.png" width="260" alt="01-keyboard-up" title="01-keyboard-up">

[01-keyboard-up](screenshots/CoreTests-testKeyboardKeepsFocusedFieldVisible-01-keyboard-up.png)

### `CoreTests/testWebAppSelfTest (light)`

<img src="screenshots/CoreTests-testWebAppSelfTest-01-self-test-finished.png" width="260" alt="01-self-test-finished" title="01-self-test-finished">

[01-self-test-finished](screenshots/CoreTests-testWebAppSelfTest-01-self-test-finished.png)

### `FeatureTests/testAppLockOpensAndLocksAgainAfterBackground (light)`

<img src="screenshots/FeatureTests-testAppLockOpensAndLocksAgainAfterBackground-01-locked-at-launch.png" width="260" alt="01-locked-at-launch" title="01-locked-at-launch">

[01-locked-at-launch](screenshots/FeatureTests-testAppLockOpensAndLocksAgainAfterBackground-01-locked-at-launch.png)

### `FeatureTests/testAppLockStaysLockedWhenAuthenticationFails (light)`

<img src="screenshots/FeatureTests-testAppLockStaysLockedWhenAuthenticationFails-01-failed-authentication.png" width="260" alt="01-failed-authentication" title="01-failed-authentication">
<img src="screenshots/FeatureTests-testAppLockStaysLockedWhenAuthenticationFails-02-failed-again.png" width="260" alt="02-failed-again" title="02-failed-again">

[01-failed-authentication](screenshots/FeatureTests-testAppLockStaysLockedWhenAuthenticationFails-01-failed-authentication.png) · [02-failed-again](screenshots/FeatureTests-testAppLockStaysLockedWhenAuthenticationFails-02-failed-again.png)

### `FeatureTests/testChatHeaderStaysVisibleWhileTyping (light)`

<img src="screenshots/FeatureTests-testChatHeaderStaysVisibleWhileTyping-01-typing.png" width="260" alt="01-typing" title="01-typing">

[01-typing](screenshots/FeatureTests-testChatHeaderStaysVisibleWhileTyping-01-typing.png)

### `FeatureTests/testDeepLinkOpensSettings (light)`

<img src="screenshots/FeatureTests-testDeepLinkOpensSettings-01-settings-from-deep-link.png" width="260" alt="01-settings-from-deep-link" title="01-settings-from-deep-link">

[01-settings-from-deep-link](screenshots/FeatureTests-testDeepLinkOpensSettings-01-settings-from-deep-link.png)

### `FeatureTests/testHeadersStayBelowStatusBar (light)`

<img src="screenshots/FeatureTests-testHeadersStayBelowStatusBar-01-chat-list-header.png" width="260" alt="01-chat-list-header" title="01-chat-list-header">
<img src="screenshots/FeatureTests-testHeadersStayBelowStatusBar-02-chat-header.png" width="260" alt="02-chat-header" title="02-chat-header">

[01-chat-list-header](screenshots/FeatureTests-testHeadersStayBelowStatusBar-01-chat-list-header.png) · [02-chat-header](screenshots/FeatureTests-testHeadersStayBelowStatusBar-02-chat-header.png)

### `FeatureTests/testKeyboardHasNoFormToolbar (light)`

<img src="screenshots/FeatureTests-testKeyboardHasNoFormToolbar-01-keyboard.png" width="260" alt="01-keyboard" title="01-keyboard">

[01-keyboard](screenshots/FeatureTests-testKeyboardHasNoFormToolbar-01-keyboard.png)

### `FeatureTests/testLiquidgramSettingsShowIPhoneSection (light)`

<img src="screenshots/FeatureTests-testLiquidgramSettingsShowIPhoneSection-01-liquidgram-settings.png" width="260" alt="01-liquidgram-settings" title="01-liquidgram-settings">
<img src="screenshots/FeatureTests-testLiquidgramSettingsShowIPhoneSection-02-iphone-section.png" width="260" alt="02-iphone-section" title="02-iphone-section">

[01-liquidgram-settings](screenshots/FeatureTests-testLiquidgramSettingsShowIPhoneSection-01-liquidgram-settings.png) · [02-iphone-section](screenshots/FeatureTests-testLiquidgramSettingsShowIPhoneSection-02-iphone-section.png)

### `FeatureTests/testPrivacyShieldCoversAppWhileInactive (light)`

<img src="screenshots/FeatureTests-testPrivacyShieldCoversAppWhileInactive-01-shield-under-notification-center.png" width="260" alt="01-shield-under-notification-center" title="01-shield-under-notification-center">
<img src="screenshots/FeatureTests-testPrivacyShieldCoversAppWhileInactive-02-shield-removed.png" width="260" alt="02-shield-removed" title="02-shield-removed">
<img src="screenshots/FeatureTests-testPrivacyShieldCoversAppWhileInactive-03-app-switcher.png" width="260" alt="03-app-switcher" title="03-app-switcher">

[01-shield-under-notification-center](screenshots/FeatureTests-testPrivacyShieldCoversAppWhileInactive-01-shield-under-notification-center.png) · [02-shield-removed](screenshots/FeatureTests-testPrivacyShieldCoversAppWhileInactive-02-shield-removed.png) · [03-app-switcher](screenshots/FeatureTests-testPrivacyShieldCoversAppWhileInactive-03-app-switcher.png)

### `FeatureTests/testQuickActionFocusesSearch (light)`

<img src="screenshots/FeatureTests-testQuickActionFocusesSearch-01-search-focused.png" width="260" alt="01-search-focused" title="01-search-focused">

[01-search-focused](screenshots/FeatureTests-testQuickActionFocusesSearch-01-search-focused.png)

### `FeatureTests/testQuickActionOpensNewMessage (light)`

<img src="screenshots/FeatureTests-testQuickActionOpensNewMessage-01-new-message.png" width="260" alt="01-new-message" title="01-new-message">

[01-new-message](screenshots/FeatureTests-testQuickActionOpensNewMessage-01-new-message.png)

### `FeatureTests/testQuickActionOpensSavedMessages (light)`

<img src="screenshots/FeatureTests-testQuickActionOpensSavedMessages-01-saved-messages.png" width="260" alt="01-saved-messages" title="01-saved-messages">

[01-saved-messages](screenshots/FeatureTests-testQuickActionOpensSavedMessages-01-saved-messages.png)

### `FeatureTests/testQuickActionTogglesGhostMode (light)`

<img src="screenshots/FeatureTests-testQuickActionTogglesGhostMode-01-ghost-mode-toast.png" width="260" alt="01-ghost-mode-toast" title="01-ghost-mode-toast">

[01-ghost-mode-toast](screenshots/FeatureTests-testQuickActionTogglesGhostMode-01-ghost-mode-toast.png)

### `ShellTests/testIPhoneStaysInPortrait (light)`

<img src="screenshots/ShellTests-testIPhoneStaysInPortrait-01-turned-sideways.png" width="260" alt="01-turned-sideways" title="01-turned-sideways">

[01-turned-sideways](screenshots/ShellTests-testIPhoneStaysInPortrait-01-turned-sideways.png)

### `ShellTests/testKeyboardResizesPageAndRestoresIt (light)`

<img src="screenshots/ShellTests-testKeyboardResizesPageAndRestoresIt-01-chat-list.png" width="260" alt="01-chat-list" title="01-chat-list">
<img src="screenshots/ShellTests-testKeyboardResizesPageAndRestoresIt-02-chat.png" width="260" alt="02-chat" title="02-chat">
<img src="screenshots/ShellTests-testKeyboardResizesPageAndRestoresIt-03-keyboard-up.png" width="260" alt="03-keyboard-up" title="03-keyboard-up">
<img src="screenshots/ShellTests-testKeyboardResizesPageAndRestoresIt-04-keyboard-hidden.png" width="260" alt="04-keyboard-hidden" title="04-keyboard-hidden">

[01-chat-list](screenshots/ShellTests-testKeyboardResizesPageAndRestoresIt-01-chat-list.png) · [02-chat](screenshots/ShellTests-testKeyboardResizesPageAndRestoresIt-02-chat.png) · [03-keyboard-up](screenshots/ShellTests-testKeyboardResizesPageAndRestoresIt-03-keyboard-up.png) · [04-keyboard-hidden](screenshots/ShellTests-testKeyboardResizesPageAndRestoresIt-04-keyboard-hidden.png)

### `ShellTests/testWindowOpenedLateShowsInAppBrowser (light)`

<img src="screenshots/ShellTests-testWindowOpenedLateShowsInAppBrowser-01-in-app-browser.png" width="260" alt="01-in-app-browser" title="01-in-app-browser">

[01-in-app-browser](screenshots/ShellTests-testWindowOpenedLateShowsInAppBrowser-01-in-app-browser.png)

### `CoreTests/testDemoAccount (dark)`

<img src="screenshots/CoreTests-testDemoAccount-01-chat-list-dark.png" width="260" alt="01-chat-list-dark" title="01-chat-list-dark">
<img src="screenshots/CoreTests-testDemoAccount-02-chat-dark.png" width="260" alt="02-chat-dark" title="02-chat-dark">
<img src="screenshots/CoreTests-testDemoAccount-03-composer-with-keyboard-dark.png" width="260" alt="03-composer-with-keyboard-dark" title="03-composer-with-keyboard-dark">

[01-chat-list-dark](screenshots/CoreTests-testDemoAccount-01-chat-list-dark.png) · [02-chat-dark](screenshots/CoreTests-testDemoAccount-02-chat-dark.png) · [03-composer-with-keyboard-dark](screenshots/CoreTests-testDemoAccount-03-composer-with-keyboard-dark.png)

