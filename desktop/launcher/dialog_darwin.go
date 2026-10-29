package main

import (
	"log"
	"os/exec"
	"strings"
)

var appleScriptEscaper = strings.NewReplacer(`\`, `\\`, `"`, `\"`)

func showDialog(message string, isWarning bool) {
	icon := "stop"
	if isWarning {
		icon = "caution"
	}

	script := `display dialog "` + appleScriptEscaper.Replace(message) + `" with title "` + appName +
		`" buttons {"OK"} default button 1 with icon ` + icon
	if err := exec.Command("osascript", "-e", script).Run(); err != nil {
		log.Printf("Could not show the dialog: %v", err)
	}
}
