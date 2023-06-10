package cmd

import (
	"github.com/spf13/cobra"
	"golang.org/x/sync/errgroup"
	"specrocloud.com/canvos/internal"
	log "specrocloud.com/canvos/logger"
)

func init() {
	rootCmd.AddCommand(initCmd)

}

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize the CanvOS project and download all the required pack templates",
	Long:  `Initialize the CanvOS project and download all the required pack templates`,
	Run: func(cmd *cobra.Command, args []string) {
		ctx := cmd.Context()

		// Initialize the logger
		GlobalCliConfig.Verbose = &Verbose
		internal.InitLogger(Verbose)

		if *GlobalCliConfig.PaletteApiKey == "" {
			log.FatalCLI("Palette API Key is required. Please set the SPECTROCLOUD_APIKEY environment variable.")
		}

		// Initialize the Palette Credentials
		paletteAuth := internal.PaletteAuth{
			Host:      *GlobalCliConfig.PaletteHost,
			APIKey:    *GlobalCliConfig.PaletteApiKey,
			ProjectID: *GlobalCliConfig.ProjectID,
		}

		packsRequestFilters := map[string]string{
			"byoos":    "filters=spec.cloudTypes=edge-nativeANDspec.name=edge-native-byoi&limit=1&orderBy=spec.version=-1",
			"cnis":     "filters=spec.cloudTypes=edge-nativeANDspec.layer=cni&limit=50&orderBy=spec.version=-1",
			"k3s":      "filters=spec.cloudTypes=edge-nativeANDspec.layer=k8sANDspec.name=edge-k3s&limit=50&orderBy=spec.version=-1",
			"pxk-e":    "filters=spec.cloudTypes=edge-nativeANDspec.layer=k8sANDspec.name=edge-k8s&limit=50&orderBy=spec.version=-1",
			"rke2":     "filters=spec.cloudTypes=edge-nativeANDspec.layer=k8sANDspec.name=edge-rke2&limit=50&orderBy=spec.version=-1",
			"microk8s": "filters=spec.cloudTypes=edge-nativeANDspec.layer=k8sANDspec.name=edge-microk8s&limit=50&orderBy=spec.version=-1",
			"os":       "filters=spec.cloudTypes=edge-nativeANDspec.layer=os&limit=50&orderBy=spec.version=-1",
		}

		log.InfoCLI("Checking system specifications....")
		log.InfoCLI("")
		// Check the system specifications
		hostMachineProvider := &internal.HostSystemProvider{}
		internal.SystemPrerequisitesChecks(hostMachineProvider)

		// Create the CanvOS directory. If it already exists, it will be skipped
		err := internal.CreateCanvOsDir(internal.DefaultCanvOsDir)
		if err != nil {
			log.FatalCLI("Error creating the CanvOS directory")
			internal.LogError(err)
		}

		g, ctx := errgroup.WithContext(ctx)

		// Variable to store Pack request responses
		var responses = make(map[string]internal.Packs)
		log.InfoCLI("Downloading Pack templates....")
		// Make all Pack data requests concurrently
		for key, filter := range packsRequestFilters {
			k := key
			f := filter
			g.Go(func() error {
				var err error
				response, err := internal.GetPacks(ctx, paletteAuth, f)
				if err != nil {
					internal.LogError(err)
				} else {
					responses[k] = response
				}
				return err
			})
		}

		// Wait for all requests to finish
		if err := g.Wait(); err != nil {
			log.FatalCLI("Error retrieving the pack information from Palette")

		}
		log.InfoCLI("Downloads complete")

		// Use the responses map
		byoos := responses["byoos"]
		cnis := responses["cnis"]
		k3s := responses["k3s"]
		pxkE := responses["pxk-e"]
		rke2 := responses["rke2"]
		microk8s := responses["microk8s"]
		os := responses["os"]

		log.InfoCLI("Creating Pack templates....")
		packs := []internal.Packs{byoos, cnis, k3s, pxkE, rke2, microk8s, os}
		internal.RemoveDuplicatePacks(&packs)
		for _, pack := range packs {
			p := pack
			g.Go(func() error {
				err := internal.CreateTemplateFile(p)
				if err != nil {
					internal.LogError(err)
				}
				return err
			})
		}

		// Get the Palette Versions
		paletteVersions, err := internal.GetPaletteVersions(ctx, paletteAuth)
		if err != nil {
			internal.LogError(err)
			log.InfoCLI("Error retrieving the palette versions")

		}

		// Wait for all requests to finish
		if err := g.Wait(); err != nil {
			internal.LogError(err)
			log.FatalCLI("Error creating the pack templates")

		}
		log.InfoCLI("All Pack templates are created successfully")

		err = internal.CreateMenuOptionsFile(packs, paletteVersions)
		if err != nil {
			internal.LogError(err)
			log.FatalCLI("Error creating the menu options file.")

		}

		// The CanvOS repository is downloaded so that the user has the Eartly scripts and required assets.
		// The plan is to host this logic in the Palette CLI and not in the CanvOS repository.
		log.InfoCLI("Downloading CanvOS assets...")
		err = internal.CloneCanvOS(cmd.Context())
		if err != nil {
			log.FatalCLI("Error cloning the CanvOS repository.")
			internal.LogError(err)
		}
		log.InfoCLI("")
		log.InfoCLI("✅ Init downloaded all required assets successfully.")
		log.InfoCLI("")
		log.InfoCLI("")
		log.InfoCLI("--------------------------------------------------------------")
		log.InfoCLI("Use the the canvos build command to build the Edge Artifacts 💾 💿")

	},
}
