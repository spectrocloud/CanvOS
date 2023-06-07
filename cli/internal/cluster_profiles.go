package internal

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"
)

// GenerateClusterProfileName generates a name for the cluster profile using a provided suffix.
// To ensure uniqueness, the name will be generated using the following format:
// edge-<suffix>-<YYYY-MM-DD>-<SHA-256 hash of ipsum string>
// Note: The SHA-256 hash will be truncated to 7 characters
// Example: edge-demo-2021-01-01-1234567
func GenerateClusterProfileName(suffix string) string {
	// Get today's date
	today := time.Now()

	// Format date as 'YYYY-MM-DD'
	todayString := today.Format("2006-01-02")
	hash := sha256.Sum256([]byte("Soluta fugit ducimus et sunt reiciendis"))
	hashString := hex.EncodeToString(hash[:])
	shaPart := hashString[:7]

	// Combine to create the final string
	finalString := fmt.Sprintf("edge-%s-%s-%s", suffix, todayString, shaPart)

	return finalString
}

// CreateEdgeClusterProfilePayLoad creates the payload for the Edge cluster profile API call.
// There are three layers to the cluster profile: OS, K8s, and CNI.
// The reurn payload will be a string that can be used in the API call.
func CreateEdgeClusterProfilePayLoad(option UserSelections) string {
	var payload string

	return payload
}
