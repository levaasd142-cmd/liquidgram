package main

import (
	"log"

	"golang.org/x/sys/windows"
)

func showError(message string) {
	log.Print(message)

	text, err := windows.UTF16PtrFromString(message)
	if err != nil {
		return
	}
	caption, err := windows.UTF16PtrFromString(appName)
	if err != nil {
		return
	}
	windows.MessageBox(0, text, caption, windows.MB_OK|windows.MB_ICONERROR|windows.MB_SETFOREGROUND)
}
