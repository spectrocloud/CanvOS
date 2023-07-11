package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
	"specrocloud.com/canvos/internal"
	log "specrocloud.com/canvos/logger"
)

func init() {
	rootCmd.AddCommand(versionCmd)
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print the current version number of CanvOS",
	Long:  `Prints the current version number of CanvOS`,
	Run: func(cmd *cobra.Command, args []string) {
		version := fmt.Sprintf("canvos v%s", internal.Version)
		log.InfoCLI(version)
	},
}