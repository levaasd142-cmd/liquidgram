package main

import (
	"os"
	"path/filepath"
	"slices"
	"strings"

	"golang.org/x/sys/windows/registry"
)

const appPathsKey = `SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\`

// Edge ships with Windows 10 and 11, so it comes first
var browserLocations = []struct {
	id string
	// Relative to Program Files and %LOCALAPPDATA%
	installPath string
	// The executable name registered under App Paths
	appPathsName string
	// A lowercase part of the registered path that confirms the vendor of a generic executable name
	appPathsMarker string
}{
	{id: "Edge", installPath: `Microsoft\Edge\Application\msedge.exe`, appPathsName: "msedge.exe"},
	{id: "Chrome", installPath: `Google\Chrome\Application\chrome.exe`, appPathsName: "chrome.exe", appPathsMarker: `\google\`},
	{id: "Brave", installPath: `BraveSoftware\Brave-Browser\Application\brave.exe`, appPathsName: "brave.exe"},
	{id: "Yandex", installPath: `Yandex\YandexBrowser\Application\browser.exe`, appPathsName: "browser.exe", appPathsMarker: `\yandex\`},
	{id: "Vivaldi", installPath: `Vivaldi\Application\vivaldi.exe`, appPathsName: "vivaldi.exe"},
	{id: "Chromium", installPath: `Chromium\Application\chrome.exe`},
}

var platformBrowserArgs []string

func discoverBrowsers() []browser {
	roots := getInstallRoots()

	var browsers []browser
	for _, location := range browserLocations {
		path := findInstallPath(roots, location.installPath)
		if path == "" && location.appPathsName != "" {
			path = lookupAppPath(location.appPathsName, location.appPathsMarker)
		}
		if path != "" {
			browsers = append(browsers, browser{id: location.id, path: path})
		}
	}
	return browsers
}

func getInstallRoots() []string {
	var roots []string
	for _, variable := range []string{"ProgramFiles", "ProgramFiles(x86)", "ProgramW6432", "LOCALAPPDATA"} {
		root := os.Getenv(variable)
		if root != "" && !slices.Contains(roots, root) {
			roots = append(roots, root)
		}
	}
	return roots
}

func findInstallPath(roots []string, installPath string) string {
	for _, root := range roots {
		path := filepath.Join(root, installPath)
		if isFile(path) {
			return path
		}
	}
	return ""
}

func lookupAppPath(executable, marker string) string {
	for _, root := range []registry.Key{registry.CURRENT_USER, registry.LOCAL_MACHINE} {
		for _, view := range []uint32{registry.WOW64_64KEY, registry.WOW64_32KEY} {
			path := readAppPath(root, view, executable)
			if path != "" && strings.Contains(strings.ToLower(path), marker) && isFile(path) {
				return path
			}
		}
	}
	return ""
}

func readAppPath(root registry.Key, view uint32, executable string) string {
	key, err := registry.OpenKey(root, appPathsKey+executable, registry.QUERY_VALUE|view)
	if err != nil {
		return ""
	}
	defer key.Close()

	value, valueType, err := key.GetStringValue("")
	if err != nil {
		return ""
	}
	if valueType == registry.EXPAND_SZ {
		if expanded, err := registry.ExpandString(value); err == nil {
			value = expanded
		}
	}
	return strings.Trim(strings.TrimSpace(value), `"`)
}
