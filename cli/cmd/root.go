package cmd

import (
	"os"

	"github.com/spf13/cobra"
	"specrocloud.com/canvos/internal"
)

var (
	// Verbose is to enable debug output
	Verbose string = "INFO"
	// GlobalCliConfig is the global CLI config
	GlobalCliConfig internal.CliConfig
	// ConfigFile is the path to the config file
	ConfigFile string
	// GenerateExampleConfig is to generate an example config file
	GenerateExampleConfig bool
)

var rootCmd = &cobra.Command{
	Use:   "canvos",
	Short: "A utility for creating Edge Artifacts with CanvOS",
	Long:  `A utility for creating Edge Artifacts with CanvOS`,
	Run: func(cmd *cobra.Command, args []string) {
		err := cmd.Help()
		if err != nil {
			internal.LogError(err)
			os.Exit(1)
		}
	},
}

func init() {

	// Environment variables
	apiKey := internal.Getenv("SPECTROCLOUD_APIKEY", "")
	PaletteEndpoint := internal.Getenv("PALETTE_HOST", "https://api.spectrocloud.com")
	ProjectID := internal.Getenv("PALETTE_PROJECT_ID", "")

	// Global CLI config
	GlobalCliConfig.PaletteApiKey = &apiKey
	GlobalCliConfig.PaletteHost = &PaletteEndpoint
	GlobalCliConfig.ProjectID = &ProjectID
	GlobalCliConfig.ConfigFile = &ConfigFile

	rootCmd.PersistentFlags().StringVarP(&Verbose, "verbose", "v", "INFO", "Set the debugging mode (DEBUG, INFO, WARN, ERROR, FATAL)")
	rootCmd.PersistentFlags().StringVarP(&ConfigFile, "config", "c", "", "Specify the path to a config file")
	GlobalCliConfig.Verbose = &Verbose
	GlobalCliConfig.ConfigFile = &ConfigFile

}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		internal.LogError(err)
		os.Exit(1)
	}
}
