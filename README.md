# Liquidgram UI tests

**Passed**: 8 passed, 0 failed, 1 skipped.

- Device: iPhone 17 Pro, iOS 26.2
- Branch: `ios-v2/fix-gestures-web` at `1703332`
- Run: https://github.com/levaasd142-cmd/liquidgram/actions/runs/40930670859
- Generated: 2026-10-29T18:44:23.900Z

## Tests

| Test | Pass | Status | Duration | Failure |
| --- | --- | --- | --- | --- |
| `CoreTests/testDemoAccount` | light | Passed | 67.0 s |  |
| `GestureTests/testChatListRightSwipeKeepsChatList` | light | Passed | 22.0 s |  |
| `GestureTests/testLongPressOpensMessageMenu` | light | Passed | 23.3 s |  |
| `GestureTests/testSlowShortSwipeSpringsBack` | light | Passed | 22.2 s |  |
| `GestureTests/testSwipeBackClosesProfile` | light | Skipped | 13.0 s | Test skipped - The chat header is under the status bar, which takes the tap that opens the profile |
| `GestureTests/testSwipeBackFromEdgeClosesChat` | light | Passed | 49.6 s |  |
| `GestureTests/testSwipeBackFromMiddleClosesChat` | light | Passed | 14.5 s |  |
| `GestureTests/testSwipeToReply` | light | Passed | 14.7 s |  |
| `CoreTests/testDemoAccount` | dark | Passed | 41.6 s |  |

Folders: [`screenshots/`](screenshots), [`ax/`](ax) (accessibility trees the tests attached), [`logs/`](logs) (app log, xcodebuild output, self-test reports).

## Screenshots

### `CoreTests/testDemoAccount (light)`

<img src="screenshots/CoreTests-testDemoAccount-01-chat-list.png" width="260" alt="01-chat-list" title="01-chat-list">
<img src="screenshots/CoreTests-testDemoAccount-02-chat.png" width="260" alt="02-chat" title="02-chat">
<img src="screenshots/CoreTests-testDemoAccount-03-composer-with-keyboard.png" width="260" alt="03-composer-with-keyboard" title="03-composer-with-keyboard">

[01-chat-list](screenshots/CoreTests-testDemoAccount-01-chat-list.png) · [02-chat](screenshots/CoreTests-testDemoAccount-02-chat.png) · [03-composer-with-keyboard](screenshots/CoreTests-testDemoAccount-03-composer-with-keyboard.png)

### `GestureTests/testChatListRightSwipeKeepsChatList (light)`

<img src="screenshots/GestureTests-testChatListRightSwipeKeepsChatList-01-chat-list.png" width="260" alt="01-chat-list" title="01-chat-list">
<img src="screenshots/GestureTests-testChatListRightSwipeKeepsChatList-02-chat-list-after-right-swipe.png" width="260" alt="02-chat-list-after-right-swipe" title="02-chat-list-after-right-swipe">

[01-chat-list](screenshots/GestureTests-testChatListRightSwipeKeepsChatList-01-chat-list.png) · [02-chat-list-after-right-swipe](screenshots/GestureTests-testChatListRightSwipeKeepsChatList-02-chat-list-after-right-swipe.png)

### `GestureTests/testLongPressOpensMessageMenu (light)`

<img src="screenshots/GestureTests-testLongPressOpensMessageMenu-01-chat.png" width="260" alt="01-chat" title="01-chat">
<img src="screenshots/GestureTests-testLongPressOpensMessageMenu-02-message-menu.png" width="260" alt="02-message-menu" title="02-message-menu">
<img src="screenshots/GestureTests-testLongPressOpensMessageMenu-03-reply-from-menu.png" width="260" alt="03-reply-from-menu" title="03-reply-from-menu">

[01-chat](screenshots/GestureTests-testLongPressOpensMessageMenu-01-chat.png) · [02-message-menu](screenshots/GestureTests-testLongPressOpensMessageMenu-02-message-menu.png) · [03-reply-from-menu](screenshots/GestureTests-testLongPressOpensMessageMenu-03-reply-from-menu.png)

### `GestureTests/testSlowShortSwipeSpringsBack (light)`

<img src="screenshots/GestureTests-testSlowShortSwipeSpringsBack-01-chat.png" width="260" alt="01-chat" title="01-chat">
<img src="screenshots/GestureTests-testSlowShortSwipeSpringsBack-02-chat-after-short-swipe.png" width="260" alt="02-chat-after-short-swipe" title="02-chat-after-short-swipe">

[01-chat](screenshots/GestureTests-testSlowShortSwipeSpringsBack-01-chat.png) · [02-chat-after-short-swipe](screenshots/GestureTests-testSlowShortSwipeSpringsBack-02-chat-after-short-swipe.png)

### `GestureTests/testSwipeBackClosesProfile (light)`

<img src="screenshots/GestureTests-testSwipeBackClosesProfile-01-chat.png" width="260" alt="01-chat" title="01-chat">

[01-chat](screenshots/GestureTests-testSwipeBackClosesProfile-01-chat.png)

### `GestureTests/testSwipeBackFromEdgeClosesChat (light)`

<img src="screenshots/GestureTests-testSwipeBackFromEdgeClosesChat-01-chat.png" width="260" alt="01-chat" title="01-chat">
<img src="screenshots/GestureTests-testSwipeBackFromEdgeClosesChat-02-chat-list-after-edge-swipe.png" width="260" alt="02-chat-list-after-edge-swipe" title="02-chat-list-after-edge-swipe">

[01-chat](screenshots/GestureTests-testSwipeBackFromEdgeClosesChat-01-chat.png) · [02-chat-list-after-edge-swipe](screenshots/GestureTests-testSwipeBackFromEdgeClosesChat-02-chat-list-after-edge-swipe.png)

### `GestureTests/testSwipeBackFromMiddleClosesChat (light)`

<img src="screenshots/GestureTests-testSwipeBackFromMiddleClosesChat-01-chat.png" width="260" alt="01-chat" title="01-chat">
<img src="screenshots/GestureTests-testSwipeBackFromMiddleClosesChat-02-chat-list-after-middle-swipe.png" width="260" alt="02-chat-list-after-middle-swipe" title="02-chat-list-after-middle-swipe">

[01-chat](screenshots/GestureTests-testSwipeBackFromMiddleClosesChat-01-chat.png) · [02-chat-list-after-middle-swipe](screenshots/GestureTests-testSwipeBackFromMiddleClosesChat-02-chat-list-after-middle-swipe.png)

### `GestureTests/testSwipeToReply (light)`

<img src="screenshots/GestureTests-testSwipeToReply-01-chat.png" width="260" alt="01-chat" title="01-chat">
<img src="screenshots/GestureTests-testSwipeToReply-02-reply-from-swipe.png" width="260" alt="02-reply-from-swipe" title="02-reply-from-swipe">

[01-chat](screenshots/GestureTests-testSwipeToReply-01-chat.png) · [02-reply-from-swipe](screenshots/GestureTests-testSwipeToReply-02-reply-from-swipe.png)

### `CoreTests/testDemoAccount (dark)`

<img src="screenshots/CoreTests-testDemoAccount-01-chat-list-dark.png" width="260" alt="01-chat-list-dark" title="01-chat-list-dark">
<img src="screenshots/CoreTests-testDemoAccount-02-chat-dark.png" width="260" alt="02-chat-dark" title="02-chat-dark">
<img src="screenshots/CoreTests-testDemoAccount-03-composer-with-keyboard-dark.png" width="260" alt="03-composer-with-keyboard-dark" title="03-composer-with-keyboard-dark">

[01-chat-list-dark](screenshots/CoreTests-testDemoAccount-01-chat-list-dark.png) · [02-chat-dark](screenshots/CoreTests-testDemoAccount-02-chat-dark.png) · [03-composer-with-keyboard-dark](screenshots/CoreTests-testDemoAccount-03-composer-with-keyboard-dark.png)

