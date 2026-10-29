package main

import (
	"bytes"
	"crypto/rand"
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
	"strings"
)

const (
	configFileName = "config.json"
	// An unreadable config moves to this name, so no later run replaces the port it may hold
	unreadableConfigSuffix = ".bad"
	logFileName            = "launcher.log"
	maxLogSize             = 1 << 20
	tokenBytes             = 32
	minConfigPort          = 1024
	maxConfigPort          = 65535
)

// Older versions of Notepad start UTF-8 files with this prefix
var utf8ByteOrderMark = []byte{0xEF, 0xBB, 0xBF}

// The launcher state that has to survive restarts. The port defines the app origin, which owns the
// session, the API keys and the message archive, so it never changes once chosen. The browser is
// chosen once as well, because its profile holds the session.
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

// Creates the secret that a second launch reads from the data folder, which other accounts on the
// computer cannot read, and that the app windows get in their launch URL. Each port has its own file,
// so instances on different ports never replace each other's token. The file is written before the
// server starts, so a launch that reached the server never reads it half-written. A token that could
// not be saved still serves the windows of this run.
func createLaunchToken(dataDir string, port int) (string, error) {
	secret := make([]byte, tokenBytes)
	// Since Go 1.24 `rand.Read` never returns an error
	rand.Read(secret)
	token := hex.EncodeToString(secret)
	return token, os.WriteFile(getTokenPath(dataDir, port), []byte(token), 0o600)
}

func readLaunchToken(dataDir string, port int) string {
	data, err := os.ReadFile(getTokenPath(dataDir, port))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func getTokenPath(dataDir string, port int) string {
	return filepath.Join(dataDir, fmt.Sprintf("launcher-%d.token", port))
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

// Reads the saved state and reports a file that exists but cannot be read or parsed: the port it may
// hold must not be replaced
func loadConfig(dataDir string) (cfg config, isUnreadable bool) {
	data, err := os.ReadFile(filepath.Join(dataDir, configFileName))
	if errors.Is(err, fs.ErrNotExist) {
		return config{}, false
	}
	if err == nil {
		err = json.Unmarshal(bytes.TrimPrefix(data, utf8ByteOrderMark), &cfg)
	}
	if err != nil {
		log.Printf("Could not read %s: %v", configFileName, err)
		return config{}, true
	}

	// The launcher saves one of its own ports, but a port set by hand may be any unprivileged one
	if cfg.Port < minConfigPort || cfg.Port > maxConfigPort {
		cfg.Port = 0
	}
	return cfg, false
}

// Moves an unreadable config out of the way of later saves and returns where the file is now
func moveConfigAside(dataDir string) string {
	path := filepath.Join(dataDir, configFileName)
	keptPath := path + unreadableConfigSuffix
	if err := os.Rename(path, keptPath); err != nil {
		log.Printf("Could not rename the unreadable %s: %v", configFileName, err)
		return path
	}
	log.Printf("Renamed the unreadable %s to %s", configFileName, filepath.Base(keptPath))
	return keptPath
}

// Replaces the file only with complete data that reached the disk, so a crash or a power cut leaves
// either the old or the new file
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
	if err == nil {
		err = file.Sync()
	}
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
