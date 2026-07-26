package metadata

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestBuildDeclaresOnlyMVPPermissions(t *testing.T) {
	document, err := Build("https://presently.stygian.tech", Config{
		ClientID:    "https://presently.stygian.tech/oauth/client-metadata.json",
		RedirectURI: "tech.stygian.presently:/oauth/callback",
	})
	if err != nil {
		t.Fatal(err)
	}

	if document.ClientID != "https://presently.stygian.tech/oauth/client-metadata.json" {
		t.Fatalf("unexpected client ID: %s", document.ClientID)
	}
	if document.ApplicationType != "native" {
		t.Fatalf("unexpected application type: %s", document.ApplicationType)
	}
	if document.Scope != Scope {
		t.Fatalf("unexpected scope: %s", document.Scope)
	}
	if document.Scope != "atproto repo:blue.flashes.story.post?action=create blob:image/jpeg" {
		t.Fatalf("scope is broader than the MVP contract: %s", document.Scope)
	}
	if !document.DPoPBoundAccessTokens || document.TokenEndpointAuth != "none" {
		t.Fatal("native public-client OAuth metadata is invalid")
	}
}

func TestHandlerServesJSONWithoutRedirect(t *testing.T) {
	handler := Handler(Config{
		ClientID:    "https://presently.stygian.tech/oauth/client-metadata.json",
		RedirectURI: "tech.stygian.presently:/oauth/callback",
	})
	request := httptest.NewRequest(http.MethodGet, "https://presently.stygian.tech/oauth/client-metadata.json", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("unexpected status: %d", response.Code)
	}
	if contentType := response.Header().Get("Content-Type"); contentType != "application/json; charset=utf-8" {
		t.Fatalf("unexpected content type: %s", contentType)
	}

	var document Document
	if err := json.NewDecoder(response.Body).Decode(&document); err != nil {
		t.Fatal(err)
	}
	if document.ClientID != "https://presently.stygian.tech/oauth/client-metadata.json" {
		t.Fatalf("unexpected client ID: %s", document.ClientID)
	}
}

func TestBuildRequiresStableProductionClientID(t *testing.T) {
	_, err := Build("https://presently-preview.vercel.app", Config{})
	if !errors.Is(err, ErrInvalidConfiguration) {
		t.Fatalf("expected configuration error, got %v", err)
	}
}

func TestBuildRejectsMismatchedRedirectScheme(t *testing.T) {
	_, err := Build("https://presently.stygian.tech", Config{
		ClientID:    "https://presently.stygian.tech/oauth/client-metadata.json",
		RedirectURI: "com.example.presently:/oauth/callback",
	})
	if !errors.Is(err, ErrInvalidConfiguration) {
		t.Fatalf("expected configuration error, got %v", err)
	}
}
