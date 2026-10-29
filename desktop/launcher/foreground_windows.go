package main

import (
	"log"

	"golang.org/x/sys/windows"
)

// `ASFW_ANY`: every process may take the foreground until the user's next input
const allowAnyProcess = 0xFFFFFFFF

var (
	procAllowSetForegroundWindow = user32.NewProc("AllowSetForegroundWindow")
	procAttachThreadInput        = user32.NewProc("AttachThreadInput")
)

// Windows lets only the process the user works with, and the processes it allows, bring a window to
// the front; others make their taskbar button flash. A launch that the user started holds that right,
// so it passes it on before the running instance opens the window for it. Failures only cost the
// window its place in front.
func allowAnyForeground() {
	if err := procAllowSetForegroundWindow.Find(); err != nil {
		log.Printf("Could not pass on the foreground: %v", err)
		return
	}
	if isAllowed, _, err := procAllowSetForegroundWindow.Call(allowAnyProcess); isAllowed == 0 {
		log.Printf("Could not pass on the foreground: %v", err)
	}
}

// Passes on the right of the foreground window, which is the app window the user just clicked in,
// by sharing its input state for a moment. Runs on a locked OS thread, because the input state
// belongs to a thread.
func allowForegroundOfActiveWindow() {
	currentThread := windows.GetCurrentThreadId()
	foregroundThread, err := windows.GetWindowThreadProcessId(windows.GetForegroundWindow(), nil)
	if err == nil && foregroundThread != currentThread && procAttachThreadInput.Find() == nil {
		isAttached, _, _ := procAttachThreadInput.Call(uintptr(currentThread), uintptr(foregroundThread), 1)
		if isAttached != 0 {
			defer procAttachThreadInput.Call(uintptr(currentThread), uintptr(foregroundThread), 0)
		}
	}
	allowAnyForeground()
}
