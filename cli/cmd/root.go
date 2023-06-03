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

	apiKey := internal.Getenv("SPECTROCLOUD_APIKEY", "")
	PaletteEndpoint := internal.Getenv("PALETTE_HOST", "https://api.spectrocloud.com")
	ProjectID := internal.Getenv("PALETTE_PROJECT_ID", "")
	GlobalCliConfig.PaletteApiKey = &apiKey
	GlobalCliConfig.PaletteHost = &PaletteEndpoint
	GlobalCliConfig.ProjectID = &ProjectID

	rootCmd.PersistentFlags().StringVarP(&Verbose, "verbose", "v", "INFO", "Set the debugging mode (DEBUG, INFO, WARN, ERROR, FATAL)")
	GlobalCliConfig.Verbose = &Verbose
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		internal.LogError(err)
		os.Exit(1)
	}
}
