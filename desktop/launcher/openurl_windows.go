package main

import (
	"os/exec"
	"path/filepath"

	"golang.org/x/sys/windows"
)

// Hands the link to the protocol handler of the default browser in a separate process
func openExternalURL(target string) error {
	systemDir, err := windows.GetSystemDirectory()
	if err != nil {
		return err
	}

	cmd := exec.Command(filepath.Join(systemDir, "rundll32.exe"), "url.dll,FileProtocolHandler", target)
	if err := cmd.Start(); err != nil {
		return err
	}
	go cmd.Wait()
	return nil
}
