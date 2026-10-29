# Liquidgram UI tests

**Passed**: 8 passed, 0 failed, 1 skipped.

- Device: iPhone 16 Pro, iOS 18.6
- Branch: `ios-v2-scratch/fix-transport-ios18` at `d41e052`
- Run: https://github.com/levaasd142-cmd/liquidgram/actions/runs/40926030096
- Generated: 2026-10-29T18:03:11.063Z

## Tests

| Test | Pass | Status | Duration | Failure |
| --- | --- | --- | --- | --- |
| `TransportTests/testLegacyDataMovesToAppOrigin` | migration | Passed | 14.6 s |  |
| `CoreTests/testColdStartShowsApiKeysScreen` | light | Passed | 13.0 s |  |
| `CoreTests/testDemoAccount` | light | Passed | 13.8 s |  |
| `CoreTests/testDemoAccountSurvivesRestart` | light | Passed | 18.0 s |  |
| `CoreTests/testKeyboardKeepsFocusedFieldVisible` | light | Passed | 6.9 s |  |
| `CoreTests/testWebAppSelfTest` | light | Passed | 9.6 s |  |
| `TransportTests/testLegacyDataMovesToAppOrigin` | light | Skipped | 0.0 s | Test skipped - Needs the data of the loopback version; run-ui-tests.sh seeds it with UI_TESTS_LEGACY_REF |
| `TransportTests/testMediaStreamsFromPage` | light | Passed | 9.7 s |  |
| `CoreTests/testDemoAccount` | dark | Passed | 18.0 s |  |

## Self-test (migration)

| Check | Result | Detail |
| --- | --- | --- |
| `appOrigin` | ok | liquidgram-web://app |
| `migrationOutcome` | ok | moved 5 localStorage items, 3 IndexedDB records, 0 left out, 30179 bytes |
| `apiCredentials` | ok | the API keys of the loopback version |
| `session` | ok | account1 of user 100000 on DC 2 |
| `marker` | ok | the localStorage marker of legacy-seed.js |
| `typedValues` | ok | Blob, ArrayBuffer, Int16Array, Date, BigInt, Map, Set, undefined and NaN |
| `cachedState` | ok | the cached state with 8 chats |

<details><summary>Page details</summary>

```json
{
  "url": "liquidgram-web://app/",
  "localStorageKeys": [
    "account1",
    "lg-api-credentials",
    "liquidgram-test-legacy-marker",
    "tt-last-activity",
    "tt-multitab_1"
  ]
}
```

</details>

## Self-test (light)

| Check | Result | Detail |
| --- | --- | --- |
| `bridge` | ok | version 1.0.0, notification permission default |
| `notificationBridge` | ok | permission default |
| `noServiceWorker` | ok | service workers are unavailable |
| `appOrigin` | ok | liquidgram-web://app |
| `secureContext` | ok | liquidgram-web://app |
| `webCrypto` | ok | SHA-256 digest matches |
| `localStorage` | ok | write, read and remove work |
| `indexedDb` | ok | open, put and get work |
| `webAssembly` | ok | a module compiles and runs |
| `worker` | ok | a module worker from the app's origin answered (secure context true) |
| `fetchIndex` | ok | status 200, text/html; charset=utf-8 |
| `rangeRequest` | ok | /assets/index-CM-eP7_t.js: 206 with bytes 100-1123/159267 |
| `userAgentMobile` | ok | Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Liquidgram |
| `userAgentLiquidgram` | ok | Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Liquidgram |
| `appRendered` | ok | Transition full-height is-auth |
| `compatTest` | ok | passed |
| `noPageErrors` | ok | none since the page started |

<details><summary>Page details</summary>

```json
{
  "url": "liquidgram-web://app/",
  "userAgent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Liquidgram",
  "language": "en-US",
  "viewport": "402x874 at 3x",
  "colorScheme": "light",
  "backdropFilter": true,
  "blobWorker": "blocked: SecurityError: The operation is insecure.",
  "authScreen": true
}
```

</details>

## Self-test (light)

| Check | Result | Detail |
| --- | --- | --- |
| `appOrigin` | ok | liquidgram-web://app |
| `loadMediaPartRegistered` | ok | the web app set `window.__liquidgramNative.loadMediaPart` |
| `webAppChain` | ok | played in 778 ms, seeked in 537 ms and played to 2.21 s of 3 s; the web app downloaded parts 0, 3 of 4 |
| `probeRange` | ok | 206 bytes 0-1, video/mp4, nosniff, sandbox |
| `openRange` | ok | 206 with the first 524288 bytes |
| `unalignedRanges` | ok | across a part boundary and at the end of the file |
| `suffixRanges` | ok | with and without the size in the URL |
| `beyondEnd` | ok | 416 with bytes */1300000 |
| `wholeFile` | ok | GET without a range is 200 with every part in order; HEAD gives the size |
| `parallelRanges` | ok | 12 requests, at most 4 parts loading at once |
| `contentTypeGuard` | ok | text/html is served as application/octet-stream in a sandbox |
| `failedPart` | ok | the request failed (TypeError: Load failed), the next one worked |
| `abortedFetch` | ok | a request stopped while streaming leaves the stream working |
| `audioStreamsAndSeeks` | ok | played in 1293 ms, seeked in 622 ms and played to 24.62 s of 30 s; 2 of 6 parts were in when it started |
| `videoPlaysAndSeeks` | ok | played in 410 ms, seeked in 371 ms and played to 2.38 s of 3 s; parts 0, 3 of 4 were asked for |

<details><summary>Page details</summary>

```json
{
  "migrationOutcome": "nothing to move",
  "webAppChain": {
    "playingMs": 778,
    "duration": 3,
    "seekedMs": 537,
    "playedTo": 2.21,
    "parts": [
      0,
      3
    ]
  },
  "audio": {
    "playingMs": 1293,
    "partsBeforePlaying": 2,
    "duration": 30,
    "seekedMs": 622,
    "playedTo": 24.62,
    "requestedParts": [
      0,
      4,
      5
    ],
    "totalParts": 6,
    "seekPart": 4
  },
  "video": {
    "playingMs": 410,
    "partsBeforePlaying": 1,
    "duration": 3,
    "seekedMs": 371,
    "playedTo": 2.38,
    "requestedParts": [
      0,
      3
    ]
  }
}
```

</details>

Folders: [`screenshots/`](screenshots), [`ax/`](ax) (accessibility trees the tests attached), [`logs/`](logs) (app log, xcodebuild output, self-test reports).
