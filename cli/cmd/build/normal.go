package build

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"specrocloud.com/canvos/internal"
	log "specrocloud.com/canvos/logger"
	"specrocloud.com/canvos/prompts"
)

// Demo is the workflow orchestrator for the demo mode
func Normal(ctx context.Context, config *internal.CliConfig, options *internal.OptionsMenu) error {

	// Initialize the Palette Credentials
	paletteAuth := internal.PaletteAuth{
		Host:      *config.PaletteHost,
		APIKey:    *config.PaletteApiKey,
		ProjectID: *config.ProjectID,
	}

	var (
		userSelectedOptions internal.UserSelections
		finalMsg            string = "Go ahead and prepare your Edge host using the ISO image created in the build/ folder"
	)

	uVersion, err := prompts.Select("Select the Palette Edge Installer version", options.PaletteVersions, options.PaletteVersions[0], "A Palette Edge Installer version is required")
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("error selecting the Palette Edge Installer version. Exiting")
	}
	userSelectedOptions.PaletteEdgeInstallerVersion = uVersion

	// Get all the OS Choices
	osChoices := []prompts.ChoiceItem{}
	for _, o := range options.GetOperatingSystemDistroOptions() {

		if o == "opensuse" {
			o = "opensuse-leap"
		}

		osChoices = append(osChoices, prompts.ChoiceItem{
			Name: o,
			ID:   o,
		})
	}

	uOSDistro, err := prompts.SelectID("Select the Operating System (OS) Distribution", osChoices, "ubuntu", "An Operating System Distro is required")
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("error selecting the OS distribution. Exiting")
	}
	userSelectedOptions.OperatingSystemDistro = uOSDistro.ID

	uOSVersion, err := prompts.Select("Select the Operating System (OS) Version", options.GetOperatingSystemVersionOptions(userSelectedOptions.OperatingSystemDistro), options.GetOperatingSystemVersionOptions(userSelectedOptions.OperatingSystemDistro)[0], "An Operating System Version is required")
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("error selecting the OS version. Exiting")
	}
	userSelectedOptions.OperatingSystemVersion = uOSVersion

	uKubernetesDistro, err := prompts.Select("Select the Kubernetes Distro", options.GetKubernetesDistroOptions(), options.GetKubernetesDistroOptions()[0], "A Kubernetes Distro is required")
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("error selecting the Kubernetes Distro. Exiting")
	}

	userSelectedOptions.KubernetesDistro, err = internal.GetKubernetesDistroPaletteValue(uKubernetesDistro)
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("error getting the Kubernetes Distro. Exiting")
	}

	uRegistryRaw, err := prompts.ReadTextRegex("Provide your Container Registry URL + Namespace - Example: dockerhub.com/canvos", "", "A Container Registry URL is required.  Example: dockerhub.com/canvos", `^([a-zA-Z0-9\-\._]+)(\/([a-zA-Z0-9\-\._]+))?(\/([a-zA-Z0-9\-\._]+))?$`)
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("error getting Container Registry URL. Exiting")
	}

	uRegistry := strings.Split(uRegistryRaw, "/")
	if len(uRegistry) != 2 {
		log.FatalCLI("error getting Container Registry URL. Exiting")
	}

	userSelectedOptions.ImageRegistryURL = uRegistry[0]
	userSelectedOptions.ImageRegistryRepository = uRegistry[1]

	registryAuth := &internal.RegistryAuthConfig{}
	registryAuth.Username, err = prompts.ReadText("Provide your Container Registry Username", "", "A Container Registry Username is required.", true, 128)
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("error getting Container Registry Username. Exiting")
	}
	registryAuth.Password, err = prompts.ReadPassword("Provide your Container Registry Password", "", "A Container Registry Password is required.", true, 128)
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("error getting Container Registry Password. Exiting")
	}
	userSelectedOptions.ImageRegistryPassword = registryAuth.Password

	uCustomTag, err := prompts.ReadText("Specify the custom image tag you want applied to all provider images", "", "A Custom Tag is required.", false, 128)
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("error getting Custom Tag. Exiting")
	}
	userSelectedOptions.CustomTag = uCustomTag

	uClusterProfileChoice, err := prompts.Select("Would you like a cluster profile created in Palette", []string{"Yes", "No"}, "Yes", "You must selecte an option. Either Yes or No")
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("error getting Custom Tag. Exiting")
	}

	if uClusterProfileChoice == "No" {
		userSelectedOptions.CreateClusterProfile = false
	}
	if uClusterProfileChoice == "Yes" {
		userSelectedOptions.CreateClusterProfile = true
	}
	ByoosVersions := options.GetBYOOSVersions()
	userSelectedOptions.BYOOSVersion = ByoosVersions[0]

	userSelectedOptions.KubernetesVersion = options.GetKubernetesDistroVersions(userSelectedOptions.KubernetesDistro)[0]

	// The logic for if the user wants a cluster profile created
	if userSelectedOptions.CreateClusterProfile {

		uCNI, err := prompts.Select("Select the Container Network Interface (CNI)", options.GetCniOptions(), options.GetCniOptions()[0], "A Container Network Interface (CNI) is required")
		if err != nil {
			log.Debug(internal.LogError(err))
			log.FatalCLI("error selecting the Container Network Interface (CNI). Exiting")
		}
		userSelectedOptions.CNI = uCNI

		uCNIVersion, err := prompts.Select("Select the Container Network Interface (CNI) Version", options.GetCniVersionOptions(uCNI), options.GetCniVersionOptions(uCNI)[0], "A Container Network Interface (CNI) Version is required")
		if err != nil {
			log.Debug(internal.LogError(err))
			log.FatalCLI("error selecting the Container Network Interface (CNI) Version. Exiting")
		}
		userSelectedOptions.CNIVersion = uCNIVersion

		uImageSuffix, err := prompts.ReadText("Provide the cluster profile image name suffix. The default cluster profile name is edge-<suffix>-<YYYY-MM-DD>-<SHA-256>", "", "An Image suffix is required.", false, 12)
		if err != nil {
			log.Debug(internal.LogError(err))
			log.FatalCLI("error getting Image suffix. Exiting")
		}
		userSelectedOptions.ClusterProfileSuffix = uImageSuffix

	}

	uConfirmUserData, err := prompts.Select("Confirm you reviewed and updated the user-data file in the local directory with the required Edge Installer configurations", []string{"Yes", "No"}, "Yes", "You must selecte an option. Either Yes or No")
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("error getting Custom Tag. Exiting")
	}
	if uConfirmUserData == "No" {
		log.FatalCLI("You must review the user-data file. Use the user-data file in the root directory and update it with valid Edge Installer configuration values. Exiting")

	}
	uConfirmDockerFile, err := prompts.Select("Confirm you reviewed and updated the Dockerfile file in the local directory with the required additional software packages and dependencies", []string{"Yes", "No"}, "Yes", "You must selecte an option. Either Yes or No")
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("error getting Custom Tag. Exiting")
	}
	if uConfirmDockerFile == "No" {
		log.FatalCLI("You must review the Dockerfile is in the local directory. Use the Dockerfile in the local directory and update it with valid additional software packages and dependencies if needed. Exiting")

	}

	// Assumptions section: customize as we learn more about the user behavior usage
	userSelectedOptions.ISOName = "palette-edge-installer"
	userSelectedOptions.Platform = "linux/amd64"

	// Create the .arg file
	log.InfoCLI("Creating the .args file....")
	err = internal.CreateArgsFile("", userSelectedOptions)
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("Error creating the demo args file. Exiting")
	}

	// Copy the content folder to the .canvos folder so it's available for Earthly
	conteFolder, err := internal.GetContentDir()
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			log.InfoCLI("no content folder found. Continuing...")
		} else {
			log.Debug(internal.LogError(err))
			log.FatalCLI("Error getting the content folder. Exiting")
		}
	}
	buildContentDstFolder := filepath.Join(internal.DefaultCanvOsDir, "canvOS", conteFolder)
	if buildContentDstFolder != "" {
		err = internal.MoveContentFolder(conteFolder, buildContentDstFolder)
		if err != nil {
			log.Debug(internal.LogError(err))
			log.FatalCLI("Error copying the build folder. Error %v", err.Error())
		}
	}

	log.InfoCLI("Starting the build process...")
	err = internal.StartBuildProcessScript(ctx, userSelectedOptions)
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("Error starting the build process script. Exiting")
	}

	sourceBuildFolder := filepath.Join(internal.DefaultCanvOsDir, "canvOS", "build")

	destinationFolder, err := os.Getwd()
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("Error getting the current working directory. Exiting")
	}
	destinationFolder = filepath.Join(destinationFolder, "build")
	// Copy the build folder to root
	err = internal.CopyDirectory(sourceBuildFolder, destinationFolder)
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("Error copying the build folder to root. Exiting")
	}

	encodedRegistryCredentials, err := registryAuth.GetEncodedAuth()
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("Error getting the registry credentials. Exiting")
	}

	dockerClient, err := internal.NewDockerClient()
	if err != nil {
		log.Debug(internal.LogError(err))
		log.FatalCLI("Error creating the docker client. Exiting")
	}

	// Push the provider images to the registry
	log.InfoCLI("Pushing the provider images to the registry....")
	err = internal.PushProviderImages(ctx, dockerClient, encodedRegistryCredentials, userSelectedOptions)
	if err != nil {
		log.Debug(internal.LogError(err))
		errMsg := fmt.Sprintf("Error pushing the provider images. %s", err.Error())
		log.FatalCLI(errMsg)
	}

	if userSelectedOptions.CreateClusterProfile {
		cp, err := internal.CreateEdgeClusterProfilePayLoad(userSelectedOptions, options)
		if err != nil {
			log.Debug(internal.LogError(err))
			log.FatalCLI("Error creating the cluster profile payload. Exiting")
		}

		log.InfoCLI("Creating the cluster profile in Palette....")
		cpId, err := internal.CreateClusterProfileInPalette(ctx, paletteAuth, cp)
		if err != nil {
			log.InfoCLI("err %s: ", err)
			log.FatalCLI("Error creating the cluster profile in Palette. Exiting")
		}

		log.InfoCLI("Publishing the cluster profile in Palette....")
		err = internal.PublishClusterProfileInPalette(ctx, paletteAuth, cpId)
		if err != nil {
			log.InfoCLI("err %s: ", err)
			log.FatalCLI("Error publishing the cluster profile in Palette. Exiting")
		}
		log.InfoCLI("Creating the cluster profile in Palette....")
		finalMsg = fmt.Sprintf("Go ahead and prepare your Edge host using the ISO image created in the build/ folder and use the cluster profile %s created in Palette.", cp.Metadata.Name)

	}
	log.InfoCLI("")
	log.InfoCLI("")
	log.InfoCLI("🚀 Edge artifacts built successfully.")
	log.InfoCLI(finalMsg)

	return nil
}
