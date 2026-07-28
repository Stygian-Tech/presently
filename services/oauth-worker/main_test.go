package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"presently/oauth-worker/metadata"
)

func TestHealth(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	response := httptest.NewRecorder()

	newHandler(metadata.Config{}).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("unexpected status: %d", response.Code)
	}
	if response.Body.String() != `{"status":"ok"}` {
		t.Fatalf("unexpected body: %s", response.Body.String())
	}
}

func TestHomepageDescribesOAuthService(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	response := httptest.NewRecorder()

	newHandler(metadata.Config{}).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("unexpected status: %d", response.Code)
	}
	if contentType := response.Header().Get("Content-Type"); contentType != "text/html; charset=utf-8" {
		t.Fatalf("unexpected content type: %s", contentType)
	}
	if body := response.Body.String(); !strings.Contains(body, `Presently OAuth`) {
		t.Fatalf("homepage does not describe OAuth service: %s", body)
	}
	if body := response.Body.String(); !strings.Contains(body, `/oauth/client-metadata.json`) {
		t.Fatalf("homepage does not link to client metadata: %s", body)
	}
}

func TestUnknownRouteIsNotFound(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/support/", nil)
	response := httptest.NewRecorder()

	newHandler(metadata.Config{}).ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("unexpected status: %d", response.Code)
	}
}
