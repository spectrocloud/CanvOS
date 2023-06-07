package internal

import (
	"strings"
	"testing"
)

func TestGenerateString(t *testing.T) {
	result := GenerateClusterProfileName("demo")

	// Check if string starts with 'edge-demo-'
	if !strings.HasPrefix(result, "edge-demo-") {
		t.Errorf("String should start with 'edge-demo-', got %v", result)
	}

	// Check if string length is correct
	// Assuming YYYY-MM-DD format for date and 7 characters for shaPart
	if len(result) != len("edge-demo-")+10+1+7 {
		t.Errorf("String length should be equal to length of 'edge-demo-' plus date plus shaPart, got %v", len(result))
	}
}
