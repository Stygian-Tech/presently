package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/fstest"

	"presently/oauth-worker/metadata"
)

func TestHealth(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	response := httptest.NewRecorder()

	newHandler(metadata.Config{}, testSite()).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("unexpected status: %d", response.Code)
	}
	if response.Body.String() != `{"status":"ok"}` {
		t.Fatalf("unexpected body: %s", response.Body.String())
	}
}

func TestHomepageServesMarketingSite(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	response := httptest.NewRecorder()

	newHandler(metadata.Config{}, testSite()).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("unexpected status: %d", response.Code)
	}
	if contentType := response.Header().Get("Content-Type"); contentType != "text/html; charset=utf-8" {
		t.Fatalf("unexpected content type: %s", contentType)
	}
	if body := response.Body.String(); !strings.Contains(body, `Presently`) {
		t.Fatalf("homepage does not contain marketing content: %s", body)
	}
}

func TestStaticAssetsUseImmutableCache(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/_astro/site.css", nil)
	response := httptest.NewRecorder()

	newHandler(metadata.Config{}, testSite()).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("unexpected status: %d", response.Code)
	}
	if cacheControl := response.Header().Get("Cache-Control"); cacheControl != "public, max-age=31536000, immutable" {
		t.Fatalf("unexpected cache control: %s", cacheControl)
	}
}

func TestStaticDirectoriesWithoutIndexAreNotListed(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/images/", nil)
	response := httptest.NewRecorder()

	newHandler(metadata.Config{}, testSite()).ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("unexpected status: %d", response.Code)
	}
	if body := response.Body.String(); strings.Contains(body, "photo.jpg") {
		t.Fatalf("directory contents were exposed: %s", body)
	}
}

func testSite() fstest.MapFS {
	return fstest.MapFS{
		"index.html":       {Data: []byte("<!doctype html><title>Presently</title>")},
		"_astro/site.css":  {Data: []byte("body {}")},
		"images/photo.jpg": {Data: []byte("not a real image")},
	}
}
