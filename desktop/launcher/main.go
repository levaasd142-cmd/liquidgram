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

// Set by the build script through `-ldflags "-X main.version=..."`
var version = "dev"

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

	log.Printf("Liquidgram %s started, data folder %s", version, dataDir)

	cfg := loadConfig(dataDir)
	instanceID := buildInstanceID(dataDir)

	listener, port, err := acquirePort(cfg.Port, instanceID)
	if errors.Is(err, errHandedOff) {
		log.Printf("The running instance on port %d opened a window", port)
		return 0
	}
	if err != nil {
		log.Print(err)
		showError(messageNoPort)
		return 1
	}

	// The first port stays preferred for good because the app data belongs to its origin
	if cfg.Port == 0 {
		cfg.Port = port
		saveConfig(dataDir, cfg)
	} else if cfg.Port != port {
		log.Printf("Saved port %d is unavailable, using port %d for this run", cfg.Port, port)
	}

	app := &desktopApp{
		url:        "http://" + net.JoinHostPort(loopbackIP, strconv.Itoa(port)) + "/",
		dataDir:    dataDir,
		extraArgs:  strings.Fields(os.Getenv(envBrowserArgs)),
		serverOnly: os.Getenv(envServerOnly) == "1",
	}

	server := &http.Server{
		Handler:           newAppHandler(webappFiles(), port, instanceID, app.openWindow),
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

	browser, err := findBrowser(os.Getenv(envBrowser), cfg.Browser)
	if err != nil {
		log.Print(err)
		showError(messageNoBrowser)
		return 1
	}
	log.Printf("Using %s browser at %s", browser.id, browser.path)

	if cfg.Browser != browser.id {
		cfg.Browser = browser.id
		saveConfig(dataDir, cfg)
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
