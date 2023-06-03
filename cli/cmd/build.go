package cmd

import (
	"github.com/pterm/pterm"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(buildCmd)
}

var buildCmd = &cobra.Command{
	Use:   "build",
	Short: "Build the Edge Artifacts",
	Long:  `Build the Edge Artifacts`,
	Run: func(cmd *cobra.Command, args []string) {
		var operatingSystems []string = []string{
			"Ubuntu",
			"Suse",
		}

		var operatingSystems2 []string = []string{
			"22.04",
			"20.04",
		}

		var kubernetesDistro []string = []string{
			"Palette eXtended Kubernetes - Edge (PXK-E)",
			"K3s",
			"RKE2",
			"MicroK8s",
		}

		paletteAPI, _ := pterm.DefaultInteractiveTextInput.Show("Provide your Palette API key")
		pterm.Println() // Blank line
		pterm.Info.Printfln("You answered: %s", paletteAPI)

		registry, _ := pterm.DefaultInteractiveTextInput.Show("Provide the image registry (Default: ttl.sh). Press Enter to use default")
		pterm.Println("Press Enter to Continue") // Blank line
		pterm.Println()                          // Blank line
		if registry == "" {
			registry = "ttl.sh"
		}
		pterm.Info.Printfln("You answered: %s", registry)

		printer := pterm.DefaultInteractiveSelect.WithOptions(operatingSystems).WithDefaultOption(operatingSystems[0])
		selectedoperatingSystems, _ := printer.Show("Select the OS you want to use. (Default: Ubuntu). Press Enter to use default")
		pterm.Info.Printfln("Selected OS: %s", pterm.Green(selectedoperatingSystems))

		printer2 := pterm.DefaultInteractiveSelect.WithOptions(operatingSystems2).WithDefaultOption(operatingSystems[0])
		selectedoperatingSystems2, _ := printer2.Show("Select the OS version you want to use")
		pterm.Info.Printfln("Selected OS: %s", pterm.Green(selectedoperatingSystems2))

		printer3 := pterm.DefaultInteractiveSelect.WithOptions(kubernetesDistro).WithDefaultOption(kubernetesDistro[0])
		selectedoperatingSystems3, _ := printer3.Show("Select the Kubernetes distribution you want to use. (Default: Palette eXtended Kubernetes - Edge (PXK-E)). Press Enter to use default")
		pterm.Info.Printfln("Selected Kubernetes Distribution: %s", pterm.Green(selectedoperatingSystems3))

		pterm.Println() // Blank line
		pterm.Println() // Blank line

		pterm.DefaultSection.Println("Summary")
		pterm.DefaultSection.Println("-------")
		pterm.DefaultSection.Println("Palette API Key: ", paletteAPI)
		pterm.DefaultSection.Println("Image Registry: ", registry)
		pterm.DefaultSection.Println("Operating System: ", selectedoperatingSystems)
		pterm.DefaultSection.Println("Operating System Version: ", selectedoperatingSystems2)
		pterm.DefaultSection.Println("Kubernetes Distribution: ", selectedoperatingSystems3)
		pterm.Println() // Blank line
		pterm.Println() // Blank line
	},
}
