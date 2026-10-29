package main

import (
	"encoding/json"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"path"
	"strings"
	"testing"
	"testing/fstest"
)

const testPort = 47819

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

func TestServeFiles(t *testing.T) {
	handler := newAppHandler(testFiles, testPort, "test", func() error { return nil })
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
	handler := newAppHandler(testFiles, testPort, "test", func() error { return nil })
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
	handler := newAppHandler(testFiles, testPort, "test", func() error { return nil })
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

func TestControlEndpoints(t *testing.T) {
	windowRequests := 0
	handler := newAppHandler(testFiles, testPort, "instance", func() error {
		windowRequests++
		return nil
	})

	response := serve(handler, http.MethodGet, pingPath, nil)
	var ping pingResponse
	if err := json.NewDecoder(response.Body).Decode(&ping); err != nil {
		t.Fatal(err)
	}
	if ping.App != signatureApp || ping.Instance != "instance" {
		t.Errorf("ping %+v", ping)
	}

	tests := []struct {
		headers map[string]string
		status  int
	}{
		{nil, http.StatusForbidden},
		{map[string]string{instanceHeader: "other"}, http.StatusForbidden},
		{map[string]string{instanceHeader: "instance", "Origin": "http://127.0.0.1:47819"}, http.StatusForbidden},
		{map[string]string{instanceHeader: "instance"}, http.StatusNoContent},
	}
	for _, test := range tests {
		if response := serve(handler, http.MethodGet, openPath, test.headers); response.Code != test.status {
			t.Errorf("open with %v: status %d, want %d", test.headers, response.Code, test.status)
		}
	}
	if windowRequests != 1 {
		t.Errorf("%d window requests, want 1", windowRequests)
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
