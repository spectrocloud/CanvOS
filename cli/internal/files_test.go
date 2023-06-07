package internal

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestDynamicCreateMenuOptionsFile(t *testing.T) {

	pathSeparator := string(os.PathSeparator)

	CreateCanvOsDir(".canvos")
	// Create a mock Packs slice
	packs := []Packs{
		{
			Items: []Pack{
				{
					Spec: Spec{
						Layer:   "k8s",
						Name:    "edge-k8s",
						Version: "1.0",
					},
				},
				{
					Spec: Spec{
						Layer:   "cni",
						Name:    "calico",
						Version: "2.0",
					},
				},
				{
					Spec: Spec{
						Layer:   "os",
						Name:    "edge-native-byoi",
						Version: "3.0",
					},
				},
			},
		},
	}

	// Call the function and check for errors
	err := DynamicCreateMenuOptionsFile(packs)
	if err != nil {
		t.Fatalf("CreateMenuOptionsFile returned an error: %v", err)
	}

	// Read the file and unmarshal the JSON data
	filePath := DefaultCanvOsDir + pathSeparator + "options.json"
	data, err := os.ReadFile(filePath)
	if err != nil {
		t.Fatalf("Could not read file: %v", err)
	}

	// Delete the file after use
	defer os.Remove(filePath)

	var result map[string]map[string][]string
	err = json.Unmarshal(data, &result)
	if err != nil {
		t.Fatalf("Could not unmarshal JSON data: %v", err)
	}

	// Create the expected result
	expected := map[string]map[string][]string{
		"k8s": {
			"edge-k8s": {"1.0"},
		},
		"cni": {
			"calico": {"2.0"},
		},
		"os": {
			"edge-native-byoi": {"3.0"},
		},
	}

	// Compare the actual result with the expected result
	if !reflect.DeepEqual(result, expected) {
		t.Errorf("Result was incorrect, got: %v, want: %v", result, expected)
	}
}

func TestCreateMenuOptionsFile(t *testing.T) {
	// arrange
	packs := []Packs{
		{
			Items: []Pack{
				{
					Spec: Spec{
						Name:    "edge-k8s",
						Version: "1.0",
						Type:    "k8s",
						Layer:   "k8s",
					},
				},
				{
					Spec: Spec{
						Name:    "cni-calico",
						Version: "2.0",
						Type:    "cni",
						Layer:   "cni",
					},
				},
				{
					Spec: Spec{
						Name:    "edge-native-byoi",
						Version: "3.0",
						Type:    "os",
						Layer:   "os",
					},
				},
			},
		},
	}

	paletteVersions := []string{"1.0", "2.0", "3.0"}

	// temporarily change DefaultCanvOsDir to a temp dir
	tempDir := filepath.Join(DefaultCanvOsDir, t.TempDir())
	os.MkdirAll(tempDir, os.ModePerm)
	defer os.RemoveAll(tempDir)

	// act
	err := CreateMenuOptionsFile(packs, paletteVersions)

	// assert
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}

	// Check if the file was created in the expected location
	_, err = os.Stat(DefaultCanvOsDir + string(os.PathSeparator) + "options.json")
	if err != nil {
		t.Fatalf("Expected options.json to be created, got error: %v", err)
	}

	// Optionally: Load the file and check if it contains the expected content
	// This depends on how exactly the function is supposed to format the output
}

func TestCreateDemoUserData(t *testing.T) {
	token := "testToken"

	err := CreateDemoUserData(token)
	if err != nil {
		t.Fatal("Error creating config file:", err)
	}

	fileName := "user-data"
	data, err := os.ReadFile(fileName)
	if err != nil {
		t.Fatal("Error reading config file:", err)
	}

	defer os.Remove(fileName) // Cleanup after the test

	expectedContent := `
#cloud-config
stylus:
  site:
    edgeHostToken: testToken
install:
  poweroff: true
users:
  - name: kairos
    passwd: kairos
    `

	if normalizeSpace(string(data)) != normalizeSpace(expectedContent) {
		t.Fatalf("Unexpected file content. Got \n%s\n, expected \n%s\n", data, expectedContent)
	}
}

func normalizeSpace(s string) string {
	return strings.Join(strings.Fields(s), "\n")
}

func TestCreateDemoArgsFile(t *testing.T) {
	u := UserSelections{
		ImageRegistryURL:       "ttl.sh",
		OperatingSystemDistro:  "ubuntu",
		OperatingSystemVersion: "22.04",
		KubernetesDistro:       "k3s",
		ISOName:                "palette-edge-installer",
	}

	err := CreateDemoArgsFile(u)
	if err != nil {
		t.Fatalf("expected no error but got: %v", err)
	}

	fileName := ".arg"
	// defer os.Remove(fileName) // Cleanup after the test

	content, err := os.ReadFile(fileName)
	if err != nil {
		t.Fatalf("expected no error but got: %v", err)
	}

	expectedContent := `
	CUSTOM_TAG=demo
	IMAGE_REGISTRY=ttl.sh
	OS_DISTRIBUTION=ubuntu
	IMAGE_REPO=ubuntu
	OS_VERSION=22.04
	K8S_DISTRIBUTION=k3s
	ISO_NAME=palette-edge-installer
	`

	// Remove leading and trailing whitespaces and newline characters
	// expectedContent = strings.TrimSpace(expectedContent)
	// fileContent := strings.TrimSpace(string(content))

	if normalizeSpace(string(content)) != normalizeSpace(expectedContent) {
		t.Fatalf("Unexpected file content. Got \n%s\n, expected \n%s\n", content, expectedContent)
	}

	// if fileContent != expectedContent {
	// 	t.Errorf("unexpected content: \n want %v \n got  %v", expectedContent, fileContent)
	// }
}
