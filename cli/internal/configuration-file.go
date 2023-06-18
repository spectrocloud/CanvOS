package internal

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v2"
)

// GetUserVaues reads the input file and returns a UserSelections struct
func GetUserVaues(file string) (UserSelections, CliConfig, error) {

	var (
		userSelections UserSelections
		cliConfig      CliConfig
	)

	fileType, err := determineFileType(file)
	if err != nil {
		log.Debug().Err(err)
		return userSelections, cliConfig, err
	}

	if err == nil && fileType == "yaml" {
		configValues, err := readConfigFileYaml(file)
		if err != nil {
			log.Debug().Err(err)
			return userSelections, cliConfig, err
		}

		registry := strings.Split(configValues.Config.RegistryConfig.RegistryURL, "/")[0]
		registryNamespace := strings.Split(configValues.Config.RegistryConfig.RegistryURL, "/")[1:]

		userSelections = UserSelections{
			// Sofware
			OperatingSystemDistro:  configValues.Config.Software.OsDistro,
			OperatingSystemVersion: configValues.Config.Software.OsVersion,
			KubernetesDistro:       configValues.Config.Software.KubernetesDistro,
			CNI:                    configValues.Config.Software.ContainerNetworkInterface,
			CNIVersion:             configValues.Config.Software.ContainerNetworkInterfaceVersion,
			// Registry
			ImageRegistryURL:        registry,
			ImageRegistryRepository: registryNamespace[0],
			ImageRegistryUsername:   configValues.Config.RegistryConfig.RegistryUsername,
			ImageRegistryPassword:   configValues.Config.RegistryConfig.RegistryPassword,
			// Edge Installer
			PaletteEdgeInstallerVersion: configValues.Config.EdgeInstaller.InstallerVersion,
			TenantRegistrationToken:     configValues.Config.EdgeInstaller.TenantRegistrationToken,
			ISOName:                     configValues.Config.EdgeInstaller.IsoImageName,
			// Cluster Profile
			CreateClusterProfile: configValues.Config.ClusterProfile.CreateClusterProfile,
			ClusterProfileSuffix: configValues.Config.ClusterProfile.Suffix,
			// Platform
			Platform: configValues.Config.Platform,
			// Custom Tag
			CustomTag: configValues.Config.CustomTag,
		}

		// Palette
		cliConfig = CliConfig{
			PaletteApiKey: &configValues.Config.Palette.ApiKey,
			ProjectID:     &configValues.Config.Palette.ProjectID,
			PaletteHost:   &configValues.Config.Palette.PaletteHost,
		}

	}

	return userSelections, cliConfig, nil

}

// This function reads a yaml input file and returns a list of Lambdas
func readConfigFileYaml(file string) (ConfigFile, error) {

	var c ConfigFile

	fileContent, err := os.ReadFile(file)
	if err != nil {
		return c, fmt.Errorf("unable to read the file %s", file)
	}

	err = yaml.Unmarshal(fileContent, &c)
	if err != nil {
		err = errors.New("unable to unmarshall the YAML file")
	}
	return c, err
}

// This function validates the existence of an input file and ensures its prefix is json | yaml | yml
func determineFileType(file string) (string, error) {
	f, err := os.Stat(file)
	var fileType string
	if err == nil {
		switch {
		case strings.HasSuffix(f.Name(), "yaml"):
			fileType = "yaml"

		case strings.HasSuffix(f.Name(), "yml"):
			fileType = "yaml"

		default:
			fileType = "none"
			err = errors.New("invalid file type provided. Must be of type json, yaml or yml")
		}
	}

	return fileType, err
}

// This function generates an example configuration file for the user to get started.
func GenerateExampleConfigFile() error {
	content := `
config:
  # The foundation software distributions and versions to use for the  Edge host
  # All the supported Kubernetes versions will be created by default.
  software:
    # Allowed values are: ubuntu, opensuse-leap 
    osDistro: ubuntu
    osVersion: 16.04
    # Allowed values are: k3s, rke2, kubeadm
    # kubeadm is the equivalent of Palette eXtended Kubernetes - Edge (PXK -E)
    kubernetesDistro: kubeadm
    containerNetworkInterface: calico
    containerNetworkInterfaceVersion: v0.12.5
  # The registry configuration values to use when uploading the provider images
  registryConfig:
	registryURL: myUsername/edge
	registryUsername: myUsername
    registryPassword: superSecretPassword
  # Palette credentials and project ID. If the project ID is not provided, then the default scope is Tenant.
  palette:
    apiKey: 1234567890
    projectID: 1234567890
	paletteHost: https://api.spectrocloud.com
  # The Edge Installer configuration values to use when creating the Edge Installer ISO
  edgeInstaller:
    tenantRegistrationToken: 1234567890
    installerVersion: 3.4.3
    isoImageName: palette-learn
  # The Cluster Profile configuration values to use when creating the Cluster Profile
  clusterProfile:
    createClusterProfile: true
    suffix: learn
  # Allowed values: linux/amd64
  platform: linux/amd64
  # The custom tag to apply to the provider images. 
  # The provider images name follow the format: <kubernetesDistro>-<k8sVersion>-v<installerVersion>-<customTag>_<platform>
  customTag: palette-learn`

	// Create a new file
	file, err := os.Create("config.yml")
	if err != nil {
		return fmt.Errorf("error creating file: %w", err)
	}
	defer file.Close()

	// Write content to file
	_, err = io.WriteString(file, content)
	if err != nil {
		return fmt.Errorf("error writing to file: %w", err)
	}

	// Save changes to disk
	if err := file.Sync(); err != nil {
		return fmt.Errorf("error saving file: %w", err)
	}

	return nil
}
