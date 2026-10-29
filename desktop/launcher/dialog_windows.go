package main

import "golang.org/x/sys/windows"

func showDialog(message string, isWarning bool) {
	text, err := windows.UTF16PtrFromString(message)
	if err != nil {
		return
	}
	caption, err := windows.UTF16PtrFromString(appName)
	if err != nil {
		return
	}

	icon := uint32(windows.MB_ICONERROR)
	if isWarning {
		icon = windows.MB_ICONWARNING
	}
	windows.MessageBox(0, text, caption, windows.MB_OK|icon|windows.MB_SETFOREGROUND)
}
