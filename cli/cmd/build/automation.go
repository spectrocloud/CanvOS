package build

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"specrocloud.com/canvos/internal"
	log "specrocloud.com/canvos/logger"
)

func Automation(ctx context.Context, userSelectedOptions *internal.UserSelections, config *internal.CliConfig, options *internal.OptionsMenu) error {

	var (
		finalMsg string
	)

	// Initialize the Palette Credentials
	paletteAuth := internal.PaletteAuth{
		Host:      *config.PaletteHost,
		APIKey:    *config.PaletteApiKey,
		ProjectID: *config.ProjectID,
	}

	// Initialize the Registry Credentials
	registryAuth := &internal.RegistryAuthConfig{
		Username: userSelectedOptions.ImageRegistryUsername,
		Password: userSelectedOptions.ImageRegistryPassword,
	}

	// Set the latest version of the BYOOS pack
	ByoosVersions := options.GetBYOOSVersions()
	userSelectedOptions.BYOOSVersion = ByoosVersions[0]

	// Get Kubernetes versions
	userSelectedOptions.KubernetesVersion = options.GetKubernetesDistroVersions(userSelectedOptions.KubernetesDistro)[0]

	// Create the .arg file
	log.InfoCLI("Creating the .args file....")
	err := internal.CreateArgsFile("", *userSelectedOptions)
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
	log.InfoCLI("Folder to copy: %s", conteFolder)
	buildContentDstFolder := filepath.Join(internal.DefaultCanvOsDir, "canvOS", conteFolder)
	if buildContentDstFolder != "" {
		err = internal.MoveContentFolder(conteFolder, buildContentDstFolder)
		if err != nil {
			log.Debug(internal.LogError(err))
			log.FatalCLI("Error copying the build folder - Error: %s", err.Error())
		}
	}

	log.InfoCLI("Starting the build process...")
	err = internal.StartBuildProcessScript(ctx, *userSelectedOptions)
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
	err = internal.PushProviderImages(ctx, dockerClient, encodedRegistryCredentials, *userSelectedOptions)
	if err != nil {
		log.Debug(internal.LogError(err))
		errMsg := fmt.Sprintf("Error pushing the provider images. %s", err.Error())
		log.FatalCLI(errMsg)
	}

	if userSelectedOptions.CreateClusterProfile {
		cp, err := internal.CreateEdgeClusterProfilePayLoad(*userSelectedOptions, options)
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
		finalMsg = fmt.Sprintf("Go ahead and prepare your Edge host using the ISO image created in the build/ folder and use the cluster profile %s created in Palette.", cp.Metadata.Name)
	}

	log.InfoCLI("")
	log.InfoCLI("")
	log.InfoCLI("🚀 Edge artifacts built successfully.")
	log.InfoCLI(finalMsg)

	return nil

}
