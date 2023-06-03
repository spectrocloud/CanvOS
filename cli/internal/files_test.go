package internal

import (
	"encoding/json"
	"io/ioutil"
	"os"
	"path/filepath"
	"reflect"
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
	data, err := ioutil.ReadFile(filePath)
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

	// temporarily change DefaultCanvOsDir to a temp dir
	tempDir := filepath.Join(DefaultCanvOsDir, t.TempDir())
	os.MkdirAll(tempDir, os.ModePerm)
	defer os.RemoveAll(tempDir)

	// act
	err := CreateMenuOptionsFile(packs)

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
