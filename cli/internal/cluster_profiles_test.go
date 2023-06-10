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

func TestByoosSystemUriValues(t *testing.T) {
	options := UserSelections{
		ImageRegistryURL:            "registryUrl",
		ImageRegistryRepository:     "repo",
		KubernetesDistro:            "k8s",
		OperatingSystemDistro:       "os",
		PaletteEdgeInstallerVersion: "1.2.3",
		CustomTag:                   "tag",
		OperatingSystemVersion:      "v4.5.6",
	}
	expected := `  system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"
  system.registry: registryUrl
  system.repo: repo
  system.k8sDistribution: k8s
  system.osName: os
  system.peVersion: v1.2.3
  system.customTag: tag
  system.osVersion: v4.5.6`
	got := byoosSystemUriValues(options)

	if got != expected {
		t.Errorf("Expected:\n%s\nGot:\n%s\n", expected, got)
	}

	// Check for correct whitespaces
	lines := strings.Split(got, "\n")
	for i, line := range lines {
		if !strings.HasPrefix(line, "  ") {
			t.Errorf("Line %d does not start with correct whitespace: %s", i+1, line)
		}
	}
}
