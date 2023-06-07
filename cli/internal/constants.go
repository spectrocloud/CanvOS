package internal

import "os"

const (
	DefaultUserAgent          string = "CanvoOS"
	Version                   string = ""
	DefaultCanvOsDir          string = ".canvos"
	DefaultCliMenuFile        string = "options.json"
	DefaultCliMenuOptionsPath string = DefaultCanvOsDir + string(os.PathSeparator) + DefaultCliMenuFile
)
