package internal

import (
	"testing"
	"time"
)

func TestNewDockerClient(t *testing.T) {
	client, err := NewDockerClient()

	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	// Verify that the returned client is not nil
	if client == nil {
		t.Error("Expected Docker client to be created, but got nil")
	}

	// Verify that the client has the expected timeout value
	expectedTimeout := 30 * time.Second
	actualTimeout := client.HTTPClient().Timeout
	if actualTimeout != expectedTimeout {
		t.Errorf("Expected timeout of %s, but got %s", expectedTimeout, actualTimeout)
	}
}

func TestGetEncodedAuth(t *testing.T) {
	authConfig := RegistryAuthConfig{
		Username: "username",
		Password: "password",
	}

	expected := "eyJVc2VybmFtZSI6InVzZXJuYW1lIiwiUGFzc3dvcmQiOiJwYXNzd29yZCJ9"

	actual, err := authConfig.GetEncodedAuth()
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if actual != expected {
		t.Errorf("Expected %s, but got %s", expected, actual)
	}
}
