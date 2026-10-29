package main

import (
	"errors"
	"fmt"
	"io/fs"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

const (
	customBrowserID   = "Custom"
	profileDirPrefix  = "Browser-"
	closeCheckPeriod  = time.Second
	closeConfirmCount = 3
)

var errClosing = errors.New("the app is shutting down")

type browser struct {
	id   string
	path string
}

// Tracks the app windows. The first browser process becomes the main process of the dedicated
// profile, and later launches with the same profile only ask it for another window and exit.
type desktopApp struct {
	url        string
	dataDir    string
	extraArgs  []string
	serverOnly bool

	mu        sync.Mutex
	browser   browser
	processes int
	isClosing bool
}

// Picks the override from the test hook, the browser used before if it is still installed, or the
// first installed one in the platform order
func findBrowser(overridePath, previousID string) (browser, error) {
	if overridePath != "" {
		if !isFile(overridePath) {
			return browser{}, fmt.Errorf("browser override %q does not exist", overridePath)
		}
		return browser{id: customBrowserID, path: overridePath}, nil
	}

	browsers := discoverBrowsers()
	if len(browsers) == 0 {
		return browser{}, errors.New("no supported browser is installed")
	}
	for _, candidate := range browsers {
		if candidate.id == previousID {
			return candidate, nil
		}
	}
	return browsers[0], nil
}

func (a *desktopApp) start(selected browser) error {
	a.mu.Lock()
	defer a.mu.Unlock()

	a.browser = selected
	_, err := os.Stat(a.getProfileDir())
	return a.startBrowserLocked(errors.Is(err, fs.ErrNotExist))
}

// Handles a window request from a second launch
func (a *desktopApp) openWindow() error {
	a.mu.Lock()
	defer a.mu.Unlock()

	if a.isClosing {
		return errClosing
	}
	// Without a browser yet, the first window is about to open anyway
	if a.serverOnly || a.browser.path == "" {
		return nil
	}
	return a.startBrowserLocked(false)
}

func (a *desktopApp) startBrowserLocked(isNewProfile bool) error {
	args := []string{
		"--app=" + a.url,
		"--user-data-dir=" + a.getProfileDir(),
		"--no-first-run",
		"--no-default-browser-check",
	}
	// Later launches keep the window placement the browser saved in the profile
	if isNewProfile {
		args = append(args, getInitialWindowArgs()...)
	}
	args = append(args, platformBrowserArgs...)
	args = append(args, a.extraArgs...)

	cmd := exec.Command(a.browser.path, args...)
	if err := cmd.Start(); err != nil {
		return err
	}

	a.processes++
	pid := cmd.Process.Pid
	log.Printf("Started browser process %d", pid)

	go func() {
		err := cmd.Wait()
		log.Printf("Browser process %d exited (%v)", pid, err)

		a.mu.Lock()
		a.processes--
		a.mu.Unlock()
	}()
	return nil
}

// Returns once no browser process started here runs and no other process holds the profile. The
// profile lock covers browsers that outlive their launcher or hand the window to an existing
// process. A few consecutive idle checks ride out browser restarts.
func (a *desktopApp) waitUntilClosed() {
	idleChecks := 0
	for {
		time.Sleep(closeCheckPeriod)

		// The lock is probed only while no started process runs, and starting one takes the same
		// mutex, so the probe never meets a browser this launcher is starting
		a.mu.Lock()
		if a.processes > 0 || isProfileLocked(a.getProfileDir()) {
			idleChecks = 0
		} else {
			idleChecks++
		}
		if idleChecks >= closeConfirmCount {
			a.isClosing = true
			a.mu.Unlock()
			return
		}
		a.mu.Unlock()
	}
}

func (a *desktopApp) getProfileDir() string {
	return filepath.Join(a.dataDir, profileDirPrefix+a.browser.id)
}

func isFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
