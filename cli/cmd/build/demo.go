package build

import (
	"context"

	"specrocloud.com/canvos/internal"
	log "specrocloud.com/canvos/logger"
	"specrocloud.com/canvos/prompts"
)

// Demo is the workflow orchestrator for the demo mode
func Demo(ctx context.Context, config *internal.CliConfig, options *internal.OptionsMenu) error {

	// Initialize the Palette Credentials
	// paletteAuth := internal.PaletteAuth{
	// 	Host:      *config.PaletteHost,
	// 	APIKey:    *config.PaletteApiKey,
	// 	ProjectID: *config.ProjectID,
	// }

	var userSelectedOptions internal.UserSelections

	tenantRegistrationToken, err := prompts.ReadText("Provide your Palette Tenant registration token", "", "A Palette Tenant registration token is required.", false, 128)
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("error getting API key. Exiting")
	}

	userSelectedOptions.TenantRegistrationToken = tenantRegistrationToken

	// Create the demo user data using the tenant registration token
	log.InfoCLI("Creating the Edge Installer User Data file....")
	err = internal.CreateDemoUserData(userSelectedOptions.TenantRegistrationToken)
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("Error creating the demo user data. Exiting")
	}

	userSelectedOptions.CustomTag = "palette-learn"

	latestUbuntuVersions := options.GetOperatingSystemVersionOptions("Ubuntu")

	userSelectedOptions.OperatingSystemDistro = "ubuntu"
	userSelectedOptions.OperatingSystemVersion = latestUbuntuVersions[0]

	latestK3sVersions := options.GetKubernetesDistroVersions("K3s")
	userSelectedOptions.KubernetesDistro = "k3s"
	userSelectedOptions.KubernetesVersion = latestK3sVersions[0]

	latestCalicoVersions := options.GetCniVersionOptions("Calico")
	userSelectedOptions.CNI = "calico"
	userSelectedOptions.CNIVersion = latestCalicoVersions[0]

	userSelectedOptions.PaletteEdgeInstallerVersion = options.PaletteVersions[0]
	userSelectedOptions.CreateClusterProfile = true

	userSelectedOptions.ClusterProfileSuffix = "demo"

	userSelectedOptions.ImageRegistryURL = "ttl.sh"
	userSelectedOptions.ImageRegistryRepository = "ubuntu"

	userSelectedOptions.ISOName = "palette-edge-installer"
	userSelectedOptions.Platform = "linux/amd64"

	ByoosVersions := options.GetBYOOSVersions()
	userSelectedOptions.BYOOSVersion = ByoosVersions[0]

	log.InfoCLI("Creating the .args file....")
	err = internal.CreateDemoArgsFile(userSelectedOptions)
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("Error creating the demo args file. Exiting")
	}

	log.InfoCLI("Starting the build process...")
	err = internal.StartBuildProcessScript(ctx, userSelectedOptions)
	if err != nil {
		log.Debug("err %s: ", err)
		log.FatalCLI("Error starting the build process script. Exiting")
	}

	// cp, err := internal.CreateEdgeClusterDemoProfilePayLoad(userSelectedOptions, options)
	// if err != nil {
	// 	log.Debug("err %s: ", err)
	// 	log.FatalCLI("Error creating the cluster profile payload. Exiting")
	// }

	// log.InfoCLI("Creating the cluster profile in Palette....")
	// cpId, err := internal.CreateClusterProfileInPalette(ctx, paletteAuth, cp)
	// if err != nil {sudo apt-get install terminator
	// 	log.InfoCLI("err %s: ", err)
	// 	log.FatalCLI("Error creating the cluster profile in Palette. Exiting")
	// }

	// log.InfoCLI("Publishing the cluster profile in Palette....")
	// err = internal.PublishClusterProfileInPalette(ctx, paletteAuth, cpId)
	// if err != nil {
	// 	log.InfoCLI("err %s: ", err)
	// 	log.FatalCLI("Error publishing the cluster profile in Palette. Exiting")
	// }

	return nil
}
