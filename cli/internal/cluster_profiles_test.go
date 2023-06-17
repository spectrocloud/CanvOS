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
	testCases := []struct {
		name     string
		options  UserSelections
		expected string
	}{
		{
			name: "Test case 1",
			options: UserSelections{
				ImageRegistryURL:            "ttl.sh",
				ImageRegistryRepository:     "myrepo",
				KubernetesDistro:            "k8s",
				OperatingSystemDistro:       "ubuntu",
				PaletteEdgeInstallerVersion: "1.2.3",
				CustomTag:                   "tag",
				OperatingSystemVersion:      "20.15",
			},
			expected: `  system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"
  system.registry: ttl.sh
  system.repo: myrepo
  system.k8sDistribution: kubeadm
  system.osName: ubuntu
  system.peVersion: v1.2.3
  system.customTag: tag
  system.osVersion: 20`,
		},
		{
			name: "Test case 2",
			options: UserSelections{
				ImageRegistryURL:            "ttl.sh",
				ImageRegistryRepository:     "customRepo",
				KubernetesDistro:            "k3s",
				OperatingSystemDistro:       "opensuse",
				PaletteEdgeInstallerVersion: "3.2.1",
				CustomTag:                   "anotherTag",
				OperatingSystemVersion:      "15.04",
			},
			expected: `  system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"
  system.registry: ttl.sh
  system.repo: customRepo
  system.k8sDistribution: k3s
  system.osName: opensuse-leap
  system.peVersion: v3.2.1
  system.customTag: anotherTag
  system.osVersion: 15`,
		},
		{
			name: "Test case 3",
			options: UserSelections{
				ImageRegistryURL:            "dockerhub.com",
				ImageRegistryRepository:     "opensuse",
				KubernetesDistro:            "rke2",
				OperatingSystemDistro:       "opensuse",
				PaletteEdgeInstallerVersion: "3.4.3",
				CustomTag:                   "demo",
				OperatingSystemVersion:      "16.44",
			},
			expected: `  system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"
  system.registry: dockerhub.com
  system.repo: opensuse
  system.k8sDistribution: rke2
  system.osName: opensuse-leap
  system.peVersion: v3.4.3
  system.customTag: demo
  system.osVersion: 16`,
		},
		{
			name: "Test case 4",
			options: UserSelections{
				ImageRegistryURL:            "dockerhub.com",
				ImageRegistryRepository:     "micro",
				KubernetesDistro:            "k8s",
				OperatingSystemDistro:       "opensuse",
				PaletteEdgeInstallerVersion: "3.4.3",
				CustomTag:                   "demo",
				OperatingSystemVersion:      "22.04",
			},
			expected: `  system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"
  system.registry: dockerhub.com
  system.repo: micro
  system.k8sDistribution: kubeadm
  system.osName: opensuse-leap
  system.peVersion: v3.4.3
  system.customTag: demo
  system.osVersion: 22`,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			got := byoosSystemUriValues(tc.options)
			if got != tc.expected {
				t.Errorf("Expected:\n%s\nGot:\n%s\n", tc.expected, got)
			}

			// Check for correct whitespaces
			lines := strings.Split(got, "\n")
			for i, line := range lines {
				if !strings.HasPrefix(line, "  ") {
					t.Errorf("Line %d does not start with correct whitespace: %s", i+1, line)
				}
			}
		})
	}
}
