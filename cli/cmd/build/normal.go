package build

import (
	"context"
	"strings"

	"specrocloud.com/canvos/internal"
	log "specrocloud.com/canvos/logger"
	"specrocloud.com/canvos/prompts"
)

// Demo is the workflow orchestrator for the demo mode
func Normal(ctx context.Context, config *internal.CliConfig, options *internal.OptionsMenu) error {

	// Initialize the Palette Credentials
	// paletteAuth := internal.PaletteAuth{
	// 	Host:      *config.PaletteHost,
	// 	APIKey:    *config.PaletteApiKey,
	// 	ProjectID: *config.ProjectID,
	// }

	var (
		userSelectedOptions internal.UserSelections
		// clusterProfile      *internal.ClusterProfile
	)

	uVersion, err := prompts.Select("Select the Palette Edge Installer version", options.PaletteVersions, options.PaletteVersions[0], "A Palette Edge Installer version is required")
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error selecting the Palette Edge Installer version. Exiting")
	}
	userSelectedOptions.PaletteEdgeInstallerVersion = uVersion

	uOSDistro, err := prompts.Select("Select the Operating System (OS) Distribution", options.GetOperatingSystemDistroOptions(), options.GetOperatingSystemDistroOptions()[0], "An Operating System Distro is required")
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error selecting the OS distribution. Exiting")
	}
	userSelectedOptions.OperatingSystemDistro = strings.ToLower(uOSDistro)

	uOSVersion, err := prompts.Select("Select the Operating System (OS) Version", options.GetOperatingSystemVersionOptions(uOSDistro), options.GetOperatingSystemVersionOptions(uOSDistro)[0], "An Operating System Version is required")
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error selecting the OS version. Exiting")
	}
	userSelectedOptions.OperatingSystemVersion = uOSVersion

	uKubernetesDistro, err := prompts.Select("Select the Kubernetes Distro", options.GetKubernetesDistroOptions(), options.GetKubernetesDistroOptions()[0], "A Kubernetes Distro is required")
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error selecting the Kubernetes Distro. Exiting")
	}

	userSelectedOptions.KubernetesDistro, err = internal.GetKubernetesDistroPaletteValue(uKubernetesDistro)
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error getting the Kubernetes Distro. Exiting")
	}

	uRegistryRaw, err := prompts.ReadTextRegex("Provide your Container Registry URL + Namespace - Example: dockerhub.com/canvos", "", "A Container Registry URL is required.  Example: dockerhub.com/canvos", `^[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$`)
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error getting Container Registry URL. Exiting")
	}

	uRegistry := strings.Split(uRegistryRaw, "/")
	if len(uRegistry) != 2 {
		log.FatalCLI("error getting Container Registry URL. Exiting")
	}

	userSelectedOptions.ImageRegistryURL = uRegistry[0]
	userSelectedOptions.ImageRegistryRepository = uRegistry[1]

	registryAuth := &internal.RegistryAuthConfig{}
	registryAuth.Username, err = prompts.ReadText("Provide your Container Registry Username", "", "A Container Registry Username is required.", false, 128)
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error getting Container Registry Username. Exiting")
	}
	registryAuth.Password, err = prompts.ReadPassword("Provide your Container Registry Password", "", "A Container Registry Password is required.", false, 128)
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error getting Container Registry Password. Exiting")
	}
	userSelectedOptions.ImageRegistryPassword = registryAuth.Password

	uCustomTag, err := prompts.ReadText("Specify the custom image tag you want applied to all provider images", "", "A Custom Tag is required.", false, 128)
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error getting Custom Tag. Exiting")
	}
	userSelectedOptions.CustomTag = uCustomTag

	uClusterProfileChoice, err := prompts.Select("Would you like a cluster profile created in Palette", []string{"Yes", "No"}, "Yes", "You must selecte an option. Either Yes or No")
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error getting Custom Tag. Exiting")
	}

	if uClusterProfileChoice == "No" {
		userSelectedOptions.CreateClusterProfile = false
	}
	if uClusterProfileChoice == "Yes" {
		userSelectedOptions.CreateClusterProfile = true
	}

	// The logic for if the user wants a cluster profile created
	if userSelectedOptions.CreateClusterProfile {

		uCNI, err := prompts.Select("Select the Container Network Interface (CNI)", options.GetCniOptions(), options.GetCniOptions()[0], "A Container Network Interface (CNI) is required")
		if err != nil {
			log.Debug("err %s: ", err)
			log.FatalCLI("error selecting the Container Network Interface (CNI). Exiting")
		}
		userSelectedOptions.CNI = uCNI

		uCNIVersion, err := prompts.Select("Select the Container Network Interface (CNI) Version", options.GetCniVersionOptions(uCNI), options.GetCniVersionOptions(uCNI)[0], "A Container Network Interface (CNI) Version is required")
		if err != nil {
			log.Debug("err %s: ", err)
			log.FatalCLI("error selecting the Container Network Interface (CNI) Version. Exiting")
		}
		userSelectedOptions.CNIVersion = uCNIVersion

		uImageSuffix, err := prompts.ReadText("Provide your image name suffix. The default cluster profile name is edge-<suffix>-<YYYY-MM-DD>-<SHA-256>", "", "An Image suffix is required.", false, 12)
		if err != nil {
			log.Debug("err %s: ", err)
			log.FatalCLI("error getting Image suffix. Exiting")
		}
		userSelectedOptions.ClusterProfileSuffix = uImageSuffix
		// cp, err := internal.CreateEdgeClusterDemoProfilePayLoad(*userSelectedOptions, options)
		// if err != nil {
		// 	log.Debug("err %s: ", err)
		// 	log.FatalCLI("Error creating the cluster profile payload. Exiting")
		// }
		// log.InfoCLI("Creating the cluster profile in Palette....")
		// cpId, err := internal.CreateClusterProfileInPalette(ctx, paletteAuth, cp)
		// if err != nil {
		// 	log.InfoCLI("err %s: ", err)
		// 	log.FatalCLI("Error creating the cluster profile in Palette. Exiting")
		// }

		// log.InfoCLI("Publishing the cluster profile in Palette....")
		// err = internal.PublishClusterProfileInPalette(ctx, paletteAuth, cpId)
		// if err != nil {
		// 	log.InfoCLI("err %s: ", err)
		// 	log.FatalCLI("Error publishing the cluster profile in Palette. Exiting")
		// }

	}

	uConfirmUserData, err := prompts.Select("Confirm you reviewed and updated the user-data file in the local directory with the required Edge Installer configurations", []string{"Yes", "No"}, "Yes", "You must selecte an option. Either Yes or No")
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error getting Custom Tag. Exiting")
	}
	if uConfirmUserData == "No" {
		log.FatalCLI("You must review the user-data file. Use the user-data file in the root directory and update it with valid Edge Installer configuration values. Exiting")

	}
	uConfirmDockerFile, err := prompts.Select("Confirm you reviewed and updated the Dockerfile file in the local directory with the required additional software packages and dependencies", []string{"Yes", "No"}, "Yes", "You must selecte an option. Either Yes or No")
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error getting Custom Tag. Exiting")
	}
	if uConfirmDockerFile == "No" {
		log.FatalCLI("You must review the Dockerfile is in the local directory. Use the Dockerfile in the local directory and update it with valid additional software packages and dependencies if needed. Exiting")

	}

	// Assumptions section: customize as we learn more about the user beahvior usage
	userSelectedOptions.ISOName = "palette-edge-installer"
	userSelectedOptions.Platform = "linux/amd64"

	// Create the .arg file
	log.InfoCLI("Creating the .args file....")
	err = internal.CreateArgsFile(userSelectedOptions)
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("Error creating the demo args file. Exiting")
	}

	log.InfoCLI("Starting the build process...")

	return nil
}
