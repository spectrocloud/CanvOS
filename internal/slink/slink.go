package main

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
	"github.com/twpayne/go-vfs/v5"
)

func slink(cmd *cobra.Command, args []string) {
	source := cmd.Flag("source").Value.String()
	target := cmd.Flag("target").Value.String()
	slog.Info(fmt.Sprintf("Source: %s, Target: %s", source, target))
	if source == "" || target == "" {
		slog.Error("Source and target must be provided")
		os.Exit(1)
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
		slog.Info(fmt.Sprintf("Creating link %s to %s", linkname, targetname))

		if err := copyDir(filepath.Dir(linkname), sourceFS, vfs.OSFS); err != nil {
			slog.Error("Error copying directory: %s", err)
			return err
		}

		if err := os.Symlink(targetname, linkname); err != nil {
			slog.Error("Error creating symlink: %s", err)
			return err
		}

		return nil
	}); err != nil {
		slog.Error("Error walking source directory: %s", err)
		os.Exit(1)
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
