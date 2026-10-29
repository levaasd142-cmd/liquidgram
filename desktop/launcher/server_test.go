package main

import (
	"encoding/json"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path"
	"slices"
	"strings"
	"testing"
	"testing/fstest"
)

const (
	testPort     = 47819
	testInstance = "instance"
	testToken    = "secret-token"
)

var testFiles = fstest.MapFS{
	"index.html":                    {Data: []byte("<!doctype html>")},
	"service.worker-pCog1pRS.js":    {Data: []byte("self")},
	"site.webmanifest":              {Data: []byte("{}")},
	"assets/index-s_N5EGuu.js":      {Data: []byte("export {}")},
	"assets/tlottie-kfyd4UOK.wasm":  {Data: []byte("\x00asm")},
	"assets/decoderWorker.min.wasm": {Data: []byte("\x00asm")},
	"get/index.html":                {Data: []byte("<!doctype html>")},
}

func TestEveryEmbeddedFileHasExplicitContentType(t *testing.T) {
	files := webappFiles()
	if _, err := fs.Stat(files, indexFileName); err != nil {
		t.Fatalf("the embedded web build has no %s: %v", indexFileName, err)
	}

	err := fs.WalkDir(files, ".", func(name string, entry fs.DirEntry, err error) error {
		if err != nil || entry.IsDir() {
			return err
		}
		if _, ok := contentTypes[strings.ToLower(path.Ext(name))]; !ok {
			t.Errorf("%s has no explicit content type", name)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}

type testActions struct {
	windows int
	urls    []string
}

func newTestHandler() (*appHandler, *testActions) {
	actions := &testActions{}
	handler := &appHandler{
		files:        testFiles,
		port:         testPort,
		allowedHosts: buildAllowedHosts(testPort),
		instanceID:   testInstance,
		launchToken:  testToken,
		openWindow: func() error {
			actions.windows++
			return nil
		},
		openURL: func(target string) error {
			actions.urls = append(actions.urls, target)
			return nil
		},
	}
	return handler, actions
}

func TestServeFiles(t *testing.T) {
	handler, _ := newTestHandler()
	tests := []struct {
		target       string
		status       int
		contentType  string
		cacheControl string
	}{
		{"/", http.StatusOK, "text/html; charset=utf-8", revalidateCacheControl},
		{"/?account=2", http.StatusOK, "text/html; charset=utf-8", revalidateCacheControl},
		{"/service.worker-pCog1pRS.js", http.StatusOK, "text/javascript; charset=utf-8", revalidateCacheControl},
		{"/site.webmanifest", http.StatusOK, "application/manifest+json", revalidateCacheControl},
		{"/assets/index-s_N5EGuu.js", http.StatusOK, "text/javascript; charset=utf-8", immutableCacheControl},
		{"/assets/tlottie-kfyd4UOK.wasm", http.StatusOK, "application/wasm", immutableCacheControl},
		{"/assets/decoderWorker.min.wasm", http.StatusOK, "application/wasm", revalidateCacheControl},
		{"/get/", http.StatusOK, "text/html; charset=utf-8", revalidateCacheControl},
		{"/get", http.StatusMovedPermanently, "", ""},
		{"/missing.js", http.StatusNotFound, "", ""},
		{"/../index.html", http.StatusBadRequest, "", ""},
		{"/assets/../index.html", http.StatusBadRequest, "", ""},
		{"/assets/%2e%2e/%2e%2e/index.html", http.StatusBadRequest, "", ""},
		{"/assets/..%2f..%2findex.html", http.StatusBadRequest, "", ""},
		{"/assets/..%5cindex.html", http.StatusBadRequest, "", ""},
		{"//index.html", http.StatusBadRequest, "", ""},
		{"/./index.html", http.StatusBadRequest, "", ""},
	}

	for _, test := range tests {
		response := serve(handler, http.MethodGet, test.target, nil)
		if response.Code != test.status {
			t.Errorf("GET %s: status %d, want %d", test.target, response.Code, test.status)
			continue
		}
		if got := response.Header().Get("X-Content-Type-Options"); got != "nosniff" {
			t.Errorf("GET %s: X-Content-Type-Options %q", test.target, got)
		}
		if test.status != http.StatusOK {
			continue
		}
		if got := response.Header().Get("Content-Type"); got != test.contentType {
			t.Errorf("GET %s: Content-Type %q, want %q", test.target, got, test.contentType)
		}
		if got := response.Header().Get("Cache-Control"); got != test.cacheControl {
			t.Errorf("GET %s: Cache-Control %q, want %q", test.target, got, test.cacheControl)
		}
	}
}

func TestRevalidateWithETag(t *testing.T) {
	handler, _ := newTestHandler()
	etag := serve(handler, http.MethodGet, "/", nil).Header().Get("ETag")
	if etag == "" {
		t.Fatal("no ETag")
	}

	response := serve(handler, http.MethodGet, "/", map[string]string{"If-None-Match": etag})
	if response.Code != http.StatusNotModified {
		t.Errorf("status %d, want %d", response.Code, http.StatusNotModified)
	}
}

func TestRejectForeignHostsAndMethods(t *testing.T) {
	handler, _ := newTestHandler()
	tests := []struct {
		method string
		host   string
		status int
	}{
		{http.MethodGet, "127.0.0.1:47819", http.StatusOK},
		{http.MethodHead, "localhost:47819", http.StatusOK},
		{http.MethodGet, "LOCALHOST:47819", http.StatusOK},
		{http.MethodGet, "evil.example:47819", http.StatusMisdirectedRequest},
		{http.MethodGet, "127.0.0.1", http.StatusMisdirectedRequest},
		{http.MethodGet, "127.0.0.1:80", http.StatusMisdirectedRequest},
		{http.MethodPost, "127.0.0.1:47819", http.StatusMethodNotAllowed},
		{http.MethodOptions, "127.0.0.1:47819", http.StatusMethodNotAllowed},
	}

	for _, test := range tests {
		response := serve(handler, test.method, "/", map[string]string{"Host": test.host})
		if response.Code != test.status {
			t.Errorf("%s with host %s: status %d, want %d", test.method, test.host, response.Code, test.status)
		}
	}
}

func TestOpenWindowForSecondLaunch(t *testing.T) {
	handler, actions := newTestHandler()

	response := serve(handler, http.MethodGet, pingPath, nil)
	var ping pingResponse
	if err := json.NewDecoder(response.Body).Decode(&ping); err != nil {
		t.Fatal(err)
	}
	if ping.App != signatureApp || ping.Instance != testInstance || ping.Build != buildID || ping.Proof != "" {
		t.Errorf("ping %+v", ping)
	}

	response = serve(handler, http.MethodGet, pingPath+"?nonce=abc123", nil)
	if err := json.NewDecoder(response.Body).Decode(&ping); err != nil {
		t.Fatal(err)
	}
	if ping.Proof != signPingNonce(testToken, testPort, "abc123") ||
		ping.Proof == signPingNonce("other-token", testPort, "abc123") ||
		ping.Proof == signPingNonce(testToken, testPort+1, "abc123") {
		t.Errorf("ping proof %q does not match the token and the port", ping.Proof)
	}

	tests := []struct {
		method  string
		headers map[string]string
		status  int
	}{
		{http.MethodGet, nil, http.StatusForbidden},
		{http.MethodGet, map[string]string{"X-Liquidgram-Instance": testInstance}, http.StatusForbidden},
		{http.MethodGet, map[string]string{tokenHeader: "guess"}, http.StatusForbidden},
		{http.MethodGet, map[string]string{tokenHeader: testToken, "Origin": "http://127.0.0.1:47819"}, http.StatusForbidden},
		{http.MethodHead, map[string]string{tokenHeader: testToken}, http.StatusForbidden},
		{http.MethodGet, map[string]string{tokenHeader: testToken}, http.StatusNoContent},
	}
	for _, test := range tests {
		if response := serve(handler, test.method, openPath, test.headers); response.Code != test.status {
			t.Errorf("%s open with %v: status %d, want %d", test.method, test.headers, response.Code, test.status)
		}
	}
	if actions.windows != 1 {
		t.Errorf("%d window requests, want 1", actions.windows)
	}
}

func TestOpenExternalURL(t *testing.T) {
	handler, actions := newTestHandler()
	fromApp := map[string]string{"Sec-Fetch-Site": "same-origin", tokenHeader: testToken}
	tests := []struct {
		url     string
		headers map[string]string
		status  int
	}{
		{"https://example.com/path?q=1#top", fromApp, http.StatusNoContent},
		{"http://example.com", fromApp, http.StatusNoContent},
		{"https://example.com", map[string]string{"Sec-Fetch-Site": "cross-site", tokenHeader: testToken}, http.StatusForbidden},
		{"https://example.com", map[string]string{tokenHeader: testToken}, http.StatusForbidden},
		{"https://example.com", map[string]string{"Sec-Fetch-Site": "same-origin"}, http.StatusForbidden},
		{"https://example.com", map[string]string{"Sec-Fetch-Site": "same-origin", "X-Liquidgram-Instance": testInstance}, http.StatusForbidden},
		{"https://example.com", map[string]string{"Sec-Fetch-Site": "same-origin", tokenHeader: "guess"}, http.StatusForbidden},
		{"file:///C:/Windows/System32/calc.exe", fromApp, http.StatusBadRequest},
		{`C:\Windows\System32\calc.exe`, fromApp, http.StatusBadRequest},
		{`\\server\share\setup.exe`, fromApp, http.StatusBadRequest},
		{"javascript:alert(1)", fromApp, http.StatusBadRequest},
		{"ms-settings:privacy", fromApp, http.StatusBadRequest},
		{"https:///no-host", fromApp, http.StatusBadRequest},
		{"/relative/path", fromApp, http.StatusBadRequest},
		{"https://example.com/" + strings.Repeat("a", maxExternalURLLength), fromApp, http.StatusBadRequest},
	}

	for _, test := range tests {
		target := openURLPath + "?url=" + url.QueryEscape(test.url)
		if response := serve(handler, http.MethodGet, target, test.headers); response.Code != test.status {
			t.Errorf("open-url %.60q with %v: status %d, want %d", test.url, test.headers, response.Code, test.status)
		}
	}

	want := []string{"https://example.com/path?q=1#top", "http://example.com"}
	if !slices.Equal(actions.urls, want) {
		t.Errorf("opened %q, want %q", actions.urls, want)
	}
}

func serve(handler http.Handler, method, target string, headers map[string]string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(method, target, nil)
	request.Host = "127.0.0.1:47819"
	for name, value := range headers {
		if name == "Host" {
			request.Host = value
			continue
		}
		request.Header.Set(name, value)
	}

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}
