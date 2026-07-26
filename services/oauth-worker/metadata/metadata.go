package metadata

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"os"
	"strings"
)

const (
	Scope                = "atproto repo:blue.flashes.story.post?action=create blob:image/jpeg"
	defaultRedirectURI   = "tech.stygian.presently:/oauth/callback"
	metadataDocumentPath = "/oauth/client-metadata.json"
)

var ErrInvalidConfiguration = errors.New("invalid OAuth client metadata configuration")

type Config struct {
	ClientID    string
	RedirectURI string
	ClientURI   string
	PolicyURI   string
	TermsURI    string
}

type Document struct {
	ClientID              string   `json:"client_id"`
	ApplicationType       string   `json:"application_type"`
	ClientName            string   `json:"client_name"`
	ClientURI             string   `json:"client_uri"`
	DPoPBoundAccessTokens bool     `json:"dpop_bound_access_tokens"`
	GrantTypes            []string `json:"grant_types"`
	RedirectURIs          []string `json:"redirect_uris"`
	ResponseTypes         []string `json:"response_types"`
	Scope                 string   `json:"scope"`
	TokenEndpointAuth     string   `json:"token_endpoint_auth_method"`
	PolicyURI             string   `json:"policy_uri,omitempty"`
	TermsURI              string   `json:"tos_uri,omitempty"`
}

func ConfigFromEnvironment() Config {
	return Config{
		ClientID:    os.Getenv("PRESENTLY_CLIENT_ID"),
		RedirectURI: os.Getenv("PRESENTLY_REDIRECT_URI"),
		ClientURI:   os.Getenv("PRESENTLY_CLIENT_URI"),
		PolicyURI:   os.Getenv("PRESENTLY_POLICY_URI"),
		TermsURI:    os.Getenv("PRESENTLY_TOS_URI"),
	}
}

func Build(requestOrigin string, config Config) (Document, error) {
	origin, err := url.Parse(requestOrigin)
	if err != nil || origin.Hostname() == "" {
		return Document{}, configurationError("request origin must be a valid URL")
	}
	isLocal := origin.Hostname() == "localhost" || origin.Hostname() == "127.0.0.1"

	clientID := config.ClientID
	if clientID == "" {
		if !isLocal {
			return Document{}, configurationError("PRESENTLY_CLIENT_ID is required")
		}
		clientID = strings.TrimRight(requestOrigin, "/") + metadataDocumentPath
	}

	clientIDURL, err := requireClientID(clientID, isLocal)
	if err != nil {
		return Document{}, err
	}

	clientURI := config.ClientURI
	if clientURI == "" {
		clientURI = clientIDURL.Scheme + "://" + clientIDURL.Host
	}
	clientURIURL, err := requireSameHostURL(clientURI, "PRESENTLY_CLIENT_URI", clientIDURL)
	if err != nil {
		return Document{}, err
	}

	redirectURI := config.RedirectURI
	if redirectURI == "" {
		redirectURI = defaultRedirectURI
	}
	if err := validateRedirectURI(redirectURI, clientIDURL); err != nil {
		return Document{}, err
	}

	policyURI, err := optionalSameHostURL(config.PolicyURI, "PRESENTLY_POLICY_URI", clientIDURL)
	if err != nil {
		return Document{}, err
	}
	termsURI, err := optionalSameHostURL(config.TermsURI, "PRESENTLY_TOS_URI", clientIDURL)
	if err != nil {
		return Document{}, err
	}

	return Document{
		ClientID:              clientIDURL.String(),
		ApplicationType:       "native",
		ClientName:            "Presently",
		ClientURI:             clientURIURL.String(),
		DPoPBoundAccessTokens: true,
		GrantTypes:            []string{"authorization_code", "refresh_token"},
		RedirectURIs:          []string{redirectURI},
		ResponseTypes:         []string{"code"},
		Scope:                 Scope,
		TokenEndpointAuth:     "none",
		PolicyURI:             policyURI,
		TermsURI:              termsURI,
	}, nil
}

func Handler(config Config) http.Handler {
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		document, err := Build(requestOrigin(request), config)
		if err != nil {
			response.Header().Set("Cache-Control", "no-store")
			response.Header().Set("Content-Type", "application/json; charset=utf-8")
			response.WriteHeader(http.StatusInternalServerError)
			_ = json.NewEncoder(response).Encode(map[string]string{
				"error": "OAuth client metadata is not configured.",
			})
			return
		}

		response.Header().Set("Access-Control-Allow-Origin", "*")
		response.Header().Set("Cache-Control", "public, max-age=300, s-maxage=300")
		response.Header().Set("Content-Type", "application/json; charset=utf-8")
		response.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(response).Encode(document)
	})
}

func requestOrigin(request *http.Request) string {
	scheme := request.Header.Get("X-Forwarded-Proto")
	if scheme == "" {
		if request.TLS != nil {
			scheme = "https"
		} else {
			scheme = "http"
		}
	}
	return scheme + "://" + request.Host
}

func requireClientID(value string, allowLocalHTTP bool) (*url.URL, error) {
	parsed, err := url.Parse(value)
	if err != nil || parsed.Hostname() == "" {
		return nil, configurationError("PRESENTLY_CLIENT_ID must be a valid URL")
	}

	isAllowedLocalHTTP := allowLocalHTTP &&
		parsed.Scheme == "http" &&
		(parsed.Hostname() == "localhost" || parsed.Hostname() == "127.0.0.1")
	if parsed.Scheme != "https" && !isAllowedLocalHTTP {
		return nil, configurationError("PRESENTLY_CLIENT_ID must use HTTPS")
	}
	if parsed.Port() != "" && !isAllowedLocalHTTP {
		return nil, configurationError("PRESENTLY_CLIENT_ID must not include a port")
	}
	return parsed, nil
}

func requireSameHostURL(value string, name string, clientID *url.URL) (*url.URL, error) {
	parsed, err := url.Parse(value)
	if err != nil || parsed.Hostname() == "" {
		return nil, configurationError(name + " must be a valid URL")
	}
	if clientID.Scheme == "https" && parsed.Scheme != "https" {
		return nil, configurationError(name + " must use HTTPS")
	}
	if parsed.Hostname() != clientID.Hostname() {
		return nil, configurationError(name + " must match the client ID hostname")
	}
	return parsed, nil
}

func optionalSameHostURL(value string, name string, clientID *url.URL) (string, error) {
	if value == "" {
		return "", nil
	}
	parsed, err := requireSameHostURL(value, name, clientID)
	if err != nil {
		return "", err
	}
	return parsed.String(), nil
}

func validateRedirectURI(value string, clientID *url.URL) error {
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme == "" {
		return configurationError("PRESENTLY_REDIRECT_URI must be a valid URI")
	}

	if parsed.Scheme == "https" {
		if parsed.Scheme != clientID.Scheme || parsed.Host != clientID.Host {
			return configurationError("HTTPS redirect URI must match the client ID origin")
		}
		return nil
	}

	hostnameSegments := strings.Split(clientID.Hostname(), ".")
	for left, right := 0, len(hostnameSegments)-1; left < right; left, right = left+1, right-1 {
		hostnameSegments[left], hostnameSegments[right] = hostnameSegments[right], hostnameSegments[left]
	}
	expectedScheme := strings.Join(hostnameSegments, ".")
	if parsed.Scheme != expectedScheme {
		return configurationError("native redirect scheme must match the reversed client ID host")
	}
	return nil
}

func configurationError(message string) error {
	return errors.Join(ErrInvalidConfiguration, errors.New(message))
}
