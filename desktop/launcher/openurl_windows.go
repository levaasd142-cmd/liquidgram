package main

import (
	"runtime"
	"syscall"

	"golang.org/x/sys/windows"
)

// Hands the link to the default browser through the shell. The launcher runs in the background, so
// the browser may come to the front only with the right of the app window that asked for the link.
func openExternalURL(target string) error {
	verb, err := windows.UTF16PtrFromString("open")
	if err != nil {
		return err
	}
	file, err := windows.UTF16PtrFromString(target)
	if err != nil {
		return err
	}

	// The input state and the COM apartment belong to the OS thread
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	allowForegroundOfActiveWindow()

	// Protocol handlers may be shell extensions that expect a single-threaded COM apartment
	err = windows.CoInitializeEx(0, windows.COINIT_APARTMENTTHREADED|windows.COINIT_DISABLE_OLE1DDE)
	if err == nil || err == syscall.Errno(windows.S_FALSE) {
		defer windows.CoUninitialize()
	}
	return windows.ShellExecute(0, verb, file, nil, nil, windows.SW_SHOWNORMAL)
}
