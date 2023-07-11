package internal

import "os"

// getEnv returns the value of the environment variable or a default value
func Getenv(key, fallback string) string {
	value := os.Getenv(key)
	if len(value) == 0 {
		return fallback
	}

	return value
}
