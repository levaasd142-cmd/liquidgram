//go:build !windows

package main

import (
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

// A running Chromium-based browser keeps `SingletonLock` in its profile as a symlink to
// `<hostname>-<pid>` and removes it on exit. A crash leaves the link behind, so the process is checked.
func isProfileLocked(profileDir string) bool {
	target, err := os.Readlink(filepath.Join(profileDir, "SingletonLock"))
	if err != nil {
		return false
	}

	separator := strings.LastIndex(target, "-")
	if separator < 0 {
		return false
	}
	if hostname, err := os.Hostname(); err != nil || target[:separator] != hostname {
		return false
	}

	pid, err := strconv.Atoi(target[separator+1:])
	if err != nil || pid <= 0 {
		return false
	}
	err = syscall.Kill(pid, 0)
	return err == nil || errors.Is(err, syscall.EPERM)
}
