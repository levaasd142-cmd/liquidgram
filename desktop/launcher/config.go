package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"runtime"
)

const (
	configFileName = "config.json"
	logFileName    = "launcher.log"
	maxLogSize     = 1 << 20
	minConfigPort  = 1024
	maxConfigPort  = 65535
)

// The launcher state that has to survive restarts. The port defines the app origin, which owns the
// session, the API keys and the message archive, so it never changes once chosen. The browser keeps
// the same profile in use while that browser stays installed.
type config struct {
	Port    int    `json:"port,omitempty"`
	Browser string `json:"browser,omitempty"`
}

func resolveDataDir() (string, error) {
	switch runtime.GOOS {
	case "windows":
		if dir := os.Getenv("LOCALAPPDATA"); filepath.IsAbs(dir) {
			return filepath.Join(dir, appName), nil
		}
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		return filepath.Join(home, "AppData", "Local", appName), nil
	case "darwin":
		dir, err := os.UserConfigDir()
		if err != nil {
			return "", err
		}
		return filepath.Join(dir, appName), nil
	default:
		if dir := os.Getenv("XDG_DATA_HOME"); filepath.IsAbs(dir) {
			return filepath.Join(dir, "liquidgram"), nil
		}
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		return filepath.Join(home, ".local", "share", "liquidgram"), nil
	}
}

// Identifies the data folder, so a launch hands off only to an instance of the same user
func buildInstanceID(dataDir string) string {
	sum := sha256.Sum256([]byte(filepath.Clean(dataDir)))
	return hex.EncodeToString(sum[:16])
}

func setupLog(path string) (closeLog func()) {
	log.SetPrefix(fmt.Sprintf("[%d] ", os.Getpid()))

	flags := os.O_CREATE | os.O_WRONLY | os.O_APPEND
	if info, err := os.Stat(path); err == nil && info.Size() > maxLogSize {
		flags |= os.O_TRUNC
	}

	file, err := os.OpenFile(path, flags, 0o600)
	if err != nil {
		log.Printf("Could not open the log file: %v", err)
		return func() {}
	}

	// The file goes first: a GUI process on Windows has no usable stderr
	log.SetOutput(io.MultiWriter(file, os.Stderr))
	return func() {
		log.SetOutput(os.Stderr)
		file.Close()
	}
}

func loadConfig(dataDir string) config {
	var cfg config

	data, err := os.ReadFile(filepath.Join(dataDir, configFileName))
	if errors.Is(err, fs.ErrNotExist) {
		return cfg
	}
	if err == nil {
		err = json.Unmarshal(data, &cfg)
	}
	if err != nil {
		log.Printf("Ignoring unreadable %s: %v", configFileName, err)
		return config{}
	}

	if cfg.Port < minConfigPort || cfg.Port > maxConfigPort {
		cfg.Port = 0
	}
	return cfg
}

func saveConfig(dataDir string, cfg config) {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		log.Printf("Could not encode %s: %v", configFileName, err)
		return
	}

	file, err := os.CreateTemp(dataDir, configFileName+".*.tmp")
	if err != nil {
		log.Printf("Could not save %s: %v", configFileName, err)
		return
	}
	tempPath := file.Name()

	_, err = file.Write(append(data, '\n'))
	if closeErr := file.Close(); err == nil {
		err = closeErr
	}
	if err == nil {
		err = os.Rename(tempPath, filepath.Join(dataDir, configFileName))
	}
	if err != nil {
		os.Remove(tempPath)
		log.Printf("Could not save %s: %v", configFileName, err)
	}
}
