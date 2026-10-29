package main

import (
	"fmt"
	"unsafe"

	"golang.org/x/sys/windows"
)

const (
	spiGetWorkArea   = 0x0030
	defaultDPI       = 96
	maxInitialWidth  = 1280
	maxInitialHeight = 860
	widthPercent     = 85
	heightPercent    = 90
)

var (
	user32                   = windows.NewLazySystemDLL("user32.dll")
	procSystemParametersInfo = user32.NewProc("SystemParametersInfoW")
	procGetDpiForSystem      = user32.NewProc("GetDpiForSystem")
)

// Centers the first window on the primary work area. The browser expects device-independent pixels,
// so the physical work area is scaled by the system DPI.
func getInitialWindowArgs() []string {
	var area windows.Rect
	if isOK, _, _ := procSystemParametersInfo.Call(spiGetWorkArea, 0, uintptr(unsafe.Pointer(&area)), 0); isOK == 0 {
		return nil
	}

	dpi := uintptr(defaultDPI)
	if procGetDpiForSystem.Find() == nil {
		if systemDPI, _, _ := procGetDpiForSystem.Call(); systemDPI != 0 {
			dpi = systemDPI
		}
	}

	toDIP := func(value int32) int { return int(value) * defaultDPI / int(dpi) }
	left, top := toDIP(area.Left), toDIP(area.Top)
	areaWidth, areaHeight := toDIP(area.Right-area.Left), toDIP(area.Bottom-area.Top)
	width := min(maxInitialWidth, areaWidth*widthPercent/100)
	height := min(maxInitialHeight, areaHeight*heightPercent/100)

	return []string{
		fmt.Sprintf("--window-size=%d,%d", width, height),
		fmt.Sprintf("--window-position=%d,%d", left+(areaWidth-width)/2, top+(areaHeight-height)/2),
	}
}
