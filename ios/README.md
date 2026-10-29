# Liquidgram for iPhone

The iPhone app is a UIKit app in Swift that shows the production web build in a full-screen `WKWebView`. The web build ships inside the app and is served by an HTTP server on the loopback interface, so the page has a fixed origin, `http://127.0.0.1:47821/`. A JavaScript bridge gives the page local notifications, the app icon badge, haptics, native settings and actions; downloads go to the share sheet.

Native features:

- **App lock** with Face ID, Touch ID or Optic ID and the device passcode as the fallback, right at launch and again after the app was in the background for a chosen time.
- **Privacy shield**: the app switcher shows a blur with the logo instead of the chats.
- **Quick actions** on the home-screen icon: Saved Messages, Search, New Message and Ghost Mode.
- **Siri and Shortcuts**: the same four actions and Open Chat by username, with phrases in English and Russian.
- **Links**: `tg:` and `liquidgram:` links open in the app.
- **In-app browser** for web links, haptic feedback, a tap on the status bar that scrolls the chat list to the top, no Previous/Next/Done bar above the keyboard, alternate app icons, playback in the background, Picture in Picture and AirPlay.

The app targets iOS 16.4 and later on iPhone and iPad, the oldest version the web build supports. The build is an unsigned IPA that the user installs with [Sideloadly](https://sideloadly.io) and a free Apple ID; the Russian guide [УСТАНОВКА-IPHONE.txt](УСТАНОВКА-IPHONE.txt) walks through it.

## Build

### GitHub Actions

[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) runs on pushes to the default branch that touch the app or the web sources, and on demand from the Actions tab. A Linux job builds the web app (`npm ci`, `npm run build:production`); a `macos-15` job selects the latest stable Xcode, downloads that build, installs XcodeGen with Homebrew and runs `ios/build-ipa.sh`. The IPA is uploaded as the `Liquidgram-iOS` artifact and, on the default branch, published as the asset of the `ios-latest` release, whose tag moves to the built commit and whose notes carry the version, the build number and the SHA-256. The release gives the IPA a permanent download link. When the build fails, the compiler errors appear as an annotation of the run.

The build uses the newest stable Xcode on the runner image and its iOS SDK. The `macos-15` image has Xcode 16 and Xcode 26, so the app builds against the iOS 26 SDK and still runs on iOS 16.4; `runs-on: macos-26` moves the build to the newer image when it needs an Xcode release that `macos-15` lacks. On private repositories macOS minutes count against the free Actions quota at a higher rate than Linux minutes.

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
| `Liquidgram/Sources/AppDelegate.swift` | Owns the server and the bridge, registers the setting defaults, sets the notification delegate and the `playback` audio session category |
| `Liquidgram/Sources/SceneDelegate.swift` | Creates the window and the app lock; forwards the scene lifecycle; turns quick actions and links into native actions |
| `Liquidgram/Sources/LocalServer.swift` | Loopback HTTP server for the web build |
| `Liquidgram/Sources/WebViewController.swift` | The web view, navigation policy, in-app browser, downloads, dialogs, camera and microphone access, status bar and its tap |
| `Liquidgram/Sources/NativeBridge.swift` | User scripts, the `liquidgram` message handler, local notifications, the badge, haptics and the delivery of native actions |
| `Liquidgram/Sources/NativeRequests.swift` | Answers the page's requests to read and change the native settings and the app icon |
| `Liquidgram/Sources/NativeSettings.swift` | The native settings in `UserDefaults` and their snapshot for the page |
| `Liquidgram/Sources/NativeActions.swift` | Native actions and how quick actions, links and usernames map to them |
| `Liquidgram/Sources/AppLock.swift`, `LockViewController.swift`, `PrivacyShield.swift`, `DeviceAuthentication.swift` | The app lock, its screen, the privacy shield and LocalAuthentication |
| `Liquidgram/Sources/AppIntents.swift` | Siri and Shortcuts actions and their phrases |
| `Liquidgram/Sources/Haptics.swift` | Haptic feedback for the page |
| `Liquidgram/Sources/TestHooks.swift` | Hooks for the UI tests, active in Debug builds only |
| `Liquidgram/Resources/bridge.js` | Page side of the bridge: the `window.Notification` replacement, the badge, `navigator.vibrate` and the API of `window.__liquidgramNative` |
| `Liquidgram/Info.plist`, `Resources/*.lproj` | Bundle settings, quick actions, URL schemes, the usage descriptions and the native strings in English and Russian; `ru.lproj/AppShortcuts.strings` holds the Russian Siri phrases |

### Local server

- **Origin.** All user data (the session, the API keys, the message cache) lives in website storage that belongs to the origin, so the port never changes. `http://127.0.0.1` is a secure context, so the page gets Web Crypto, media capture and storage like on HTTPS. `NSAllowsLocalNetworking` lets the web view load it under App Transport Security.
- **Listener.** An `NWListener` is bound to `127.0.0.1:47821` through `requiredLocalEndpoint`, so only processes on the device can connect, and loopback traffic needs no local network permission. The listener never shares the port: `allowLocalEndpointReuse` stays off, because with `SO_REUSEPORT` another app could bind the same address and receive the web view's requests. Instead, the client closes every connection first (see HTTP), so the `TIME_WAIT` state stays with the client's port and a new listener can take the server's port at once.
- **Suspension and ownership.** iOS may reclaim the listening socket while the app is suspended (TN2277), and another app could take the free port meanwhile. The web view therefore loads or reloads a page only once connections are known to reach this app's listener: right after the listener binds, since nothing else can hold the port then, or after a probe request with a random path has reached it. When the app returns to the foreground, the server probes its listener at once. A listener that failed or no longer receives connections is replaced, after a delay that grows from 0.5 to 8 seconds for repeated failures. When another process accepts the probe or holds the port, the web view replaces the page with a blank one and loads it again once the port is the app's own.
- **HTTP.** The server reads the request head and answers with `Connection: close` and a `Content-Length`, which makes the client close the connection once it has read the response; the server reads the connection until then. Every connection is closed after 30 seconds, whatever its state. The server accepts only `GET` and `HEAD`, answers `421` to any `Host` other than `127.0.0.1:47821` or `localhost:47821` (DNS rebinding), and `400` to paths with dot segments, empty segments, backslashes or NUL after percent-decoding. `/` and paths ending with `/` map to `index.html`; anything else missing is `404`. Heads over 32 KB get `431`.
- **Responses.** Content types come from an explicit table, the same as the desktop launcher's, with `application/octet-stream` as the fallback, and every response carries `X-Content-Type-Options: nosniff`. Content-hashed files in `assets/` are cached as immutable; everything else is revalidated. A single `bytes=` range gets `206` with `Content-Range`, which WebKit needs to play audio and video such as the notification sounds; other range forms get the whole file.

### Web view

- `WKWebsiteDataStore.default()` keeps the data between launches. Media plays inline without a user gesture, in Picture in Picture and over AirPlay. `Liquidgram` follows WebKit's own `Mobile/…` token in the user agent, so bot web apps and embeds choose their mobile layout. Web Inspector is enabled on iOS 16.4 and later.
- The page fills the screen: `contentInsetAdjustmentBehavior` is `.never`, so `viewport-fit=cover` and `env(safe-area-inset-*)` work. Rubber-band scrolling of the page, link previews and back/forward swipes are off. The status bar text follows the page's `theme-color`: light over dark themes, dark over light ones.
- **Keyboard.** The web view's `inputAccessoryView` is `nil`; WebKit's content view asks the web view for it, so no Previous/Next/Done bar appears above the keyboard.
- **Status bar tap.** UIKit offers the tap only to a scroll view that can scroll, and the page's own scroll view never does, since the web app scrolls elements inside the page. An invisible scroll view behind the web view takes the tap, does not scroll, and sends the `scrollToTop` action instead.
- Until the page draws, the view shows the launch screen color. If the page has not loaded after 10 seconds because the server or the load failed, a message with the error appears; it disappears when a retry succeeds. Failed loads retry after 1 to 8 seconds. When iOS ends the web process, the page reloads at once, or when the app becomes active again if it was in the background.
- **Navigation.** The main frame stays on the app's origin. Links to `http`, `https`, `mailto`, `tel` and `tg` leave the page; other schemes are ignored. Web links open in an app that claims them as universal links, such as YouTube, and otherwise in the in-app browser (`SFSafariViewController`), or in Safari when the user turned the in-app browser off. `mailto`, `tel` and `tg` links always go to other apps through `UIApplication.open`. Frames inside the page, such as bot web apps and video embeds, load web pages in place. Links with `target="_blank"` and `window.open` follow the same rules, and their `blob:` and `data:` URLs download; the web view never creates a second window.
- **Downloads.** A link with the `download` attribute, a response the web view cannot show and a `blob:` or `data:` URL in the main frame become `WKDownload`s. Each file is saved under its suggested name in a new folder in the temporary directory and offered in the share sheet (Save to Files, Save Image or Video, AirDrop), anchored as a popover on iPad. The folder is emptied at the next launch.
- **Dialogs and capture.** `alert`, `confirm` and `prompt` use `UIAlertController`. The app's own page gets the camera and the microphone without WebKit's per-site prompt; iOS asks once per permission. Other frames keep WebKit's prompt.

### App lock and privacy shield

- With the lock on, the app starts locked, and it locks again when it returns after at least `appLockDelay` seconds in the background (0 locks it every time). The time comes from the continuous clock, which counts while the device sleeps and ignores changes to the device clock. The web app can also lock at once with `{ type: 'lockNow' }`.
- The lock screen is a window above everything else, including alerts, share sheets and Safari views. It shows the app logo where the launch screen has it, "Liquidgram is locked" and an unlock button whose title and symbol follow the biometry: Face ID, Touch ID, Optic ID, or the passcode alone. It follows light and dark mode, keeps VoiceOver on itself and dismisses the keyboard. Authentication uses `LAPolicy.deviceOwnerAuthentication`, so the passcode works when biometry fails or is unavailable. It starts by itself when the scene becomes active after locking, and the button retries after a failure or a cancel. If the device no longer has a passcode, the app unlocks and turns the lock off.
- Native actions, such as a quick action that launched the locked app, wait until the app is unlocked.
- With the privacy shield or the lock on, a blur with the app logo covers the app whenever it resigns active and when it enters the background, so the app switcher shows no chats. It goes away when the app becomes active again, or after unlocking. A prompt that confirms a change of the lock setting does not raise it.

### Quick actions, links and Siri

- `UIApplicationShortcutItems` in `Info.plist` declare the quick actions; their titles are localized through `InfoPlist.strings`, keyed by the English title. The types are `org.liquidgram.messenger.savedMessages`, `.search`, `.newMessage` and `.ghostMode`.
- `CFBundleURLTypes` registers the `liquidgram` and `tg` schemes. `tg:X` goes to the page as is, `liquidgram:X` becomes `tg:X`, and `liquidgram://open?url=<link>` passes a URL-encoded `https://t.me/…`, `telegram.me`, `telegram.dog` or `tg:` link on. iOS picks one app for `tg` when the official Telegram app is installed as well.
- `AppIntents.swift` defines Open Saved Messages, Search Chats, New Message, Toggle Ghost Mode and Open Chat with a username parameter, which becomes `tg://resolve?domain=<username>`. They open the app and run like quick actions. An `AppShortcutsProvider` gives them Siri phrases that include the app name; `ru.lproj/AppShortcuts.strings` translates the phrases and `Localizable.strings` the titles.
- Quick actions and links that launch the app are read from the scene's connection options; later ones arrive through `windowScene(_:performActionFor:completionHandler:)` and `scene(_:openURLContexts:)`.

### Bridge contract

Both sides follow this contract; `bridge.js` implements the page side, and the page treats every member of `window.__liquidgramNative` as optional.

- At document start, before any page script, the app injects two user scripts into the main frame only:
  1. `window.__liquidgramNative = { platform: 'ios', version: '<CFBundleShortVersionString>', notificationPermission: 'default' | 'granted' | 'denied' }`. The permission maps the `UNUserNotificationCenter` authorization status: not determined is `default`; authorized, provisional and ephemeral are `granted`; denied is `denied`. The scripts are rebuilt whenever the status changes, so reloads start with the current value.
  2. `Resources/bridge.js`, which marks itself installed with `isBridgeInstalled` and does nothing when injected again.
- The page posts plain objects to `window.webkit.messageHandlers.liquidgram`. The app accepts them only from the main frame of its own origin and checks the type and range of every field:
  - `{ type: 'requestNotificationPermission', requestId: number }` asks for alerts, sounds and badges;
  - `{ type: 'notify', tag: string, title: string, body: string, silent?: boolean }` shows a local notification at once, with the tag as its identifier, so a new notification with the same tag replaces the old one, and the default sound unless `silent` is true;
  - `{ type: 'closeNotification', tag: string }` removes the delivered notification;
  - `{ type: 'badge', count: number }` sets the app icon badge;
  - `{ type: 'log', level: string, message: string }` writes to the system log for debugging;
  - `{ type: 'haptic', style }` plays `'selection'`, `'light'`, `'medium'`, `'heavy'`, `'soft'`, `'rigid'`, `'success'`, `'warning'` or `'error'`, at most one every 50 ms and only while haptics are on;
  - `{ type: 'lockNow' }` locks the app if the lock is on; `{ type: 'openSystemSettings' }` opens the app's page in the Settings app;
  - `{ type: 'appReady' }` says that the signed-in web app registered its action handler;
  - requests with a `requestId`, answered exactly once (see below).
- The app calls back with `evaluateJavaScript` on the main thread, through optional chaining, so a call before `bridge.js` runs does nothing. Every value it passes is JSON-encoded:
  - `resolvePermission(requestId, state)` with `'granted'`, `'denied'` or `'default'`;
  - `notificationClicked(tag)` when the user opens a notification;
  - `setPermission(state)` after the app returns to the foreground, since the user may have changed the permission in Settings;
  - `resolveRequest(requestId, response)` with the answer to a request;
  - `dispatchAction(action)` with a native action.
- `bridge.js` adds to `window.__liquidgramNative`:
  - `request(type, payload?)`: posts `{ ...payload, type, requestId }` and returns a promise of the response, which rejects after 30 seconds without one;
  - `haptic(style)` and `postMessage(message)`, which post without an answer;
  - `setActionHandler(handler)`: stores the handler and posts `appReady`, on every call, so a remount announces it again. `dispatchAction` calls the handler, or keeps up to 20 actions until one is set and then runs them in order;
  - and `navigator.vibrate(pattern)`, which `WKWebView` lacks: a single vibration plays `'medium'`, a pattern `'warning'`, and 0 or `[]` nothing.
- **Requests.** `getNativeSettings` answers `{ ok: true, settings }`. `setNativeSetting` with `{ key, value }` and `setAppIcon` with `{ name: string | null }` (`null` is the primary icon) answer `{ ok, error?, settings }`, where `error` is `'authFailed'`, `'cancelled'`, `'notAvailable'` or `'invalid'`, and `settings` is always the current snapshot. The keys are `appLockEnabled` (boolean; the app asks for Face ID, Touch ID, Optic ID or the passcode first, when turning it on and off), `appLockDelay` (0, 60, 300, 900 or 3600), `privacyShieldEnabled`, `hapticsEnabled` and `inAppBrowserEnabled` (booleans). A request of an unknown type is answered with `'invalid'`. A response never reaches a newer page than the one that asked.
- **Settings snapshot.** `{ appLockEnabled, appLockDelay, biometryType: 'faceID' | 'touchID' | 'opticID' | 'passcode' | 'none', privacyShieldEnabled, hapticsEnabled, inAppBrowserEnabled, appIcon: string | null, appIcons: string[], supportsAlternateIcons }`. `appIcons` lists the alternate icons that the bundle declares, in the order `AppIconMidnight`, `AppIconAurora`, `AppIconGlass`, `AppIconClassic`; the web build has square previews of them, and of the primary icon as `AppIcon.png`, in `ios-app-icons/`. `setAppIcon` switches the icon with `UIApplication.setAlternateIconName`, and iOS confirms every change with an alert. The values live in `UserDefaults.standard` with registered defaults: the lock off with a delay of 60 seconds, the privacy shield, haptics and the in-app browser on.
- **Actions.** `{ type: 'openSavedMessages' }`, `{ type: 'openSearch' }` (focuses the chat search), `{ type: 'newMessage' }` (the new private chat picker), `{ type: 'toggleGhostMode' }` (toggles it and shows a short toast with the new state), `{ type: 'openLink', url }` (a `tg:` or `https://t.me/` link for `openTelegramLink`) and `{ type: 'scrollToTop' }` (scrolls the visible chat list to the top). The app keeps up to 8 actions until the current page has reported `appReady` and the app is unlocked, and drops actions that waited longer than two minutes, for example while the user signed in. Readiness resets with every page load. A status bar tap that cannot be delivered right away is dropped.
- While the app is active, notifications are not shown as banners, because the page shows new messages itself. While Liquidgram is in the background for its first seconds, or inactive, for example under Control Center, they show as a banner and in Notification Center with sound.
- The web app disables its service worker when `window.__liquidgramNative` exists: service workers in `WKWebView` need App-Bound Domains, which the app does not use.

### Test hooks

`TestHooks.swift` serves the simulator UI tests and acts only in Debug builds; Release builds compile the same code with every hook turned off.

- Launch argument `-LiquidgramResetState YES` starts clean: the native settings and all web data are removed before the page loads. Arguments such as `-appLockEnabled YES` set native settings for one run.
- `LIQUIDGRAM_TEST_USER_SCRIPT` in the launch environment is base64 JavaScript that runs at document start before the app's scripts, for example to seed a demo account.
- `LIQUIDGRAM_TEST_SELFTEST_SCRIPT` is the base64 body of an async function that returns a string. It runs after `appReady`, or 5 seconds after the page first finished loading, and its result becomes the accessibility value of `liquidgram.selftest.result` and is logged in the `SelfTest` category.
- `-LiquidgramFakeAuthentication success|failure|cancel` skips LocalAuthentication: the lock gets this outcome after 0.3 seconds, or after the seconds of `-LiquidgramFakeAuthenticationDelay`, and the biometry reads as Face ID.
- `-LiquidgramTestAction <type>` performs that action after the first `appReady`, like a quick action.
- Accessibility identifiers: `liquidgram.webview`, `liquidgram.lock`, `liquidgram.lock.unlock`, `liquidgram.privacyShield`, `liquidgram.startupError` and `liquidgram.selftest.result`.

## Free Apple ID

Sideloadly signs the IPA with a free Apple ID, which has a development certificate valid for 7 days and none of the paid capabilities. The app therefore uses no push notifications (`aps-environment`), App Groups, iCloud, Associated Domains or app extensions. Its features need no entitlement: Face ID is a usage description, quick actions, URL schemes and the `audio` background mode are `Info.plist` keys, and App Intents are part of the app itself. The web app's own notifications work while it runs: in the foreground, for the few seconds iOS keeps a backgrounded app running, and while it plays audio in the background.

Re-signing with the same Apple ID and bundle ID before or after the 7 days keeps all data. A different bundle ID, which Sideloadly sets with its "Change bundle ID" option when `org.liquidgram.messenger` is taken, installs a separate app with empty storage. A free Apple ID can have three sideloaded apps installed and create ten App IDs per seven days.

## Assets

`AppIcon.png` is a single 1024×1024 universal icon without an alpha channel; Xcode derives the other sizes. It is `src/assets/liquidgram-logo.svg` without the rounded corners, since iOS applies its own mask, rendered with Chromium and flattened with ImageMagick (`convert icon.png -alpha remove -alpha off -define png:color-type=2 PNG24:AppIcon.png`). `LaunchLogo` is the rounded logo at 120 points (120, 240 and 360 pixels) with transparency. `LaunchBackground` is lavender `#B9B4F5`, the web manifest's background color, and `#1C1A2E` in dark mode. Regenerate them when the logo changes.

## Limitations

- The IPA is unsigned, and the installation needs a computer with Sideloadly every 7 days, or Sideloadly's automatic refresh over Wi-Fi.
- No push notifications while the app is closed; see [Free Apple ID](#free-apple-id).
- Without a service worker, videos and large files download completely before they play, as in the browser extension.
- Other apps on the device can connect to `127.0.0.1:47821` as well; the server only serves the public web build. While Liquidgram is suspended, another app that keeps running in the background could take the port if iOS reclaims Liquidgram's socket. The app checks the port before every load and as soon as it returns to the foreground, and drops the page while another process holds it, but a page that resumes can still send requests in the moment before that check completes. This applies to every app that serves its content from a loopback port.
- Playing audio in the background and Picture in Picture depend on WebKit, which can pause media when the page is hidden, for example video without Picture in Picture.
