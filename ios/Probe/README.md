# Transport probe

A simulator-only test app that compares the two ways the iPhone app can serve its bundled web build:

- `http://127.0.0.1:47821/` from `LocalServer`, a loopback HTTP server;
- `liquidgram-web://app/` from `AppSchemeHandler`, a `WKURLSchemeHandler`.

Both Swift files are compiled unchanged from `ios/Liquidgram/Sources`. The web view is configured like the app's and gets the same document-start scripts (the `window.__liquidgramNative` line and `bridge.js`), plus `Resources/probe-inject.js`, which reports console errors, uncaught errors, CSP violations, failed resources and the workers a page starts.

## What it checks

For each origin the app loads three pages and records the results in `Documents/probe-<phase>/report.json`, with a snapshot of each page:

| Page | Checks |
| --- | --- |
| `Pages/features.html` | Origin and secure context, Web Crypto, `crypto.randomUUID`, that `getUserMedia` exists (nothing is recorded), localStorage, IndexedDB and Cache Storage writes, `navigator.storage.persist`, Web Locks, classic and module scripts, dynamic import, `fetch` and XHR of build files, `HEAD`, 404, single ranges and 416, path traversal attempts, streaming WebAssembly compilation, images, fonts, classic and module dedicated workers with their own imports, fetches, WebAssembly and WebSocket, classic and module shared workers (their own script, and separately `importScripts`, `fetch` and static imports inside them), BroadcastChannel, CompressionStream and DecompressionStream, `blob:` URLs and a `blob:` download, audio and video playback with seeking (the bundled sounds, `nojs.mp4`, a 20-second H.264 video whose index sits at the end of the file and the same video from a `blob:` URL), a WebSocket to `wss://venus.web.telegram.org/apiws` from the page and from a worker (opened and closed, nothing sent), the History API |
| The real web app (`index.html`) | The API keys screen renders; the GramJS worker of the build starts and answers the `ping` of its protocol; the shared state worker answers; the opus-recorder workers of the build turn an OGG Opus voice message into WAV as `src/util/oggToWav.ts` does, and the WAV loads from a `blob:` URL; a reload renders the app again; no uncaught errors, unhandled rejections, CSP violations, failed resources or worker errors |
| `Pages/embed.html` | YouTube embeds with the sandbox of Instant View embeds, with and without the `origin` and `widget_referrer` parameters, and the `Referer` header that frame navigations carry |
| `Pages/media.html` | Four attempts each of seeking while playing (a video with its index at the end and a faststart copy), seeking while paused and seeking audio, after both origins ran once, so rare stalls show up as a rate |

`fetch-abort` cancels downloads of a 32 MB file after its first chunk and before any response, so WebKit stops scheme handler tasks midway; the request log shows them as `stopped by WebKit`.

Names that start with `info-` describe the environment or a limit worth knowing rather than a capability the web app needs today. `RecordingSchemeHandler` logs every request the scheme handler answered, including the `Range` headers WebKit sends for media. The report also lists the website data records of the default data store.

The runner launches the app twice. The first launch (`-ProbePhase main`) runs the checks and stores markers in localStorage, IndexedDB and Cache Storage; the second (`-ProbePhase verify`) reads them back after the relaunch, then removes all website data the way `TestHooks.prepareForLaunch` does and checks that the markers of both origins are gone.

## Running it

On a Mac with Xcode 16 or newer and XcodeGen:

```bash
npm ci && npm run build:production
python3 ios/Probe/prepare_webapp.py dist
xcodegen generate --spec ios/Probe/project.yml --project ios/Probe
xcodebuild -project ios/Probe/LiquidgramProbe.xcodeproj -scheme LiquidgramProbe -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/probe \
  CODE_SIGNING_ALLOWED=NO build
python3 ios/Probe/run_probe.py build/probe/Build/Products/Debug-iphonesimulator/LiquidgramProbe.app 26 results/ios-26 local
python3 ios/Probe/summarize.py results
```

`run_probe.py` creates a new simulator device for the newest runtime that matches the version prefix, runs both phases and copies the reports, snapshots, screenshots, the app's log, WebKit errors and any crash report to the output folder. `summarize.py` writes `summary.md` and `summary.json` and prints a GitHub annotation per runtime.
