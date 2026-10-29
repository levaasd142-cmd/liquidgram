// Command launcher runs Liquidgram as a desktop app. It serves the embedded web build on a stable
// loopback origin and shows it in an installed Chromium-based browser running in app mode with a
// dedicated profile. A second launch hands off to the running instance, which opens another window.
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const (
	appName = "Liquidgram"

	// Test hooks: a browser executable to use instead of the installed ones, extra browser
	// arguments separated by whitespace, and a mode that serves the app without opening a window
	envBrowser     = "LIQUIDGRAM_BROWSER"
	envBrowserArgs = "LIQUIDGRAM_BROWSER_ARGS"
	envServerOnly  = "LIQUIDGRAM_SERVER_ONLY"

	shutdownTimeout = 2 * time.Second
)

// Set by the build script through `-ldflags "-X main.version=... -X main.buildID=..."`
var (
	version = "dev"
	buildID = "dev"
)

const (
	messageNoBrowser = "Liquidgram не нашёл браузер, в котором можно открыть окно приложения.\n\n" +
		"Установите Microsoft Edge или Google Chrome и запустите Liquidgram ещё раз.\n\n" +
		"No supported browser found. Install Microsoft Edge or Google Chrome and start Liquidgram again."
	messageNoPort = "Liquidgram не может запуститься: все его локальные порты заняты другими программами.\n\n" +
		"Перезагрузите компьютер и попробуйте ещё раз.\n\n" +
		"All local ports reserved for Liquidgram are busy. Restart the computer and try again."
	messageStartFailed = "Liquidgram не смог открыть окно приложения.\n\n" +
		"Подробности записаны в файл %s\n\n" +
		"Liquidgram could not open its window: %v"
	messageNoDataDir = "Liquidgram не может создать папку для своих данных.\n\n" +
		"Liquidgram could not create its data folder: %v"
	messageSparePort = "Порт %d, к которому привязаны ваш вход, ключи и чаты в Liquidgram, сейчас занят " +
		"другой программой, поэтому Liquidgram откроется без них.\n\n" +
		"Ничего не потеряно: закройте Liquidgram, перезагрузите компьютер и откройте Liquidgram снова.\n\n" +
		"Port %d, which holds your Liquidgram data, is busy, so the app opens without it. " +
		"Nothing is lost: close Liquidgram, restart the computer and open it again."
	messageOtherBuild = "Сейчас работает другая версия Liquidgram, и окно открыла она.\n\n" +
		"Чтобы запустить эту версию, закройте все окна Liquidgram и откройте его снова.\n\n" +
		"Another version of Liquidgram is running and opened the window. " +
		"Close all Liquidgram windows and open it again to start this version."
	messageUnreadableConfig = "Liquidgram не смог прочитать файл своих настроек, поэтому сейчас откроется с настройками " +
		"по умолчанию. Ваш вход, ключи и чаты могут не появиться.\n\n" +
		"Ничего не удалено, старый файл лежит здесь: %s\n\n" +
		"Liquidgram could not read its settings file, so it opens with default settings now. " +
		"Your login, keys and chats may not appear. Nothing is deleted; the old file is here: %s"
	messageBrowserMissing = "Браузер %[1]s, через который Liquidgram открывался раньше, не найден, поэтому сейчас " +
		"окно откроется через %[2]s.\n\n" +
		"Ваш вход, ключи и чаты не пропали: они остались в профиле %[1]s. Чтобы снова их увидеть, " +
		"установите %[1]s обратно.\n\n" +
		"%[1]s, the browser Liquidgram used before, is not installed, so the window opens through %[2]s this time. " +
		"Your login, keys and chats are not lost: they stay in the %[1]s profile. Install %[1]s again to see them."
	messageAlreadyRunning = "Liquidgram уже запущен, но не открыл новое окно, или его порт %d занят другой программой.\n\n" +
		"Закройте все окна Liquidgram и запустите его снова. Если это сообщение появится опять, " +
		"перезагрузите компьютер.\n\n" +
		"Liquidgram is already running but did not open a new window, or another program holds its port %d. " +
		"Close all Liquidgram windows and start it again. If this message appears again, restart the computer."
)

func main() {
	os.Exit(run())
}

func run() int {
	dataDir, err := resolveDataDir()
	if err == nil {
		err = os.MkdirAll(dataDir, 0o700)
	}
	if err != nil {
		showError(fmt.Sprintf(messageNoDataDir, err))
		return 1
	}

	logPath := filepath.Join(dataDir, logFileName)
	closeLog := setupLog(logPath)
	defer closeLog()

	log.Printf("Liquidgram %s (build %s) started, data folder %s", version, buildID, dataDir)

	cfg, isConfigUnreadable := loadConfig(dataDir)
	instanceID := buildInstanceID(dataDir)

	listener, port, err := acquirePort(cfg.Port, instanceID, dataDir)
	var handoff *handoffError
	if errors.As(err, &handoff) {
		log.Printf("The running instance on port %d opened a window (build %s)", port, handoff.build)
		// After an update the window comes from the copy that still runs
		if handoff.build != buildID {
			showWarning(messageOtherBuild)
		}
		return 0
	}
	if errors.Is(err, errAlreadyRunning) {
		log.Printf("Port %d: %v", port, err)
		showWarning(fmt.Sprintf(messageAlreadyRunning, port, port))
		return 0
	}
	if err != nil {
		log.Print(err)
		showError(messageNoPort)
		return 1
	}

	// The first port stays preferred for good because the app data belongs to its origin. An unreadable
	// config may hold the port of the user's data, so it moves aside and this run saves nothing.
	savedPort := cfg.Port
	var keptConfigPath string
	switch {
	case isConfigUnreadable:
		keptConfigPath = moveConfigAside(dataDir)
	case savedPort == 0:
		cfg.Port = port
		saveConfig(dataDir, cfg)
	case savedPort != port:
		log.Printf("Saved port %d is unavailable, using port %d for this run", savedPort, port)
	}

	// Without the saved token second launches cannot open more windows
	launchToken, err := createLaunchToken(dataDir, port)
	if err != nil {
		log.Printf("Could not save the launch token: %v", err)
	}

	app := &desktopApp{
		url:         "http://" + net.JoinHostPort(loopbackIP, strconv.Itoa(port)) + "/",
		dataDir:     dataDir,
		launchToken: launchToken,
		extraArgs:   strings.Fields(os.Getenv(envBrowserArgs)),
		serverOnly:  os.Getenv(envServerOnly) == "1",
	}

	server := &http.Server{
		Handler: &appHandler{
			files:        webappFiles(),
			port:         port,
			allowedHosts: buildAllowedHosts(port),
			instanceID:   instanceID,
			launchToken:  launchToken,
			openWindow:   app.openWindow,
			openURL:      openExternalURL,
		},
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       2 * time.Minute,
		ErrorLog:          log.Default(),
	}
	go func() {
		if err := server.Serve(listener); !errors.Is(err, http.ErrServerClosed) {
			log.Printf("Server stopped: %v", err)
		}
	}()
	defer shutdownServer(server)

	log.Printf("Serving %s", app.url)

	if app.serverOnly {
		fmt.Printf("Liquidgram is serving %s\n", app.url)
		waitForSignal()
		return 0
	}

	browser, isSavedBrowserMissing, err := findBrowser(os.Getenv(envBrowser), cfg.Browser)
	if err != nil {
		log.Print(err)
		showError(messageNoBrowser)
		return 1
	}
	log.Printf("Using %s browser at %s", browser.id, browser.path)

	if cfg.Browser == "" && !isConfigUnreadable {
		cfg.Browser = browser.id
		saveConfig(dataDir, cfg)
	}

	// Before a window that may show none of the user's data opens, the user learns why
	if keptConfigPath != "" {
		showWarning(fmt.Sprintf(messageUnreadableConfig, keptConfigPath, keptConfigPath))
	}
	if savedPort != 0 && savedPort != port {
		showWarning(fmt.Sprintf(messageSparePort, savedPort, savedPort))
	}
	if isSavedBrowserMissing {
		showWarning(fmt.Sprintf(messageBrowserMissing, cfg.Browser, browser.id))
	}

	if err := app.start(browser); err != nil {
		log.Printf("Could not start the browser: %v", err)
		showError(fmt.Sprintf(messageStartFailed, logPath, err))
		return 1
	}

	app.waitUntilClosed()
	log.Print("All app windows are closed, exiting")
	return 0
}

func shutdownServer(server *http.Server) {
	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Printf("Server shutdown: %v", err)
	}
}

func waitForSignal() {
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	log.Printf("Received %v, exiting", <-signals)
}
