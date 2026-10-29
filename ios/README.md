# Liquidgram for iPhone

The iPhone app is a small UIKit app in Swift that shows the production web build in a full-screen `WKWebView`. The web build ships inside the app and is served by an HTTP server on the loopback interface, so the page has a fixed origin, `http://127.0.0.1:47821/`. A JavaScript bridge gives the page local notifications, the app icon badge and native permission prompts; downloads go to the share sheet.

The app targets iOS 16.4 and later on iPhone and iPad, the oldest version the web build supports. The build is an unsigned IPA that the user installs with [Sideloadly](https://sideloadly.io) and a free Apple ID; the Russian guide [УСТАНОВКА-IPHONE.txt](УСТАНОВКА-IPHONE.txt) walks through it.

## Build

### GitHub Actions

[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) runs on pushes to the default branch that touch the app or the web sources, and on demand from the Actions tab. On a `macos-15` runner it selects the latest stable Xcode, builds the web app (`npm ci`, `npm run build:production`), installs XcodeGen with Homebrew and runs `ios/build-ipa.sh`. The IPA is uploaded as the `Liquidgram-iOS` artifact and published as the asset of the `ios-latest` release, whose tag moves to the built commit and whose notes carry the version, the build number and the SHA-256. The release gives the IPA a permanent download link.

The build uses the newest stable Xcode on the runner image and its iOS SDK. The `macos-15` image has Xcode 16 and Xcode 26, so the app builds against the iOS 26 SDK and still runs on iOS 16; `runs-on: macos-26` moves the build to the newer image when it needs an Xcode release that `macos-15` lacks. On private repositories macOS minutes count against the free Actions quota at a higher rate than Linux minutes.

### On a Mac

Requirements: Xcode 16 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and the Node.js version in `.node-version`.

```bash
npm ci
npm run build:production
bash ios/build-ipa.sh            # or: bash ios/build-ipa.sh <repo-root> <dist-dir>
```

The script:

1. copies `dist` without source maps and PHP files into `ios/Liquidgram/WebApp`;
2. generates `ios/Liquidgram.xcodeproj` from [`project.yml`](project.yml) with XcodeGen;
3. builds the Release configuration for `generic/platform=iOS` with signing disabled, passing the version from `package.json` as `MARKETING_VERSION` and `BUILD_NUMBER` (default: the number of commits) as `CURRENT_PROJECT_VERSION`;
4. checks that the app bundle has its executable, `Assets.car`, `bridge.js` and `WebApp/index.html`;
5. packs `Payload/Liquidgram.app` into `dist-ios/Liquidgram.ipa` and prints its size and SHA-256.

The web build folder, the generated project and `dist-ios` are ignored by Git.

To work in Xcode, run the script once (or copy a web build into `ios/Liquidgram/WebApp`), run `xcodegen generate --spec ios/project.yml` and open `ios/Liquidgram.xcodeproj`. The simulator needs no signing. To run on a device from Xcode, set a development team and turn code signing back on, which `project.yml` turns off for the unsigned CI build.

## How it works

| File | Role |
| --- | --- |
| `Liquidgram/Sources/AppDelegate.swift` | Owns the server and the bridge, sets the notification delegate at launch, sets the `playback` audio session category |
| `Liquidgram/Sources/SceneDelegate.swift` | Creates the window; restarts the server and refreshes the notification permission when the app returns to the foreground |
| `Liquidgram/Sources/LocalServer.swift` | Loopback HTTP server for the web build |
| `Liquidgram/Sources/WebViewController.swift` | The web view, navigation policy, downloads, dialogs, camera and microphone access, status bar |
| `Liquidgram/Sources/NativeBridge.swift` | User scripts, the `liquidgram` message handler and local notifications |
| `Liquidgram/Resources/bridge.js` | Page side of the bridge: the `window.Notification` replacement and the badge |
| `Liquidgram/Info.plist`, `Resources/*.lproj` | Bundle settings and the usage descriptions in English and Russian |

### Local server

- **Origin.** All user data (the session, the API keys, the message cache) lives in website storage that belongs to the origin, so the port never changes. `http://127.0.0.1` is a secure context, so the page gets Web Crypto, media capture and storage like on HTTPS. `NSAllowsLocalNetworking` lets the web view load it under App Transport Security.
- **Listener.** An `NWListener` is bound to `127.0.0.1:47821` through `requiredLocalEndpoint`, so only processes on the device can connect, and loopback traffic needs no local network permission. `allowLocalEndpointReuse` lets a new listener take the port while sockets of closed connections are in `TIME_WAIT`.
- **Suspension.** iOS may reclaim the listening socket while the app is suspended (TN2277). `start()` does nothing while a listener is starting or running and replaces one that failed or was cancelled; the scene delegate calls it when the app returns to the foreground, and a failure restarts the listener after a delay that grows from 0.5 to 8 seconds. The web view waits for the ready state before it loads the page.
- **HTTP.** The server reads the request head, answers with `Connection: close` and closes the connection. It accepts only `GET` and `HEAD`, answers `421` to any `Host` other than `127.0.0.1:47821` or `localhost:47821` (DNS rebinding), and `400` to paths with dot segments, empty segments, backslashes or NUL after percent-decoding. `/` and paths ending with `/` map to `index.html`; anything else missing is `404`. Requests whose head is still incomplete after 30 seconds are dropped, heads over 32 KB get `431`.
- **Responses.** Content types come from an explicit table, the same as the desktop launcher's, with `application/octet-stream` as the fallback, and every response carries `X-Content-Type-Options: nosniff`. Content-hashed files in `assets/` are cached as immutable; everything else is revalidated. A single `bytes=` range gets `206` with `Content-Range`, which WebKit needs to play audio and video such as the notification sounds; other range forms get the whole file.

### Web view

- `WKWebsiteDataStore.default()` keeps the data between launches. Media plays inline without a user gesture. The default user agent gets `Liquidgram` appended. Web Inspector is enabled on iOS 16.4 and later.
- The page fills the screen: `contentInsetAdjustmentBehavior` is `.never`, so `viewport-fit=cover` and `env(safe-area-inset-*)` work. Rubber-band scrolling of the page, link previews and back/forward swipes are off. The status bar text follows the page's `theme-color`: light over dark themes, dark over light ones.
- Until the page draws, the view shows the launch screen color. If the page has not loaded after 10 seconds because the server or the load failed, a message with the error appears; it disappears when a retry succeeds. Failed loads retry after 1 to 8 seconds. When iOS ends the web process, the page reloads at once, or when the app becomes active again if it was in the background.
- **Navigation.** The main frame stays on the app's origin. Links to `http`, `https`, `mailto`, `tel` and `tg` open in other apps through `UIApplication.open`; other schemes are ignored. Frames inside the page, such as bot web apps and video embeds, load web pages in place. Links with `target="_blank"` and `window.open` open web pages in other apps too, and their `blob:` and `data:` URLs download; the web view never creates a second window.
- **Downloads.** A link with the `download` attribute, a response the web view cannot show and a `blob:` or `data:` URL in the main frame become `WKDownload`s. Each file is saved under its suggested name in a new folder in the temporary directory and offered in the share sheet (Save to Files, Save Image or Video, AirDrop), anchored as a popover on iPad. The folder is emptied at the next launch.
- **Dialogs and capture.** `alert`, `confirm` and `prompt` use `UIAlertController`. The app's own page gets the camera and the microphone without WebKit's per-site prompt; iOS asks once per permission. Other frames keep WebKit's prompt.

### Bridge contract

Both sides follow this contract; `bridge.js` implements the page side.

- At document start, before any page script, the app injects two user scripts into the main frame only:
  1. `window.__liquidgramNative = { platform: 'ios', version: '<CFBundleShortVersionString>', notificationPermission: 'default' | 'granted' | 'denied' }`. The permission maps the `UNUserNotificationCenter` authorization status: not determined is `default`; authorized, provisional and ephemeral are `granted`; denied is `denied`. The scripts are rebuilt whenever the status changes, so reloads start with the current value.
  2. `Resources/bridge.js`.
- The page posts plain objects to `window.webkit.messageHandlers.liquidgram`. The app accepts them only from the main frame of its own origin:
  - `{ type: 'requestNotificationPermission', requestId: number }` asks for alerts, sounds and badges;
  - `{ type: 'notify', tag: string, title: string, body: string, silent?: boolean }` shows a local notification at once, with the tag as its identifier, so a new notification with the same tag replaces the old one, and the default sound unless `silent` is true;
  - `{ type: 'closeNotification', tag: string }` removes the delivered notification;
  - `{ type: 'badge', count: number }` sets the app icon badge;
  - `{ type: 'log', level: string, message: string }` writes to the system log for debugging.
- The app calls back with `evaluateJavaScript` on the main thread, through optional chaining, so a call before `bridge.js` runs does nothing:
  - `window.__liquidgramNative.resolvePermission(requestId, state)` with `'granted'`, `'denied'` or `'default'`;
  - `window.__liquidgramNative.notificationClicked(tag)` when the user opens a notification;
  - `window.__liquidgramNative.setPermission(state)` after the app returns to the foreground, since the user may have changed the permission in Settings.
- While the app is active, notifications are not shown as banners, because the page shows new messages itself; while it is inactive, for example under Control Center, they show as a banner and in Notification Center with sound.
- The web app disables its service worker when `window.__liquidgramNative` exists: service workers in `WKWebView` need App-Bound Domains, which the app does not use.

## Free Apple ID

Sideloadly signs the IPA with a free Apple ID, which has a development certificate valid for 7 days and none of the paid capabilities. The app therefore uses no push notifications (`aps-environment`), App Groups, iCloud, Associated Domains, app extensions or background modes. The web app's own notifications work while it runs: in the foreground and for the few seconds iOS keeps a backgrounded app running.

Re-signing with the same Apple ID and bundle ID before or after the 7 days keeps all data. A different bundle ID, which Sideloadly sets with its "Change bundle ID" option when `org.liquidgram.messenger` is taken, installs a separate app with empty storage. A free Apple ID can have three sideloaded apps installed and create ten App IDs per seven days.

## Assets

`AppIcon.png` is a single 1024×1024 universal icon without an alpha channel; Xcode derives the other sizes. It is `src/assets/liquidgram-logo.svg` without the rounded corners, since iOS applies its own mask, rendered with Chromium and flattened with ImageMagick (`convert icon.png -alpha remove -alpha off -define png:color-type=2 PNG24:AppIcon.png`). `LaunchLogo` is the rounded logo at 120 points (120, 240 and 360 pixels) with transparency. `LaunchBackground` is lavender `#B9B4F5`, the web manifest's background color, and `#1C1A2E` in dark mode. Regenerate them when the logo changes.

## Limitations

- The IPA is unsigned, and the installation needs a computer with Sideloadly every 7 days, or Sideloadly's automatic refresh over Wi-Fi.
- No push notifications while the app is closed; see [Free Apple ID](#free-apple-id).
- Without a service worker, videos and large files download completely before they play, as in the browser extension.
- Other apps on the device can connect to `127.0.0.1:47821` as well. The server only serves the public web build, but an app that keeps running in the background could take the port while Liquidgram is suspended and serve its own page under Liquidgram's origin, which holds its data, when Liquidgram returns. This applies to every app that serves its content from a loopback port.
