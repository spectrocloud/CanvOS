package main

import (
	"os"
	"path/filepath"

	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/twpayne/go-vfs/v4"
)

func slink(cmd *cobra.Command, args []string) {
	source := cmd.Flag("source").Value.String()
	target := cmd.Flag("target").Value.String()
	logrus.Infof("Source: %s, Target: %s", source, target)
	if source == "" || target == "" {
		logrus.Fatal("Source and target are required")
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

		if err := copyDir(filepath.Dir(linkname), sourceFS, vfs.OSFS); err != nil {
			logrus.Error(err)
			return err
		}

		if err := os.Symlink(targetname, linkname); err != nil {
			logrus.Error(err)
			return err
		}

		return nil
	}); err != nil {
		logrus.Fatal(err)
	}
}

func copyDir(path string, srcFS, dstFS vfs.FS) error {
	if exists, err := Exists(dstFS, path); err != nil {
		return err
	} else if exists {
		return nil
	}

	// Check if parent of path exists
	if err := copyDir(filepath.Dir(path), srcFS, dstFS); err != nil {
		return err
	}

	// Get permission of source directory
	srcInfo, err := srcFS.Stat(path)
	if err != nil {
		return err
	}
	// Create directory with same permissions as source
	if err := vfs.MkdirAll(dstFS, path, srcInfo.Mode()); err != nil {
		return err
	}
	return nil
}

func Exists(fs vfs.FS, path string) (bool, error) {
	_, err := fs.Stat(path)
	if err == nil {
		return true, nil
	}
	if os.IsNotExist(err) {
		return false, nil
	}
	return false, err
}
func main() {
	cmd := &cobra.Command{
		Use: "slink",
		Run: slink,
	}
	cmd.Flags().StringP("source", "s", "", "source directory")
	cmd.Flags().StringP("target", "t", "", "target prefix")
	cmd.Execute()
}
