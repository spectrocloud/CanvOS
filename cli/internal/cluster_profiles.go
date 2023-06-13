package internal

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/rs/zerolog/log"
)

// GenerateClusterProfileName generates a name for the cluster profile using a provided suffix.
// To ensure uniqueness, the name will be generated using the following format:
// edge-<suffix>-<YYYY-MM-DD>-<SHA-256 hash of ipsum string>
// Note: The SHA-256 hash will be truncated to 7 characters
// Example: edge-demo-2021-01-01-1234567
func GenerateClusterProfileName(suffix string) string {
	// Get current time
	now := time.Now()

	// Format date as 'YYYY-MM-DD'
	todayString := now.Format("2006-01-02")

	// Add current timestamp (in nanoseconds) to the fixed string
	inputString := fmt.Sprintf("Soluta fugit ducimus et sunt reiciendis %d", now.UnixNano())

	hash := sha256.Sum256([]byte(inputString))
	hashString := hex.EncodeToString(hash[:])
	shaPart := hashString[:7]

	// Combine to create the final string
	finalString := fmt.Sprintf("edge-%s-%s-%s", suffix, todayString, shaPart)

	return finalString
}

// CreateEdgeClusterProfilePayLoad creates the payload for the Edge cluster profile API call.
// There are three layers to the cluster profile: OS, K8s, and CNI.
// The reurn payload will be a ClusterProfile struct.
func CreateEdgeClusterDemoProfilePayLoad(options UserSelections, rawValues *OptionsMenu) (ClusterProfile, error) {
	var output ClusterProfile

	osTemplate, err := getByoosPackValues(options)
	if err != nil {
		log.Debug().Msgf("err %s: ", err)
		return output, errors.New("error getting the edge-native-byoi pack values")
	}

	k8sTemplate, err := getKubernetesPackValues(options)
	if err != nil {
		log.Debug().Msgf("err %s: ", err)
		return output, errors.New("error getting the kubernetes pack values")
	}

	cniTemplate, err := getCniPackValues(options)
	if err != nil {
		log.Debug().Msgf("err %s: ", err)
		return output, errors.New("error getting the cni pack values")
	}

	output.Metadata.Name = GenerateClusterProfileName(options.ClusterProfileSuffix)
	output.Metadata.Annotations.Description = "CanvOS created Edge cluster profile"
	output.Metadata.Labels.CreatedBy = "canvos"
	output.Metadata.Labels.Type = "edge"
	output.Spec.Template.CloudType = "edge-native"
	output.Spec.Template.Type = "cluster"
	output.Spec.Version = "1.0.0"

	byoosPackUID, byoosRegistryID := rawValues.GetPackUIDs("edge-native-byoi", options.BYOOSVersion)
	k8sPackUID, k8sRegistryID := rawValues.GetPackUIDs(options.KubernetesDistro, options.KubernetesVersion)
	cniPackUID, cniRegistryID := rawValues.GetPackUIDs(options.CNI, options.CNIVersion)

	output.Spec.Template.Packs = []PacksCP{
		{
			Name:        "edge-native-byoi",
			RegistryUID: byoosRegistryID,
			Tag:         options.BYOOSVersion,
			Values:      osTemplate,
			PackUID:     byoosPackUID,
			Logo:        "https://registry.spectrocloud.com/v1/edge-native-byoi/blobs/sha256:b6081bca439eeb01a8d43b3cb6895df4c088f80af978856ddc0da568e5c09365?type=image/png",
			Type:        "spectro",
			UID:         byoosPackUID,
			Template: TemplatePacks{
				Parameters: ParametersCP{
					InputParameters:  []string{},
					OutputParameters: []string{},
				},
			},
			Manifests: []string{},
		},
		{
			Name:        "edge-k3s",
			RegistryUID: k8sRegistryID,
			Tag:         options.KubernetesVersion,
			Values:      k8sTemplate,
			PackUID:     k8sPackUID,
			Type:        "spectro",
			UID:         k8sPackUID,
			Template: TemplatePacks{
				Parameters: ParametersCP{
					InputParameters:  []string{},
					OutputParameters: []string{},
				},
			},
			Manifests: []string{},
		},
		{
			Name:        "cni-calico",
			RegistryUID: cniRegistryID,
			Tag:         options.CNIVersion,
			Values:      cniTemplate,
			PackUID:     cniPackUID,
			Type:        "spectro",
			UID:         cniPackUID,
			Template: TemplatePacks{
				Parameters: ParametersCP{
					InputParameters:  []string{},
					OutputParameters: []string{},
				},
			},
			Manifests: []string{},
		},
	}

	return output, nil
}

// getByoosPackValues returns the values for the edge-native-byoi pack.
func getByoosPackValues(options UserSelections) (string, error) {
	var values string

	path := DefaultCanvOsDir + string(os.PathSeparator) + "os" + string(os.PathSeparator) + "edge-native-byoi-" + options.BYOOSVersion + ".yaml"

	raw, err := os.ReadFile(path)
	if err != nil {
		return values, err
	}

	content := string(raw)
	lines := strings.Split(content, "\n")
	// Identify the start of the section to replace
	startIndex := -1
	for i, line := range lines {
		if strings.TrimSpace(line) == "system.uri: \"\"" {
			startIndex = i
			break
		}
	}
	if startIndex == -1 {
		return values, errors.New("unable to find system.uri in edge-native-byoi pack")
	}
	newLines := append(lines[:startIndex], byoosSystemUriValues(options))
	values = strings.Join(newLines, "\n")

	return values, nil
}

// byoosSystemUriValues returns the values for the system.uri section of the edge-native-byoi pack.
// Do not mofidy the whitespace in this string.
func byoosSystemUriValues(options UserSelections) string {
	newValue := fmt.Sprintf(
		`  system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"
  system.registry: %s
  system.repo: %s
  system.k8sDistribution: %s
  system.osName: %s
  system.peVersion: v%s
  system.customTag: %s
  system.osVersion: %s`,
		options.ImageRegistryURL,
		options.ImageRegistryRepository,
		options.KubernetesDistro,
		options.OperatingSystemDistro,
		options.PaletteEdgeInstallerVersion,
		options.CustomTag,
		options.OperatingSystemVersion)

	return newValue
}

// getKubernetesPackValues returns the values for the kubernetes pack.
func getKubernetesPackValues(options UserSelections) (string, error) {

	var (
		values  string
		k8sName string
	)

	switch options.KubernetesDistro {
	case "k3s":
		k8sName = "edge-k3s-"
	case "k8s":
		k8sName = "edge-k8s-"
	case "rke2":
		k8sName = "edge-rke2-"
	case "microk8s":
		k8sName = "edge-microk8s-"
	default:
		return values, errors.New("invalid kubernetes distro")
	}

	path := DefaultCanvOsDir + string(os.PathSeparator) + "k8s" + string(os.PathSeparator) + k8sName + options.KubernetesVersion + ".yaml"

	raw, err := os.ReadFile(path)
	if err != nil {
		log.Info().Msgf("err %s: ", err)
		return values, err
	}

	return string(raw), nil

}

// getCniPackValues returns the values for the cni pack.
func getCniPackValues(options UserSelections) (string, error) {
	var (
		values  string
		cniName string
	)

	switch options.CNI {
	case "calico":
		cniName = "cni-calico-"
	case "flannel":
		cniName = "cni-flannel-"
	case "cilium":
		cniName = "cni-cilium-"
	default:
		return values, errors.New("invalid cni")

	}

	path := DefaultCanvOsDir + string(os.PathSeparator) + "cni" + string(os.PathSeparator) + cniName + options.CNIVersion + ".yaml"

	raw, err := os.ReadFile(path)
	if err != nil {
		log.Info().Msgf("err %s: ", err)
		return values, err
	}

	return string(raw), nil

}
