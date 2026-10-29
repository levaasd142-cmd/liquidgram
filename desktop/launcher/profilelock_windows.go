package main

import (
	"errors"
	"os"
	"path/filepath"

	"golang.org/x/sys/windows"
)

// A running Chromium-based browser keeps `lockfile` in its profile open for writing without write
// sharing and deletes it on exit, so opening it for writing fails exactly while the profile is in use
func isProfileLocked(profileDir string) bool {
	file, err := os.OpenFile(filepath.Join(profileDir, "lockfile"), os.O_WRONLY, 0)
	if err == nil {
		file.Close()
		return false
	}
	return errors.Is(err, windows.ERROR_SHARING_VIOLATION) || errors.Is(err, windows.ERROR_ACCESS_DENIED)
}
