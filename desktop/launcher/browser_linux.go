package main

import "os/exec"

var browserCommands = []struct {
	id    string
	names []string
}{
	{id: "Chrome", names: []string{"google-chrome-stable", "google-chrome"}},
	{id: "Chromium", names: []string{"chromium", "chromium-browser"}},
	{id: "Edge", names: []string{"microsoft-edge-stable", "microsoft-edge"}},
	{id: "Brave", names: []string{"brave-browser", "brave"}},
	{id: "Yandex", names: []string{"yandex-browser-stable", "yandex-browser"}},
	{id: "Vivaldi", names: []string{"vivaldi-stable", "vivaldi"}},
}

// Groups the app windows under their own name in docks and window lists
var platformBrowserArgs = []string{"--class=" + appName}

func discoverBrowsers() []browser {
	var browsers []browser
	for _, candidate := range browserCommands {
		for _, name := range candidate.names {
			if path, err := exec.LookPath(name); err == nil {
				browsers = append(browsers, browser{id: candidate.id, path: path})
				break
			}
		}
	}
	return browsers
}
