package main

import "log"

func showError(message string) {
	log.Print(message)
	showDialog(message, false)
}

func showWarning(message string) {
	log.Print(message)
	showDialog(message, true)
}
