package main

import (
	"os"
	"path/filepath"
)

var browserBundles = []struct {
	id         string
	bundle     string
	executable string
}{
	{id: "Chrome", bundle: "Google Chrome.app", executable: "Google Chrome"},
	{id: "Edge", bundle: "Microsoft Edge.app", executable: "Microsoft Edge"},
	{id: "Brave", bundle: "Brave Browser.app", executable: "Brave Browser"},
	{id: "Yandex", bundle: "Yandex.app", executable: "Yandex"},
	{id: "Vivaldi", bundle: "Vivaldi.app", executable: "Vivaldi"},
	{id: "Chromium", bundle: "Chromium.app", executable: "Chromium"},
}

var platformBrowserArgs []string

func discoverBrowsers() []browser {
	applicationDirs := []string{"/Applications"}
	if home, err := os.UserHomeDir(); err == nil {
		applicationDirs = append(applicationDirs, filepath.Join(home, "Applications"))
	}

	var browsers []browser
	for _, candidate := range browserBundles {
		for _, dir := range applicationDirs {
			path := filepath.Join(dir, candidate.bundle, "Contents", "MacOS", candidate.executable)
			if isFile(path) {
				browsers = append(browsers, browser{id: candidate.id, path: path})
				break
			}
		}
	}
	return browsers
}
