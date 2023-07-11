package internal

import (
	"encoding/json"
	"fmt"
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

func TestCreateArgsFile(t *testing.T) {
	testCases := []struct {
		name     string
		user     UserSelections
		expected string
	}{
		{
			name: "Test case 1",
			user: UserSelections{
				CustomTag:                   "demo",
				ImageRegistryURL:            "ttl.sh",
				ImageRegistryRepository:     "ubuntu",
				OperatingSystemDistro:       "ubuntu",
				OperatingSystemVersion:      "22.04",
				KubernetesDistro:            "k3s",
				ISOName:                     "palette-edge-installer",
				PaletteEdgeInstallerVersion: "3.4.3",
				Platform:                    "linux/amd64",
			},
			expected: `
                CUSTOM_TAG=demo
                IMAGE_REGISTRY=ttl.sh
                OS_DISTRIBUTION=ubuntu
                IMAGE_REPO=ubuntu
                OS_VERSION=22
                K8S_DISTRIBUTION=k3s
                ISO_NAME=palette-edge-installer
                PE_VERSION=v3.4.3
                platform=linux/amd64
            `,
		},
		{
			name: "Test case 2",
			user: UserSelections{
				CustomTag:                   "test",
				ImageRegistryURL:            "registry.com",
				ImageRegistryRepository:     "custom",
				OperatingSystemDistro:       "opensuse",
				OperatingSystemVersion:      "15.04",
				KubernetesDistro:            "k8s",
				ISOName:                     "palette-edge",
				PaletteEdgeInstallerVersion: "3.4.3",
				Platform:                    "linux/amd64",
			},
			expected: `
                CUSTOM_TAG=test
                IMAGE_REGISTRY=registry.com
                OS_DISTRIBUTION=opensuse-leap
                IMAGE_REPO=custom
                OS_VERSION=15
                K8S_DISTRIBUTION=kubeadm
                ISO_NAME=palette-edge
                PE_VERSION=v3.4.3
                platform=linux/amd64
            `,
		},
		{
			name: "Test case 3",
			user: UserSelections{
				CustomTag:                   "demo",
				ImageRegistryURL:            "ttl.sh",
				ImageRegistryRepository:     "ubuntu",
				OperatingSystemDistro:       "Ubuntu",
				OperatingSystemVersion:      "22.04",
				KubernetesDistro:            "k3s",
				ISOName:                     "palette-edge",
				PaletteEdgeInstallerVersion: "3.4.3",
				Platform:                    "linux/amd64",
			},
			expected: `
                CUSTOM_TAG=demo
                IMAGE_REGISTRY=ttl.sh
                OS_DISTRIBUTION=ubuntu
                IMAGE_REPO=ubuntu
                OS_VERSION=22
                K8S_DISTRIBUTION=k3s
                ISO_NAME=palette-edge
                PE_VERSION=v3.4.3
                platform=linux/amd64
            `,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			fileName := fmt.Sprintf(".arg_%s", tc.name) // Unique file for each test
			defer os.Remove(fileName)                   // Cleanup after the test

			err := CreateArgsFile(fileName, tc.user)
			if err != nil {
				t.Fatalf("expected no error but got: %v", err)
			}

			content, err := os.ReadFile(fileName)
			if err != nil {
				t.Fatalf("expected no error but got: %v", err)
			}

			if normalizeSpace(string(content)) != normalizeSpace(tc.expected) {
				t.Fatalf("Unexpected file content. Got \n%s\n, expected \n%s\n", content, tc.expected)
			}
		})
	}
}

func TestCreateMenuOptionsFile(t *testing.T) {
	// arrange
	packs := []Packs{
		{
			Items: []Pack{
				{
					Spec: Spec{
						Name:        "edge-k3s",
						Version:     "1.20.4",
						RegistryUID: "5eecc89d0b150045ae661cef",
					},
					Metadata: Metadata{
						UID: "60917d9a5b3dba346b597f97",
					},
				},
				{
					Spec: Spec{
						Name:        "edge-k8s",
						Version:     "1.22.1",
						RegistryUID: "5eecc89d0b150045ae661cef",
					},
					Metadata: Metadata{
						UID: "626808fdd9c58677ccdd6390",
					},
				},
				{
					Spec: Spec{
						Name:        "cni-flannel",
						Version:     "0.13.0",
						RegistryUID: "ruid3",
					},
					Metadata: Metadata{
						UID: "136802fdd9c58677ccdd6390",
					},
				},
				{
					Spec: Spec{
						Name:        "edge-native-ubuntu",
						Version:     "20.04",
						RegistryUID: "5eecc89d0b150045ae661cef",
					},
					Metadata: Metadata{
						UID: "266802fdd9c58677ccdd6390",
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
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}

	// Check if the file was created in the expected location
	_, err = os.Stat(DefaultCanvOsDir + string(os.PathSeparator) + "options.json")
	if err != nil {
		t.Fatalf("Expected options.json to be created, got error: %v", err)
	}

	// Load the file and check if it contains the expected content
	file, _ := os.ReadFile(DefaultCanvOsDir + string(os.PathSeparator) + "options.json")
	var options OptionsMenu
	_ = json.Unmarshal([]byte(file), &options)

	// The expected output after the CreateMenuOptionsFile
	expectedOptions := OptionsMenu{
		Kubernetes: OptionsKubernetes{
			Edgek3S: AvailblePacks{
				RegistryUID: "5eecc89d0b150045ae661cef",
				Versions: []PackVersion{
					{
						Version: "1.20.4",
						UID:     "60917d9a5b3dba346b597f97",
					},
				},
			},
			EdgeK8S: AvailblePacks{
				RegistryUID: "5eecc89d0b150045ae661cef",
				Versions: []PackVersion{
					{
						Version: "1.22.1",
						UID:     "626808fdd9c58677ccdd6390",
					},
				},
			},
		},
		OperatingSystems: OptionsOperatingSystems{
			Ubuntu: AvailblePacks{
				RegistryUID: "5eecc89d0b150045ae661cef",
				Versions: []PackVersion{
					{
						Version: "20.04",
						UID:     "266802fdd9c58677ccdd6390",
					},
				},
			},
		},
		Cnis: OptionsCNIs{
			Flannel: AvailblePacks{
				RegistryUID: "ruid3",
				Versions: []PackVersion{
					{
						Version: "0.13.0",
						UID:     "136802fdd9c58677ccdd6390",
					},
				},
			},
		},
		PaletteVersions: paletteVersions,
	}

	if !reflect.DeepEqual(options, expectedOptions) {
		t.Fatalf("Expected %v, got %v", expectedOptions, options)
	}
}

func TestMoveContentFolder(t *testing.T) {
	// Create a temporary directory to work in.
	tempDir, err := os.MkdirTemp("", "test")
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("Created temporary directory: %s", tempDir)

	// Assume source directory with existing content.
	sourceDir := "../tests/content-123456"
	t.Logf("Source directory: %s", sourceDir)

	// Run the function.
	err = MoveContentFolder(sourceDir, tempDir)
	if err != nil {
		t.Fatal(err)
	}
	t.Log("Moved source directory to temporary directory")

	// Check that the directory starting with "content-" was moved.
	files, err := os.ReadDir(tempDir)
	if err != nil {
		t.Fatal(err)
	}
	moved := false
	for _, file := range files {
		if file.Name() == "content-123456" {
			moved = true
			t.Logf("Found %s in temporary directory", file.Name())
			break
		}
	}

	if !moved {
		t.Fatalf("Directory content-123456 was not moved to target directory")
	}

	// Check that the directory is no longer in the source directory.
	_, err = os.Stat(sourceDir)
	if err == nil {
		t.Errorf("Directory content-123456 was not removed from source directory")
	} else if !os.IsNotExist(err) {
		t.Error(err)
	} else {
		t.Log("Confirmed source directory was removed from original location")
	}

	// Move the folder back to the original location.
	err = MoveContentFolder(filepath.Join(tempDir, "content-123456"), filepath.Dir(sourceDir))
	if err != nil {
		t.Fatal(err)
	}
	t.Log("Moved directory back to original location")

	// Check that the directory is in the original location.
	_, err = os.Stat(sourceDir)
	if os.IsNotExist(err) {
		t.Errorf("Directory content-123456 was not moved back to original location")
	} else {
		t.Log("Confirmed directory is back in original location")
	}

	// Clean up temporary directory at the end of the test.
	err = os.RemoveAll(tempDir)
	if err != nil {
		t.Fatal(err)
	}
	t.Log("Cleaned up temporary directory")
}