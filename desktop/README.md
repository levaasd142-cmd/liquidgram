# Liquidgram desktop

The desktop app is a small Go launcher with the production web build embedded. It serves the build on a fixed loopback origin and shows it in an installed Chromium-based browser running in app mode, so the window has no tabs or address bar and the app keeps working like the web version: service worker, media streaming, notifications while open.

Windows is the main target (installer and portable zip). The Linux binary is the same launcher and is what the automated tests run.

## Build

Requirements: Node.js 24, Go 1.24 or newer, and NSIS 3 (`apt-get install nsis`, `brew install makensis` or the Windows installer from nsis.sourceforge.io).

```bash
npm run build:desktop
```

This runs `npm run build:production` and then `dev/buildDesktop.mjs`, which:

1. copies `dist` without source maps into `desktop/launcher/webapp` (ignored by Git) for `go:embed`;
2. runs `go vet` and `go test`;
3. generates the Windows resources (icon, version from `package.json`, manifest) with `go-winres`;
4. builds `Liquidgram.exe` (`windows/amd64`, GUI subsystem) and `liquidgram-linux-x64` with the version and a build ID, a hash of the launcher sources and the embedded web build;
5. packs `Liquidgram-Portable.zip` (the exe and a Russian `README.txt`) and builds `Liquidgram-Setup.exe` with `makensis`.

Everything lands in `dist-desktop/`. To package an existing web build: `node dev/buildDesktop.mjs --dist path/to/dist [--out dir] [--no-installer]`. The `GO` and `MAKENSIS` environment variables override the tool paths.

## How the launcher works

The code lives in `desktop/launcher`; platform files use the `_windows`, `_linux` and `_darwin` suffixes.

- **Origin.** All user data (session, API keys, message archive) lives in storage owned by the origin, so the port must not change. The launcher tries the port saved in `config.json`, then `47819`, `43819`, `39819`, `35819` and `31819`. These defaults sit below the Windows dynamic port range, and the first port that works is saved for good. A port set by hand in `config.json` may be any from 1024 to 65535. A port that belongs to another program is skipped for that run only, and a message explains why the window opens without the user's data.
- **Single instance.** Before it starts serving, each run writes a new secret token into `launcher-<port>.token` in the data folder, one file per port. When a port is taken, the launcher sends `GET /__liquidgram/ping?nonce=…` to whoever holds it. An instance of the same data folder answers with its instance ID, its build ID and an HMAC of the port and the nonce under the token. So the launcher sends the token only to a server that already knows it, never to a program that took the port, even one that passes the nonce on to the real instance on another port. It then calls `GET /__liquidgram/open` with the token in `X-Liquidgram-Token`, that instance opens another window, and the new launcher exits. The app page knows the token too, so this endpoint refuses requests that carry `Origin`, `Sec-Fetch-Site` or `Sec-Fetch-Mode`: browsers add these to every request to `127.0.0.1`, the launcher never does, and no script can open windows. If the running instance is another build, the user is told to close it to start this one. A launch never moves past a port whose program claims its data folder, because another port would show an empty profile. If that program does not prove itself or does not open a window, the launcher says that Liquidgram is already running or another program holds its port.
- **Server.** The server listens on `127.0.0.1` only and answers `421` to any `Host` other than `127.0.0.1:<port>` or `localhost:<port>`, which blocks DNS rebinding. It accepts only `GET` and `HEAD`, and paths with dot segments, empty segments or backslashes get `400`, so it serves embedded files only. Content types come from an explicit table in `server.go`, not from `mime.TypeByExtension`: on Windows the latter reads the registry, where other software can map `.js` or `.wasm` to `text/plain`. `go test` fails when the web build contains an extension the table lacks. Every response carries `X-Content-Type-Options: nosniff`. Content-hashed files in `assets/` are cached as immutable; everything else, including `index.html`, the service worker and the manifests, is revalidated with content-hash ETags.
- **Window.** The launcher starts the browser with `--app=http://127.0.0.1:<port>/ --user-data-dir=<data>/Browser-<id> --no-first-run --no-default-browser-check`. Only a new profile also gets a window size (on Windows, centered on the work area). Later launches keep the placement the browser saved. Linux adds `--class=Liquidgram`. The browser chosen once is preferred while it stays installed, because each browser keeps its own profile.
  - Windows: Edge, Chrome, Brave, Yandex Browser, Vivaldi, then Chromium. The launcher checks the usual folders under Program Files and `%LOCALAPPDATA%`, then `App Paths` in the registry.
  - macOS: the same browsers in `/Applications` and `~/Applications`.
  - Linux: `google-chrome`, `chromium`, `microsoft-edge`, `brave-browser`, `yandex-browser` and `vivaldi` on `PATH`.
- **Exit.** The launcher stays alive while a browser process it started runs or while the profile is locked: `lockfile` on Windows, `SingletonLock` elsewhere. The lock check covers a browser that outlived a killed launcher. After three idle checks one second apart, the server stops and the launcher exits.
- **Links.** The app window uses its own browser profile, so links to other sites go to the default browser, where the user is signed in. The launcher opens every window with the launch token in the URL fragment, which no server receives. On `127.0.0.1`, `src/util/desktopLauncherToken.ts` takes the token out of the URL before the routing reads it and keeps it in `localStorage` for reloads and later windows. `src/util/desktopLauncher.ts` then sends links from `window.open` and from clicks on `target="_blank"` anchors to `GET /__liquidgram/open-url?url=…` with the token. The launcher also requires `Sec-Fetch-Site: same-origin`. It passes only absolute `http` and `https` addresses to `ShellExecute` on Windows, `open` on macOS or `xdg-open` on Linux. If that fails, the link opens in a window of the app profile.
- **Foreground on Windows.** Windows lets only the process the user works with, and the processes it allows, bring a window to the front; other windows open behind and flash their taskbar button. The launcher that serves the app runs in the background, so `foreground_windows.go` passes the right on. A second launch, which the user just started, calls `AllowSetForegroundWindow(ASFW_ANY)` before it asks the running instance for a window. Before `ShellExecute` opens a link, the launcher attaches its thread to the input of the foreground window, the app window where the user clicked, makes the same call and detaches. Failures are only logged. Other platforms skip this.
- **Other accounts.** On Windows, other accounts on the computer can read neither the data folder nor the command lines of this user's processes, so they cannot get the token and cannot open windows or links through the launcher. On Linux and macOS other accounts can read process command lines, which carry the token, so there it only keeps web pages out.
- **Errors.** If no browser is found or no port is free, the launcher shows a Russian and English message: a message box on Windows, `osascript` on macOS, and `zenity` or stderr on Linux.

Data folder: `%LOCALAPPDATA%\Liquidgram` on Windows, `~/Library/Application Support/Liquidgram` on macOS, and `$XDG_DATA_HOME/liquidgram` (default `~/.local/share/liquidgram`) on Linux. It holds `config.json`, `launcher.log` (truncated once it passes 1 MB), the `launcher-<port>.token` files and the browser profiles. The uninstaller keeps it.

### Test hooks

| Variable | Effect |
| --- | --- |
| `LIQUIDGRAM_BROWSER` | Browser executable to use instead of the installed ones (profile `Browser-Custom`) |
| `LIQUIDGRAM_BROWSER_ARGS` | Extra browser arguments separated by whitespace, for example `--headless=new --remote-debugging-port=9222` |
| `LIQUIDGRAM_SERVER_ONLY=1` | Serve the app without opening a window until interrupted |

## Development

```bash
cd desktop/launcher                  # after one build, so that webapp/ exists
go vet ./... && GOOS=windows go vet ./... && go test ./...
gofmt -l .
LIQUIDGRAM_SERVER_ONLY=1 go run .    # then open http://127.0.0.1:47819/
```

## Installer

`desktop/installer/liquidgram.nsi` builds a per-user installer that needs no administrator rights. It uses Modern UI in Russian, or English when Windows uses English, and installs into `%LOCALAPPDATA%\Programs\Liquidgram`. It creates Start menu and desktop shortcuts and registers an uninstaller under `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Liquidgram`. The finish page has a "Run Liquidgram" checkbox. `/S` installs or uninstalls silently. An update over a running copy renames the old executable, which Windows allows, and writes the new one next to it. If even that fails, the installer asks the user to close Liquidgram; a silent install exits with code 2 and keeps the old files.

## Assets

`assets/liquidgram.ico` (16 to 256 px) and `installer/welcome.bmp` (164×314, the Modern UI welcome bitmap) are rendered from `src/assets/liquidgram-logo.svg` with Chromium and converted with ImageMagick, for example `convert icon-16.png … icon-256.png liquidgram.ico` and `convert welcome.png -alpha off -type TrueColor BMP3:welcome.bmp`. Regenerate both when the logo changes.

## Limitations

- The executables are not code-signed, so SmartScreen warns on first launch.
- The foreground handoff follows the Windows documentation but has not run on a real Windows PC: Wine does not enforce the foreground rules.
- The app runs only while its window is open. There is no tray icon, autostart or push notifications when it is closed.
- A window pinned to the taskbar starts the browser directly, without the launcher. Pin the Start menu shortcut instead.
- The macOS code compiles (`GOOS=darwin go vet ./...`), but the build script makes no macOS package and nothing runs it on a Mac.
