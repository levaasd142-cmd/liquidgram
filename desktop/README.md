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
4. builds `Liquidgram.exe` (`windows/amd64`, GUI subsystem) and `liquidgram-linux-x64`;
5. packs `Liquidgram-Portable.zip` (the exe and a Russian `README.txt`) and builds `Liquidgram-Setup.exe` with `makensis`.

Everything lands in `dist-desktop/`. To package an existing web build: `node dev/buildDesktop.mjs --dist path/to/dist [--out dir] [--no-installer]`. The `GO` and `MAKENSIS` environment variables override the tool paths.

## How the launcher works

The code lives in `desktop/launcher`; platform files use the `_windows`, `_linux` and `_darwin` suffixes.

- **Origin.** All user data (session, API keys, message archive) lives in storage owned by the origin, so the port must not change. The launcher tries the port saved in `config.json`, then `47819`, `43819`, `39819`, `35819` and `31819`. All of them sit below the Windows dynamic port range, and the first port that works is saved for good. A port that belongs to another program is skipped for that run only.
- **Single instance.** When the port is taken, the launcher asks `GET /__liquidgram/ping` who holds it. If it is a Liquidgram instance with the same data folder, the launcher calls `GET /__liquidgram/open` with the `X-Liquidgram-Instance` header, and that instance opens another window. The new launcher then exits. Instances of other Windows users on the same computer have other data folders, so they are left alone.
- **Server.** The server listens on `127.0.0.1` only and answers `421` to any `Host` other than `127.0.0.1:<port>` or `localhost:<port>`, which blocks DNS rebinding. It accepts only `GET` and `HEAD`, and paths with dot segments, empty segments or backslashes get `400`, so it serves embedded files only. Content types come from an explicit table in `server.go`, not from `mime.TypeByExtension`: on Windows the latter reads the registry, where other software can map `.js` or `.wasm` to `text/plain`. `go test` fails when the web build contains an extension the table lacks. Every response carries `X-Content-Type-Options: nosniff`. Content-hashed files in `assets/` are cached as immutable; everything else, including `index.html`, the service worker and the manifests, is revalidated with content-hash ETags.
- **Window.** The launcher starts the browser with `--app=http://127.0.0.1:<port>/ --user-data-dir=<data>/Browser-<id> --no-first-run --no-default-browser-check`. Only a new profile also gets a window size (on Windows, centered on the work area). Later launches keep the placement the browser saved. Linux adds `--class=Liquidgram`. The browser chosen once is preferred while it stays installed, because each browser keeps its own profile.
  - Windows: Edge, Chrome, Brave, Yandex Browser, Vivaldi, then Chromium. The launcher checks the usual folders under Program Files and `%LOCALAPPDATA%`, then `App Paths` in the registry.
  - macOS: the same browsers in `/Applications` and `~/Applications`.
  - Linux: `google-chrome`, `chromium`, `microsoft-edge`, `brave-browser`, `yandex-browser` and `vivaldi` on `PATH`.
- **Exit.** The launcher stays alive while a browser process it started runs or while the profile is locked: `lockfile` on Windows, `SingletonLock` elsewhere. The lock check covers a browser that outlived a killed launcher. After three idle checks one second apart, the server stops and the launcher exits.
- **Errors.** If no browser is found or no port is free, the launcher shows a Russian and English message: a message box on Windows, `osascript` on macOS, and `zenity` or stderr on Linux.

Data folder: `%LOCALAPPDATA%\Liquidgram` on Windows, `~/Library/Application Support/Liquidgram` on macOS, and `$XDG_DATA_HOME/liquidgram` (default `~/.local/share/liquidgram`) on Linux. It holds `config.json`, `launcher.log` (truncated once it passes 1 MB) and the browser profiles. The uninstaller keeps it.

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

`desktop/installer/liquidgram.nsi` builds a per-user installer that needs no administrator rights. It uses Modern UI in Russian, or English when Windows uses English, and installs into `%LOCALAPPDATA%\Programs\Liquidgram`. It creates Start menu and desktop shortcuts and registers an uninstaller under `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Liquidgram`. The finish page has a "Run Liquidgram" checkbox. `/S` installs or uninstalls silently. An update over a running copy renames the old executable, which Windows allows, and writes the new one next to it.

## Assets

`assets/liquidgram.ico` (16 to 256 px) and `installer/welcome.bmp` (164×314, the Modern UI welcome bitmap) are rendered from `src/assets/liquidgram-logo.svg` with Chromium and converted with ImageMagick, for example `convert icon-16.png … icon-256.png liquidgram.ico` and `convert welcome.png -alpha off -type TrueColor BMP3:welcome.bmp`. Regenerate both when the logo changes.

## Limitations

- The executables are not code-signed, so SmartScreen warns on first launch.
- The app runs only while its window is open. There is no tray icon, autostart or push notifications when it is closed.
- Links to other sites open in a browser window that uses the Liquidgram profile.
- A window pinned to the taskbar starts the browser directly, without the launcher. Pin the Start menu shortcut instead.
