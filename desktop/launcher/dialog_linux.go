package main

import (
	"log"
	"os"
	"os/exec"
)

// Shows the message with zenity on a desktop session. The log already printed it to stderr.
func showDialog(message string, isWarning bool) {
	if os.Getenv("DISPLAY") == "" && os.Getenv("WAYLAND_DISPLAY") == "" {
		return
	}
	zenity, err := exec.LookPath("zenity")
	if err != nil {
		return
	}

	kind := "--error"
	if isWarning {
		kind = "--warning"
	}
	if err := exec.Command(zenity, kind, "--no-markup", "--title="+appName, "--text="+message).Run(); err != nil {
		log.Printf("Could not show the dialog: %v", err)
	}
}
