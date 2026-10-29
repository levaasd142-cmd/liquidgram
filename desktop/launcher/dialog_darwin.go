package main

import (
	"log"
	"os/exec"
	"strings"
)

var appleScriptEscaper = strings.NewReplacer(`\`, `\\`, `"`, `\"`)

func showError(message string) {
	log.Print(message)

	script := `display dialog "` + appleScriptEscaper.Replace(message) + `" with title "` + appName +
		`" buttons {"OK"} default button 1 with icon stop`
	if err := exec.Command("osascript", "-e", script).Run(); err != nil {
		log.Printf("Could not show the error dialog: %v", err)
	}
}
