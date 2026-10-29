package main

import (
	"log"
	"os"
	"os/exec"
)

// Logs the message, which also prints it to stderr, and shows it with zenity on a desktop session
func showError(message string) {
	log.Print(message)

	if os.Getenv("DISPLAY") == "" && os.Getenv("WAYLAND_DISPLAY") == "" {
		return
	}
	zenity, err := exec.LookPath("zenity")
	if err != nil {
		return
	}
	if err := exec.Command(zenity, "--error", "--no-markup", "--title="+appName, "--text="+message).Run(); err != nil {
		log.Printf("Could not show the error dialog: %v", err)
	}
}
