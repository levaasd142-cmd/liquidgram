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

## Screenshots

All screenshots at a glance, with a band for the test's result: green passed, red failed, orange the moment of the failure.

<img src="contact-sheet.png" alt="Contact sheet of all screenshots">

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
<img src="screenshots/FeatureTests-testAppLockOpensAndLocksAgainAfterBackground-02-unlocked.png" width="260" alt="02-unlocked" title="02-unlocked">
<img src="screenshots/FeatureTests-testAppLockOpensAndLocksAgainAfterBackground-03-locked-after-background.png" width="260" alt="03-locked-after-background" title="03-locked-after-background">
<img src="screenshots/FeatureTests-testAppLockOpensAndLocksAgainAfterBackground-04-unlocked-again.png" width="260" alt="04-unlocked-again" title="04-unlocked-again">

[01-locked-at-launch](screenshots/FeatureTests-testAppLockOpensAndLocksAgainAfterBackground-01-locked-at-launch.png) · [02-unlocked](screenshots/FeatureTests-testAppLockOpensAndLocksAgainAfterBackground-02-unlocked.png) · [03-locked-after-background](screenshots/FeatureTests-testAppLockOpensAndLocksAgainAfterBackground-03-locked-after-background.png) · [04-unlocked-again](screenshots/FeatureTests-testAppLockOpensAndLocksAgainAfterBackground-04-unlocked-again.png)

### `FeatureTests/testAppLockStaysLockedWhenAuthenticationFails (light)`

<img src="screenshots/FeatureTests-testAppLockStaysLockedWhenAuthenticationFails-01-failed-authentication.png" width="260" alt="01-failed-authentication" title="01-failed-authentication">
<img src="screenshots/FeatureTests-testAppLockStaysLockedWhenAuthenticationFails-02-failed-again.png" width="260" alt="02-failed-again" title="02-failed-again">

[01-failed-authentication](screenshots/FeatureTests-testAppLockStaysLockedWhenAuthenticationFails-01-failed-authentication.png) · [02-failed-again](screenshots/FeatureTests-testAppLockStaysLockedWhenAuthenticationFails-02-failed-again.png)

### `FeatureTests/testDeepLinkOpensSettings (light)`

<img src="screenshots/FeatureTests-testDeepLinkOpensSettings-01-settings-from-deep-link.png" width="260" alt="01-settings-from-deep-link" title="01-settings-from-deep-link">

[01-settings-from-deep-link](screenshots/FeatureTests-testDeepLinkOpensSettings-01-settings-from-deep-link.png)

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

### `UsabilityTests/testAppStaysPortrait (light)`

<img src="screenshots/UsabilityTests-testAppStaysPortrait-01-portrait.png" width="260" alt="01-portrait" title="01-portrait">
<img src="screenshots/UsabilityTests-testAppStaysPortrait-02-device-turned.png" width="260" alt="02-device-turned" title="02-device-turned">

[01-portrait](screenshots/UsabilityTests-testAppStaysPortrait-01-portrait.png) · [02-device-turned](screenshots/UsabilityTests-testAppStaysPortrait-02-device-turned.png)

### `UsabilityTests/testAttachMenuAndEmojiPanelFitOnScreen (light)`

<img src="screenshots/UsabilityTests-testAttachMenuAndEmojiPanelFitOnScreen-01-attach-menu.png" width="260" alt="01-attach-menu" title="01-attach-menu">
<img src="screenshots/UsabilityTests-testAttachMenuAndEmojiPanelFitOnScreen-02-emoji-panel.png" width="260" alt="02-emoji-panel" title="02-emoji-panel">
<img src="screenshots/UsabilityTests-testAttachMenuAndEmojiPanelFitOnScreen-failure-the-panels-of-the-composer-the-emoji-tab-of-the.png" width="260" alt="failure-the-panels-of-the-composer-the-emoji-tab-of-the" title="failure-the-panels-of-the-composer-the-emoji-tab-of-the">

[01-attach-menu](screenshots/UsabilityTests-testAttachMenuAndEmojiPanelFitOnScreen-01-attach-menu.png) · [02-emoji-panel](screenshots/UsabilityTests-testAttachMenuAndEmojiPanelFitOnScreen-02-emoji-panel.png) · [failure-the-panels-of-the-composer-the-emoji-tab-of-the](screenshots/UsabilityTests-testAttachMenuAndEmojiPanelFitOnScreen-failure-the-panels-of-the-composer-the-emoji-tab-of-the.png)

### `UsabilityTests/testChatListTopRowWorks (light)`

<img src="screenshots/UsabilityTests-testChatListTopRowWorks-01-chat-list.png" width="260" alt="01-chat-list" title="01-chat-list">
<img src="screenshots/UsabilityTests-testChatListTopRowWorks-02-main-menu.png" width="260" alt="02-main-menu" title="02-main-menu">
<img src="screenshots/UsabilityTests-testChatListTopRowWorks-03-search.png" width="260" alt="03-search" title="03-search">
<img src="screenshots/UsabilityTests-testChatListTopRowWorks-04-ghost-mode.png" width="260" alt="04-ghost-mode" title="04-ghost-mode">

[01-chat-list](screenshots/UsabilityTests-testChatListTopRowWorks-01-chat-list.png) · [02-main-menu](screenshots/UsabilityTests-testChatListTopRowWorks-02-main-menu.png) · [03-search](screenshots/UsabilityTests-testChatListTopRowWorks-03-search.png) · [04-ghost-mode](screenshots/UsabilityTests-testChatListTopRowWorks-04-ghost-mode.png)

### `UsabilityTests/testChatTopRowWorks (light)`

<img src="screenshots/UsabilityTests-testChatTopRowWorks-01-chat.png" width="260" alt="01-chat" title="01-chat">
<img src="screenshots/UsabilityTests-testChatTopRowWorks-02-chat-menu.png" width="260" alt="02-chat-menu" title="02-chat-menu">
<img src="screenshots/UsabilityTests-testChatTopRowWorks-03-profile.png" width="260" alt="03-profile" title="03-profile">
<img src="screenshots/UsabilityTests-testChatTopRowWorks-04-chat-list-after-back.png" width="260" alt="04-chat-list-after-back" title="04-chat-list-after-back">

[01-chat](screenshots/UsabilityTests-testChatTopRowWorks-01-chat.png) · [02-chat-menu](screenshots/UsabilityTests-testChatTopRowWorks-02-chat-menu.png) · [03-profile](screenshots/UsabilityTests-testChatTopRowWorks-03-profile.png) · [04-chat-list-after-back](screenshots/UsabilityTests-testChatTopRowWorks-04-chat-list-after-back.png)

### `UsabilityTests/testDelayedWindowOpenShowsInAppBrowser (light)`

<img src="screenshots/UsabilityTests-testDelayedWindowOpenShowsInAppBrowser-01-in-app-browser.png" width="260" alt="01-in-app-browser" title="01-in-app-browser">

[01-in-app-browser](screenshots/UsabilityTests-testDelayedWindowOpenShowsInAppBrowser-01-in-app-browser.png)

### `UsabilityTests/testDraggingMessagesHidesKeyboard (light)`

<img src="screenshots/UsabilityTests-testDraggingMessagesHidesKeyboard-01-keyboard-up.png" width="260" alt="01-keyboard-up" title="01-keyboard-up">
<img src="screenshots/UsabilityTests-testDraggingMessagesHidesKeyboard-02-after-drag.png" width="260" alt="02-after-drag" title="02-after-drag">
<img src="screenshots/UsabilityTests-testDraggingMessagesHidesKeyboard-failure-the-keyboard-stayed-up-after-a-drag-down-on-the.png" width="260" alt="failure-the-keyboard-stayed-up-after-a-drag-down-on-the" title="failure-the-keyboard-stayed-up-after-a-drag-down-on-the">

[01-keyboard-up](screenshots/UsabilityTests-testDraggingMessagesHidesKeyboard-01-keyboard-up.png) · [02-after-drag](screenshots/UsabilityTests-testDraggingMessagesHidesKeyboard-02-after-drag.png) · [failure-the-keyboard-stayed-up-after-a-drag-down-on-the](screenshots/UsabilityTests-testDraggingMessagesHidesKeyboard-failure-the-keyboard-stayed-up-after-a-drag-down-on-the.png)

### `UsabilityTests/testKeyboardKeepsChatLayout (light)`

<img src="screenshots/UsabilityTests-testKeyboardKeepsChatLayout-01-chat.png" width="260" alt="01-chat" title="01-chat">
<img src="screenshots/UsabilityTests-testKeyboardKeepsChatLayout-02-keyboard.png" width="260" alt="02-keyboard" title="02-keyboard">
<img src="screenshots/UsabilityTests-testKeyboardKeepsChatLayout-03-keyboard-hidden.png" width="260" alt="03-keyboard-hidden" title="03-keyboard-hidden">
<img src="screenshots/UsabilityTests-testKeyboardKeepsChatLayout-04-after-keyboard-cycles.png" width="260" alt="04-after-keyboard-cycles" title="04-after-keyboard-cycles">
<img src="screenshots/UsabilityTests-testKeyboardKeepsChatLayout-failure-the-chat-with-the-keyboard-the-page-scrolled.png" width="260" alt="failure-the-chat-with-the-keyboard-the-page-scrolled" title="failure-the-chat-with-the-keyboard-the-page-scrolled">

[01-chat](screenshots/UsabilityTests-testKeyboardKeepsChatLayout-01-chat.png) · [02-keyboard](screenshots/UsabilityTests-testKeyboardKeepsChatLayout-02-keyboard.png) · [03-keyboard-hidden](screenshots/UsabilityTests-testKeyboardKeepsChatLayout-03-keyboard-hidden.png) · [04-after-keyboard-cycles](screenshots/UsabilityTests-testKeyboardKeepsChatLayout-04-after-keyboard-cycles.png) · [failure-the-chat-with-the-keyboard-the-page-scrolled](screenshots/UsabilityTests-testKeyboardKeepsChatLayout-failure-the-chat-with-the-keyboard-the-page-scrolled.png)

### `UsabilityTests/testLongPressOnMessageOpensMenu (light)`

<img src="screenshots/UsabilityTests-testLongPressOnMessageOpensMenu-01-message-menu.png" width="260" alt="01-message-menu" title="01-message-menu">
<img src="screenshots/UsabilityTests-testLongPressOnMessageOpensMenu-02-reply.png" width="260" alt="02-reply" title="02-reply">

[01-message-menu](screenshots/UsabilityTests-testLongPressOnMessageOpensMenu-01-message-menu.png) · [02-reply](screenshots/UsabilityTests-testLongPressOnMessageOpensMenu-02-reply.png)

### `UsabilityTests/testMediaViewerOpensAndCloses (light)`

<img src="screenshots/UsabilityTests-testMediaViewerOpensAndCloses-01-chat-with-photo.png" width="260" alt="01-chat-with-photo" title="01-chat-with-photo">
<img src="screenshots/UsabilityTests-testMediaViewerOpensAndCloses-02-media-viewer.png" width="260" alt="02-media-viewer" title="02-media-viewer">
<img src="screenshots/UsabilityTests-testMediaViewerOpensAndCloses-03-media-viewer-closed.png" width="260" alt="03-media-viewer-closed" title="03-media-viewer-closed">

[01-chat-with-photo](screenshots/UsabilityTests-testMediaViewerOpensAndCloses-01-chat-with-photo.png) · [02-media-viewer](screenshots/UsabilityTests-testMediaViewerOpensAndCloses-02-media-viewer.png) · [03-media-viewer-closed](screenshots/UsabilityTests-testMediaViewerOpensAndCloses-03-media-viewer-closed.png)

### `UsabilityTests/testPageIsActiveBeforeFirstTap (light)`

<img src="screenshots/UsabilityTests-testPageIsActiveBeforeFirstTap-01-chat-list-untouched.png" width="260" alt="01-chat-list-untouched" title="01-chat-list-untouched">

[01-chat-list-untouched](screenshots/UsabilityTests-testPageIsActiveBeforeFirstTap-01-chat-list-untouched.png)

### `UsabilityTests/testProfileTopRowWorks (light)`

<img src="screenshots/UsabilityTests-testProfileTopRowWorks-01-profile.png" width="260" alt="01-profile" title="01-profile">
<img src="screenshots/UsabilityTests-testProfileTopRowWorks-02-edit-contact.png" width="260" alt="02-edit-contact" title="02-edit-contact">
<img src="screenshots/UsabilityTests-testProfileTopRowWorks-03-chat-after-back.png" width="260" alt="03-chat-after-back" title="03-chat-after-back">

[01-profile](screenshots/UsabilityTests-testProfileTopRowWorks-01-profile.png) · [02-edit-contact](screenshots/UsabilityTests-testProfileTopRowWorks-02-edit-contact.png) · [03-chat-after-back](screenshots/UsabilityTests-testProfileTopRowWorks-03-chat-after-back.png)

### `UsabilityTests/testSettingsTopRowWorks (light)`

<img src="screenshots/UsabilityTests-testSettingsTopRowWorks-01-settings.png" width="260" alt="01-settings" title="01-settings">
<img src="screenshots/UsabilityTests-testSettingsTopRowWorks-02-settings-menu.png" width="260" alt="02-settings-menu" title="02-settings-menu">
<img src="screenshots/UsabilityTests-testSettingsTopRowWorks-03-settings-search.png" width="260" alt="03-settings-search" title="03-settings-search">
<img src="screenshots/UsabilityTests-testSettingsTopRowWorks-04-edit-profile.png" width="260" alt="04-edit-profile" title="04-edit-profile">
<img src="screenshots/UsabilityTests-testSettingsTopRowWorks-05-chat-list.png" width="260" alt="05-chat-list" title="05-chat-list">

[01-settings](screenshots/UsabilityTests-testSettingsTopRowWorks-01-settings.png) · [02-settings-menu](screenshots/UsabilityTests-testSettingsTopRowWorks-02-settings-menu.png) · [03-settings-search](screenshots/UsabilityTests-testSettingsTopRowWorks-03-settings-search.png) · [04-edit-profile](screenshots/UsabilityTests-testSettingsTopRowWorks-04-edit-profile.png) · [05-chat-list](screenshots/UsabilityTests-testSettingsTopRowWorks-05-chat-list.png)

### `UsabilityTests/testStatusBarStripMatchesTheme (light)`

<img src="screenshots/UsabilityTests-testStatusBarStripMatchesTheme-01-status-bar-strip.png" width="260" alt="01-status-bar-strip" title="01-status-bar-strip">

[01-status-bar-strip](screenshots/UsabilityTests-testStatusBarStripMatchesTheme-01-status-bar-strip.png)

### `CoreTests/testDemoAccount (dark)`

<img src="screenshots/CoreTests-testDemoAccount-01-chat-list-dark.png" width="260" alt="01-chat-list-dark" title="01-chat-list-dark">
<img src="screenshots/CoreTests-testDemoAccount-02-chat-dark.png" width="260" alt="02-chat-dark" title="02-chat-dark">
<img src="screenshots/CoreTests-testDemoAccount-03-composer-with-keyboard-dark.png" width="260" alt="03-composer-with-keyboard-dark" title="03-composer-with-keyboard-dark">

[01-chat-list-dark](screenshots/CoreTests-testDemoAccount-01-chat-list-dark.png) · [02-chat-dark](screenshots/CoreTests-testDemoAccount-02-chat-dark.png) · [03-composer-with-keyboard-dark](screenshots/CoreTests-testDemoAccount-03-composer-with-keyboard-dark.png)

### `UsabilityTests/testStatusBarStripMatchesTheme (dark)`

<img src="screenshots/UsabilityTests-testStatusBarStripMatchesTheme-01-status-bar-strip-dark.png" width="260" alt="01-status-bar-strip-dark" title="01-status-bar-strip-dark">

[01-status-bar-strip-dark](screenshots/UsabilityTests-testStatusBarStripMatchesTheme-01-status-bar-strip-dark.png)

