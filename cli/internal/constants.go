package internal

import "os"

const (
	DefaultUserAgent          string = "CanvoOS"
	Version                   string = ""
	DefaultCanvOsDir          string = ".canvos"
	DefaultCliMenuFile        string = "options.json"
	DefaultCliMenuOptionsPath string = DefaultCanvOsDir + string(os.PathSeparator) + DefaultCliMenuFile
	MinCPUs                          = 4
	MinMemory                        = 8 * 1024 * 1024 * 1024  // 8 GB in bytes
	MinFreeSpace                     = 50 * 1024 * 1024 * 1024 // 50 GB in bytes
)
