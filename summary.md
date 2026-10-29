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
