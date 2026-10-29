package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"io/fs"
	"log"
	"net"
	"net/http"
	"path"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	loopbackIP        = "127.0.0.1"
	controlPathPrefix = "/__liquidgram/"
	pingPath          = controlPathPrefix + "ping"
	openPath          = controlPathPrefix + "open"
	instanceHeader    = "X-Liquidgram-Instance"
	signatureApp      = "liquidgram"
	indexFileName     = "index.html"
	defaultMediaType  = "application/octet-stream"

	immutableCacheControl  = "public, max-age=31536000, immutable"
	revalidateCacheControl = "no-cache"
	noStoreCacheControl    = "no-store"
)

// Vite names hashed chunks `name-<8 hash characters>.ext`. Other files under `assets/`, such as
// copied decoders, keep their names between builds and must be revalidated.
var reHashedAsset = regexp.MustCompile(`^assets/[^/]+-[\w-]{8}\.\w+$`)

// An explicit table instead of `mime.TypeByExtension`: on Windows the latter reads the registry,
// where other software can map `.js` to `text/plain` and break module scripts
var contentTypes = map[string]string{
	".avif":        "image/avif",
	".bin":         "application/octet-stream",
	".css":         "text/css; charset=utf-8",
	".gif":         "image/gif",
	".htm":         "text/html; charset=utf-8",
	".html":        "text/html; charset=utf-8",
	".ico":         "image/x-icon",
	".jpeg":        "image/jpeg",
	".jpg":         "image/jpeg",
	".js":          "text/javascript; charset=utf-8",
	".json":        "application/json",
	".m4a":         "audio/mp4",
	".mjs":         "text/javascript; charset=utf-8",
	".mp3":         "audio/mpeg",
	".mp4":         "video/mp4",
	".oga":         "audio/ogg",
	".ogg":         "audio/ogg",
	".opus":        "audio/ogg",
	".otf":         "font/otf",
	".pdf":         "application/pdf",
	".png":         "image/png",
	".svg":         "image/svg+xml",
	".tgs":         "application/x-tgsticker",
	".ttf":         "font/ttf",
	".txt":         "text/plain; charset=utf-8",
	".wasm":        "application/wasm",
	".wav":         "audio/wav",
	".webm":        "video/webm",
	".webmanifest": "application/manifest+json",
	".webp":        "image/webp",
	".woff":        "font/woff",
	".woff2":       "font/woff2",
	".xml":         "application/xml",
}

type pingResponse struct {
	App      string `json:"app"`
	Version  string `json:"version"`
	Instance string `json:"instance"`
}

// Serves the embedded web build and the control endpoints that let a second launch hand off
type appHandler struct {
	files        fs.FS
	allowedHosts []string
	instanceID   string
	openWindow   func() error
	etags        sync.Map
}

func newAppHandler(files fs.FS, port int, instanceID string, openWindow func() error) *appHandler {
	portText := strconv.Itoa(port)
	return &appHandler{
		files:        files,
		allowedHosts: []string{net.JoinHostPort(loopbackIP, portText), net.JoinHostPort("localhost", portText)},
		instanceID:   instanceID,
		openWindow:   openWindow,
	}
}

func (h *appHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("X-Content-Type-Options", "nosniff")

	// Any other host name means DNS rebinding or a request that was not meant for this server
	if !h.isAllowedHost(r.Host) {
		http.Error(w, http.StatusText(http.StatusMisdirectedRequest), http.StatusMisdirectedRequest)
		return
	}

	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, http.StatusText(http.StatusMethodNotAllowed), http.StatusMethodNotAllowed)
		return
	}

	if strings.HasPrefix(r.URL.Path, controlPathPrefix) {
		h.serveControl(w, r)
		return
	}

	h.serveFile(w, r)
}

func (h *appHandler) isAllowedHost(host string) bool {
	for _, allowedHost := range h.allowedHosts {
		if strings.EqualFold(host, allowedHost) {
			return true
		}
	}
	return false
}

func (h *appHandler) serveControl(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", noStoreCacheControl)

	switch r.URL.Path {
	case pingPath:
		w.Header().Set("Content-Type", contentTypes[".json"])
		json.NewEncoder(w).Encode(pingResponse{App: signatureApp, Version: version, Instance: h.instanceID})
	case openPath:
		// Browsers cannot send the custom header cross-origin without a preflight, which is refused,
		// and the instance ID keeps launches of other users on this computer out
		if r.Method != http.MethodGet || r.Header.Get("Origin") != "" || r.Header.Get(instanceHeader) != h.instanceID {
			http.Error(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)
			return
		}
		if err := h.openWindow(); err != nil {
			log.Printf("Could not open a window on request: %v", err)
			http.Error(w, http.StatusText(http.StatusServiceUnavailable), http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		http.NotFound(w, r)
	}
}

func (h *appHandler) serveFile(w http.ResponseWriter, r *http.Request) {
	name, ok := resolveFileName(r.URL.Path)
	if !ok {
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}

	file, err := h.files.Open(name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}
	if info.IsDir() {
		http.Redirect(w, r, "/"+name+"/", http.StatusMovedPermanently)
		return
	}

	content, ok := file.(io.ReadSeeker)
	if !ok {
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}

	etag, err := h.getETag(name, content)
	if err != nil {
		log.Printf("Could not read %s: %v", name, err)
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}

	header := w.Header()
	header.Set("Content-Type", getContentType(name))
	header.Set("Cache-Control", getCacheControl(name))
	header.Set("ETag", etag)
	http.ServeContent(w, r, name, time.Time{}, content)
}

// Maps a URL path to a file of the embedded build. Dot segments, empty segments and backslashes are
// rejected instead of being cleaned, so no request addresses anything outside the build.
func resolveFileName(urlPath string) (string, bool) {
	name, hasRoot := strings.CutPrefix(urlPath, "/")
	if !hasRoot || strings.ContainsAny(name, "\\\x00") {
		return "", false
	}

	if name == "" || strings.HasSuffix(name, "/") {
		name += indexFileName
	}
	return name, fs.ValidPath(name)
}

func getContentType(name string) string {
	if contentType, ok := contentTypes[strings.ToLower(path.Ext(name))]; ok {
		return contentType
	}
	return defaultMediaType
}

func getCacheControl(name string) string {
	if reHashedAsset.MatchString(name) {
		return immutableCacheControl
	}
	return revalidateCacheControl
}

// The embedded files carry no modification time, so revalidation relies on content hashes
func (h *appHandler) getETag(name string, content io.ReadSeeker) (string, error) {
	if etag, ok := h.etags.Load(name); ok {
		return etag.(string), nil
	}

	hash := sha256.New()
	if _, err := io.Copy(hash, content); err != nil {
		return "", err
	}
	if _, err := content.Seek(0, io.SeekStart); err != nil {
		return "", err
	}

	etag := `"` + hex.EncodeToString(hash.Sum(nil)[:16]) + `"`
	h.etags.Store(name, etag)
	return etag, nil
}
