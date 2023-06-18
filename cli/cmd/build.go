package cmd

import (
	"os"

	"github.com/spf13/cobra"
	"specrocloud.com/canvos/cmd/build"
	"specrocloud.com/canvos/internal"
	log "specrocloud.com/canvos/logger"
	"specrocloud.com/canvos/prompts"
)

func init() {
	rootCmd.AddCommand(buildCmd)
}

var buildCmd = &cobra.Command{
	Use:   "build",
	Short: "Build the Edge Artifacts",
	Long:  `Build the Edge Artifacts`,
	Run: func(cmd *cobra.Command, args []string) {

		ctx := cmd.Context()

		// Initialize the logger
		GlobalCliConfig.Verbose = &Verbose
		internal.InitLogger(Verbose)

		// Check if the CanvOS directory and options file exist
		checkIfCanvOSDirExists()
		// Create the user selections struct that will be used to store the user selections
		var userSelectedOptions internal.UserSelections

		options, err := internal.ReadOptionsFile(internal.DefaultCliMenuOptionsPath)
		if err != nil {
			log.Debug("err %s: ", err)
			log.FatalCLI("Error reading the CanvOS options file")

		}

		// Check if the user has provided a Palette API Key
		// If not, prompt the user to enter the API Key
		if *GlobalCliConfig.PaletteApiKey == "" {

			apiKey, err := prompts.ReadText("Enter your Palette API Key", "", "Palette API Key is required", false, 128)
			if err != nil {
				log.Debug("err %s: ", err)
				log.FatalCLI("error getting API key. Exiting")
			}
			GlobalCliConfig.PaletteApiKey = &apiKey

		}

		if *GlobalCliConfig.ProjectID == "" {

			projectId, err := prompts.ReadText("Enter your Palette Project ID. Or press Enter to leave empty and use the Tenant instead of a project", "", "Palette API Key is required", true, 128)
			if err != nil {
				log.Debug("err %s: ", err)
				log.FatalCLI("error getting API key. Exiting")
			}
			GlobalCliConfig.ProjectID = &projectId

		}

		workflowModes := []prompts.ChoiceItem{
			{
				ID:   "Normal",
				Name: "Normal - Intended for production deployments.",
			},
			{
				ID:   "Demo",
				Name: "Demo - Intended for learning purposes and demonstrations.",
			},
		}
		// Automation Mode
		if *GlobalCliConfig.ConfigFile != "" {

			// check the config file exists
			if _, err := os.Stat(*GlobalCliConfig.ConfigFile); os.IsNotExist(err) {
				log.FatalCLI("Config file does not exist or the file path is incorrect. Exiting")
			}

			log.InfoCLI("Config file found. Starting in automation mode")

		}

		if *GlobalCliConfig.ConfigFile == "" {

			// User selects the workflow mode
			wizardMode, err := prompts.SelectID("Select the workflow mode", workflowModes, workflowModes[1].ID, "A workflow mode is required")
			if err != nil {
				log.Debug("err %s: ", err)
				log.FatalCLI("Error selecting the workflow mode. Exiting")
			}

			userSelectedOptions.Mode = internal.GetWizardModeFromStr(wizardMode.ID)

			// This transitions the program logic to the respective workflow mode's entry point
			switch userSelectedOptions.Mode {
			case 0:
				log.Debug("Demo Mode")
				err := build.Demo(ctx, &GlobalCliConfig, options)
				if err != nil {
					log.Debug("err %s: ", err)
					log.FatalCLI("Error running the demo workflow. Exiting")
				}

			case 1:
				log.Debug("Normal Mode")
				err := build.Normal(ctx, &GlobalCliConfig, options)
				if err != nil {
					log.Debug("err %s: ", err)
					log.FatalCLI("Error running the normal workflow. Exiting")
				}
			default:
				log.Debug("Invalid workflow mode")
				log.FatalCLI("Invalid workflow mode. Exiting")

			}

		}

	},
}

// checkIfCanvOSDirExists checks if the .canvos directory exists in the local directory.
// If it does not exist, the program exits with an error message.
func checkIfCanvOSDirExists() {

	if _, err := os.Stat(internal.DefaultCanvOsDir); os.IsNotExist(err) {
		log.Error("error %s", err)
		internal.LogError(err)
		log.FatalCLI("CanvOS directory does not exist. Please issue the canvos init command to create the .canvos directory")
	}

	if _, err := os.Stat(internal.DefaultCliMenuOptionsPath); os.IsNotExist(err) {
		log.Error("error %s", err)
		internal.LogError(err)
		log.FatalCLI("CanvOS options file does not exist. Please issue the canvos init command to create the options.json file")
	}
}
