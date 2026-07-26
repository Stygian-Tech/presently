package main

import (
	"net/http"
	"net/http/httptest"
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
