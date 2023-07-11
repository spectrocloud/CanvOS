package internal

import (
	"os"
	"testing"
)

func TestGetenv(t *testing.T) {
	key := "MY_ENV_VAR"
	fallback := "default_value"

	// Environment variable is set
	os.Setenv(key, "my_value")
	defer os.Unsetenv(key)
	if result := Getenv(key, fallback); result != "my_value" {
		t.Errorf("Getenv(%q, %q) = %q; expected %q", key, fallback, result, "my_value")
	}

	// Environment variable is not set, fallback value should be returned
	os.Unsetenv(key)
	defer os.Setenv(key, fallback)
	if result := Getenv(key, fallback); result != fallback {
		t.Errorf("Getenv(%q, %q) = %q; expected %q", key, fallback, result, fallback)
	}

	// Environment variable is set but empty, fallback value should be returned
	os.Setenv(key, "")
	defer os.Unsetenv(key)
	if result := Getenv(key, fallback); result != fallback {
		t.Errorf("Getenv(%q, %q) = %q; expected %q", key, fallback, result, fallback)
	}

	os.Clearenv()
}
