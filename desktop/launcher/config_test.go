package main

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

func TestLoadConfigWithByteOrderMark(t *testing.T) {
	dataDir := t.TempDir()
	content := "\xef\xbb\xbf{\r\n  \"port\": 43819,\r\n  \"browser\": \"Edge\"\r\n}\r\n"
	if err := os.WriteFile(filepath.Join(dataDir, configFileName), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, isUnreadable := loadConfig(dataDir)
	if isUnreadable || cfg != (config{Port: 43819, Browser: "Edge"}) {
		t.Errorf("loaded %+v, unreadable %v", cfg, isUnreadable)
	}
}

func TestKeepUnreadableConfigAside(t *testing.T) {
	tests := []struct {
		name    string
		content string
		isDir   bool
	}{
		{name: "broken JSON", content: `{"port": 43819,`},
		{name: "empty after a power cut"},
		{name: "port as a string", content: `{"port": "43819"}`},
		{name: "byte order mark of another encoding", content: "\xff\xfe{\x00}\x00"},
		// A folder in its place cannot be read as a file
		{name: "unreadable", isDir: true},
	}

	for _, test := range tests {
		dataDir := t.TempDir()
		path := filepath.Join(dataDir, configFileName)
		var err error
		if test.isDir {
			err = os.Mkdir(path, 0o700)
		} else {
			err = os.WriteFile(path, []byte(test.content), 0o600)
		}
		if err != nil {
			t.Fatal(err)
		}

		cfg, isUnreadable := loadConfig(dataDir)
		if !isUnreadable || cfg != (config{}) {
			t.Errorf("%s: loaded %+v, unreadable %v", test.name, cfg, isUnreadable)
			continue
		}

		keptPath := moveConfigAside(dataDir)
		if keptPath != path+unreadableConfigSuffix {
			t.Errorf("%s: kept at %s", test.name, keptPath)
		}
		if _, err := os.Lstat(path); !errors.Is(err, fs.ErrNotExist) {
			t.Errorf("%s: %s is still in place: %v", test.name, configFileName, err)
		}
		if !test.isDir {
			if kept, err := os.ReadFile(keptPath); err != nil || string(kept) != test.content {
				t.Errorf("%s: kept content %q, %v", test.name, kept, err)
			}
		}
		// Nothing replaces the port it may hold: the next run starts like the first one
		if cfg, isUnreadable := loadConfig(dataDir); isUnreadable || cfg != (config{}) {
			t.Errorf("%s: next load %+v, unreadable %v", test.name, cfg, isUnreadable)
		}
	}
}

func TestSaveConfig(t *testing.T) {
	dataDir := t.TempDir()
	saveConfig(dataDir, config{Port: 43819})
	saveConfig(dataDir, config{Port: 43819, Browser: "Edge"})

	if cfg, isUnreadable := loadConfig(dataDir); isUnreadable || cfg != (config{Port: 43819, Browser: "Edge"}) {
		t.Errorf("loaded %+v, unreadable %v", cfg, isUnreadable)
	}
	entries, err := os.ReadDir(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		names = append(names, entry.Name())
	}
	if !slices.Equal(names, []string{configFileName}) {
		t.Errorf("data folder holds %q, want only %s", names, configFileName)
	}
}

func TestFindLastServedPort(t *testing.T) {
	dataDir := t.TempDir()
	if port := findLastServedPort(dataDir); port != 0 {
		t.Errorf("empty data folder gave port %d, want 0", port)
	}

	start := time.Now().Add(-time.Hour)
	files := []struct {
		name string
		age  time.Duration
	}{
		{name: "launcher-47819.token", age: 30 * time.Minute},
		{name: "launcher-43819.token", age: 10 * time.Minute},
		// Newer, but not a launcher port or not a token file name
		{name: "launcher-80.token", age: 0},
		{name: "launcher-abc.token", age: 0},
		{name: "launcher-39819.token.tmp", age: 0},
	}
	for _, file := range files {
		path := filepath.Join(dataDir, file.name)
		if err := os.WriteFile(path, []byte("token"), 0o600); err != nil {
			t.Fatal(err)
		}
		modTime := start.Add(time.Hour - file.age)
		if err := os.Chtimes(path, modTime, modTime); err != nil {
			t.Fatal(err)
		}
	}

	if port := findLastServedPort(dataDir); port != 43819 {
		t.Errorf("found port %d, want 43819 from the newest token file", port)
	}
}
