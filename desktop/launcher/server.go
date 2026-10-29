package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"io"
	"io/fs"
	"log"
	"net"
	"net/http"
	"net/url"
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
	openURLPath       = controlPathPrefix + "open-url"
	tokenHeader       = "X-Liquidgram-Token"
	signatureApp      = "liquidgram"
	indexFileName     = "index.html"
	defaultMediaType  = "application/octet-stream"

	// The app window gets the launch token in its URL fragment, which never reaches any server.
	// `src/util/desktopLauncherToken.ts` reads it under this key.
	tokenFragmentKey = "liquidgram-launcher"
	pingProofContext = "liquidgram-ping\n"

	maxExternalURLLength = 8192
	maxNonceLength       = 64

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
	// Answers the `nonce` query parameter with the launch token, so a launch sends its token only to an
	// instance that already knows it and never to a program that took the port
	Proof string `json:"proof,omitempty"`
}

func signPingNonce(launchToken, nonce string) string {
	mac := hmac.New(sha256.New, []byte(launchToken))
	mac.Write([]byte(pingProofContext + nonce))
	return hex.EncodeToString(mac.Sum(nil))
}

// Serves the embedded web build and the control endpoints: the handoff of a second launch and links
// that the app sends to the default browser
type appHandler struct {
	files        fs.FS
	allowedHosts []string
	// Public: tells launches whether this instance uses their data folder
	instanceID string
	// Secret: only this user's launches and the app windows know it
	launchToken string
	openWindow  func() error
	openURL     func(string) error
	etags       sync.Map
}

func buildAllowedHosts(port int) []string {
	portText := strconv.Itoa(port)
	return []string{net.JoinHostPort(loopbackIP, portText), net.JoinHostPort("localhost", portText)}
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
		ping := pingResponse{App: signatureApp, Version: version, Instance: h.instanceID}
		if nonce := r.URL.Query().Get("nonce"); nonce != "" && len(nonce) <= maxNonceLength && h.launchToken != "" {
			ping.Proof = signPingNonce(h.launchToken, nonce)
		}
		w.Header().Set("Content-Type", contentTypes[".json"])
		json.NewEncoder(w).Encode(ping)
	case openPath:
		h.serveOpenWindow(w, r)
	case openURLPath:
		h.serveOpenURL(w, r)
	default:
		http.NotFound(w, r)
	}
}

// Opens another app window for a second launch, which proves it runs as the same user by presenting
// the token from the data folder
func (h *appHandler) serveOpenWindow(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet || r.Header.Get("Origin") != "" || !h.hasLaunchToken(r) {
		http.Error(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)
		return
	}

	if err := h.openWindow(); err != nil {
		log.Printf("Could not open a window on request: %v", err)
		http.Error(w, http.StatusText(http.StatusServiceUnavailable), http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Opens a link to another site in the default browser, which has the user's sign-ins, instead of a
// window of the app profile. Only the app page may ask: the browser marks its requests as same-origin,
// and the page gets the token from the URL it was launched with.
func (h *appHandler) serveOpenURL(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet || r.Header.Get("Sec-Fetch-Site") != "same-origin" || !h.hasLaunchToken(r) {
		http.Error(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)
		return
	}

	target, ok := parseExternalURL(r.URL.Query().Get("url"))
	if !ok {
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}

	if err := h.openURL(target); err != nil {
		log.Printf("Could not open a link in the default browser: %v", err)
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *appHandler) hasLaunchToken(r *http.Request) bool {
	token := r.Header.Get(tokenHeader)
	return h.launchToken != "" && subtle.ConstantTimeCompare([]byte(token), []byte(h.launchToken)) == 1
}

// Accepts only absolute web addresses, so the system handler can never receive a file path or a
// custom protocol
func parseExternalURL(rawURL string) (string, bool) {
	if len(rawURL) > maxExternalURLLength {
		return "", false
	}

	parsedURL, err := url.Parse(rawURL)
	if err != nil || (parsedURL.Scheme != "http" && parsedURL.Scheme != "https") || parsedURL.Host == "" {
		return "", false
	}
	return parsedURL.String(), true
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
