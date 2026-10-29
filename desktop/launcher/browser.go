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
	// A browser process that exits with an error sooner than this after its start failed to start
	startFailureTime = 10 * time.Second
)

var errClosing = errors.New("the app is shutting down")

type browser struct {
	id   string
	path string
}

// Tracks the app windows. The first browser process becomes the main process of the dedicated
// profile, and later launches with the same profile only ask it for another window and exit.
type desktopApp struct {
	url         string
	dataDir     string
	launchToken string
	extraArgs   []string
	serverOnly  bool

	mu        sync.Mutex
	browser   browser
	processes int
	// Set once a browser process runs for a while or exits cleanly, or another process holds the profile
	hasStarted bool
	// The error of the last browser process that failed to start
	startErr  error
	isClosing bool
}

// Picks the override from the test hook, the saved browser if it is still installed, or the first
// installed one in the platform order. Reports a saved browser that is missing, because its profile
// holds the user's data.
func findBrowser(overridePath, savedID string) (selected browser, isSavedMissing bool, err error) {
	if overridePath != "" {
		if !isFile(overridePath) {
			return browser{}, false, fmt.Errorf("browser override %q does not exist", overridePath)
		}
		return browser{id: customBrowserID, path: overridePath}, false, nil
	}

	browsers := discoverBrowsers()
	if len(browsers) == 0 {
		return browser{}, false, errors.New("no supported browser is installed")
	}
	for _, candidate := range browsers {
		if candidate.id == savedID {
			return candidate, false, nil
		}
	}
	return browsers[0], savedID != "", nil
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
	// The page takes the token out of the fragment before anything else reads the URL
	appURL := a.url
	if a.launchToken != "" {
		appURL += "#" + tokenFragmentKey + "=" + a.launchToken
	}

	args := []string{
		"--app=" + appURL,
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
	startedAt := time.Now()
	log.Printf("Started browser process %d", pid)

	go func() {
		err := cmd.Wait()
		log.Printf("Browser process %d exited (%v)", pid, err)

		a.mu.Lock()
		a.processes--
		// A browser that hands the window to its running process exits with an error as well, but
		// that process holds the profile, which `waitUntilClosed` notices
		if err == nil || time.Since(startedAt) >= startFailureTime {
			a.hasStarted = true
		} else {
			a.startErr = err
		}
		a.mu.Unlock()
	}()
	return nil
}

// Returns once no browser process started here runs and no other process holds the profile. The
// profile lock covers browsers that outlive their launcher or hand the window to an existing
// process. A few consecutive idle checks ride out browser restarts. Reports a browser that never
// started: every process exited with an error right after its start and none held the profile.
func (a *desktopApp) waitUntilClosed() error {
	idleChecks := 0
	for {
		time.Sleep(closeCheckPeriod)

		// The lock is probed only while no started process runs, and starting one takes the same
		// mutex, so the probe never meets a browser this launcher is starting
		a.mu.Lock()
		switch {
		case a.processes > 0:
			idleChecks = 0
		case isProfileLocked(a.getProfileDir()):
			a.hasStarted = true
			idleChecks = 0
		default:
			idleChecks++
		}
		if idleChecks >= closeConfirmCount {
			a.isClosing = true
			var err error
			if !a.hasStarted {
				err = fmt.Errorf("%s exited right after its start: %w", a.browser.id, a.startErr)
			}
			a.mu.Unlock()
			return err
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
