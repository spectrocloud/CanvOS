package internal

import (
	"net/http"
)

// DefaultHTTPClient returns the default HTTP client for the application.
// This is used for all HTTP requests.
// It is configured to use the system proxy and HTTP/2.
func DefaultHTTPClient() *http.Client {
	return &http.Client{
		Transport: &http.Transport{
			Proxy:             http.ProxyFromEnvironment,
			ForceAttemptHTTP2: true,
		},
	}
}

// GetUserAgentString returns the user agent for the HTTP client.
func GetUserAgentString(version string) string {

	if version != "" {
		return DefaultUserAgent + "/v" + version
	}

	return DefaultUserAgent

}
