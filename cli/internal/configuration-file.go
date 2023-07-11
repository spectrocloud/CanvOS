package internal

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/go-playground/validator/v10"
	log "specrocloud.com/canvos/logger"

	"gopkg.in/yaml.v3"
)

// GetUserVaues reads the input file and returns a UserSelections struct
func GetUserVaues(ctx context.Context, file string) (UserSelections, CliConfig, error) {

	var (
		userSelections    UserSelections
		cliConfig         CliConfig
		configValues      ConfigFile
		registry          string
		registryNamespace []string
	)

	fileType, err := determineFileType(ctx, file)
	if err != nil {
		log.Debug(LogError(err))
		return userSelections, cliConfig, err
	}

	if err == nil && fileType == "yaml" {
		configValues, err = readConfigFileYaml(ctx, file)
		if err != nil {
			log.Debug(LogError(err))
			return userSelections, cliConfig, err
		}

		// Split the registry URL to get the registry and namespace/repository
		if *configValues.Config.RegistryConfig.RegistryURL != "" {
			registry = strings.Split(*configValues.Config.RegistryConfig.RegistryURL, "/")[0]
			registryNamespace = strings.Split(*configValues.Config.RegistryConfig.RegistryURL, "/")[1:]
		}

		userSelections = UserSelections{
			// Sofware
			OperatingSystemDistro:  *configValues.Config.Software.OsDistro,
			OperatingSystemVersion: *configValues.Config.Software.OsVersion,
			KubernetesDistro:       *configValues.Config.Software.KubernetesDistro,
			CNI:                    *configValues.Config.Software.ContainerNetworkInterface,
			CNIVersion:             *configValues.Config.Software.ContainerNetworkInterfaceVersion,
			// Registry
			ImageRegistryURL:        registry,
			ImageRegistryRepository: registryNamespace[0],
			ImageRegistryUsername:   *configValues.Config.RegistryConfig.RegistryUsername,
			ImageRegistryPassword:   *configValues.Config.RegistryConfig.RegistryPassword,
			// Edge Installer
			PaletteEdgeInstallerVersion: *configValues.Config.EdgeInstaller.InstallerVersion,
			TenantRegistrationToken:     *configValues.Config.EdgeInstaller.TenantRegistrationToken,
			ISOName:                     *configValues.Config.EdgeInstaller.IsoImageName,
			// Cluster Profile
			CreateClusterProfile: *configValues.Config.ClusterProfile.CreateClusterProfile,
			ClusterProfileSuffix: *configValues.Config.ClusterProfile.Suffix,
			// Platform
			Platform: *configValues.Config.Platform,
			// Custom Tag
			CustomTag: *configValues.Config.CustomTag,
		}

		// Palette
		cliConfig = CliConfig{
			PaletteApiKey: configValues.Config.Palette.ApiKey,
			ProjectID:     configValues.Config.Palette.ProjectID,
			PaletteHost:   configValues.Config.Palette.PaletteHost,
			CanvosVersion: configValues.Config.CanvosVersion,
		}

	}

	return userSelections, cliConfig, nil

}

// This function reads a yaml input file and returns a list of Lambdas
func readConfigFileYaml(ctx context.Context, file string) (ConfigFile, error) {

	var c ConfigFile

	fileContent, err := os.ReadFile(file)
	if err != nil {
		log.Debug(LogError(err))
		return c, fmt.Errorf("unable to read the file %s", file)
	}

	err = yaml.Unmarshal(fileContent, &c)
	if err != nil {
		log.Debug(LogError(err))
		return c, errors.New("unable to unmarshall the YAML file")
	}

	err = c.Validate()
	if err != nil {
		log.Debug(LogError(err))
		return c, err
	}

	// Validate the configuration file
	v := validator.New()
	err = v.Struct(c)
	if err != nil {
		log.Debug(LogError(err))
		return c, fmt.Errorf("invalid configuration file: %s", err.(validator.ValidationErrors))
	}
	return c, err
}

// This function validates the existence of an input file and ensures its prefix is json | yaml | yml
func determineFileType(ctx context.Context, file string) (string, error) {
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
func GenerateExampleConfigFile(ctx context.Context) error {
	content := `
config:
  # The foundation software distributions and versions to use for the  Edge host
  # All the supported Kubernetes versions will be created by default.
  software:
    # Allowed values are: ubuntu, opensuse-leap 
    osDistro: ubuntu
    osVersion: 22.04
    # Allowed values are: k3s, rke2, kubeadm
    # kubeadm is the equivalent of Palette eXtended Kubernetes - Edge (PXK -E)
    kubernetesDistro: kubeadm
    # Choose a Container Network Interface (CNI) available in Palette.
    containerNetworkInterface: calico
    # Choose a Container Network Interface (CNI) version available in Palette.
    containerNetworkInterfaceVersion: 3.25.0
  # The registry configuration values to use when uploading the provider images
  registryConfig:
    registryURL: myUsername/myrepository
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
    # The suffix is part of the cluster profile name. The name format is: edge-<suffix>-<YYYY-MM-DD>-<SHA-256>
    suffix: learn
  # Allowed values: linux/amd64
  platform: linux/amd64
  # The custom tag to apply to the provider images. 
  # The provider images name follow the format: <kubernetesDistro>-<k8sVersion>-v<installerVersion>-<customTag>_<platform>
  customTag: palette-learn
  # The Canvos version to use for the Edge Installer ISO
  canvosVersion: 3.4.3
  `

	// Create a new file
	file, err := os.Create("config.yml")
	if err != nil {
		log.Debug(LogError(err))
		return fmt.Errorf("error creating file: %w", err)
	}
	defer file.Close()

	// Write content to file
	_, err = io.WriteString(file, content)
	if err != nil {
		log.Debug(LogError(err))
		return fmt.Errorf("error writing to file: %w", err)
	}

	// Save changes to disk
	if err := file.Sync(); err != nil {
		log.Debug(LogError(err))
		return fmt.Errorf("error saving file: %w", err)
	}

	return nil
}
