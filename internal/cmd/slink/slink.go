package main

import (
	"os"
	"path/filepath"

	"github.com/sirupsen/logrus"
	"github.com/spectrocloud/CanvOS/internal/pkg/utils"
	"github.com/spf13/cobra"
	"github.com/twpayne/go-vfs/v5"
)

func slink(cmd *cobra.Command, args []string) {
	source := cmd.Flag("source").Value.String()
	target := cmd.Flag("target").Value.String()
	logrus.Infof("Source: %s, Target: %s", source, target)
	if source == "" || target == "" {
		logrus.Fatal("Source and target must be provided")
	}

	sourceFS := vfs.NewPathFS(vfs.OSFS, source)

	if err := vfs.Walk(sourceFS, "/", func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}

		// Create symlink
		linkname := path
		targetname := filepath.Join(target, path)
		logrus.Infof("Creating link %s to %s", linkname, targetname)

		if err := utils.CopyDir(filepath.Dir(linkname), sourceFS, vfs.OSFS); err != nil {
			logrus.Errorf("Error creating directory: %s", err)
			return err
		}

		if err := os.Symlink(targetname, linkname); err != nil {
			logrus.Errorf("Error creating symlink: %s", err)
			return err
		}

		return nil
	}); err != nil {
		logrus.Fatalf("Error walking source directory: %s", err)
	}
}

func main() {
	cmd := &cobra.Command{
		Use: "slink",
		Run: slink,
	}
	cmd.Flags().StringP("source", "s", "", "source directory")
	cmd.Flags().StringP("target", "t", "", "target prefix")
	if err := cmd.Execute(); err != nil {
		logrus.Fatal(err)
	}
}
