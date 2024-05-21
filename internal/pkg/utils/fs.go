package utils

import (
	"os"
	"path/filepath"

	"github.com/twpayne/go-vfs/v5"
)

func CopyDir(path string, srcFS, dstFS vfs.FS) error {
	if exists, err := Exists(dstFS, path); err != nil {
		return err
	} else if exists {
		return nil
	}

	// Check if parent of path exists
	if err := CopyDir(filepath.Dir(path), srcFS, dstFS); err != nil {
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