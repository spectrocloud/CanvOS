package internal

import (
	"fmt"
	"os"
	"runtime"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

// InitLogger initializes the logger
func InitLogger(logLevel string) {
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
	switch logLevel {
	case "TRACE":
		zerolog.SetGlobalLevel(zerolog.TraceLevel)
	case "DEBUG":
		zerolog.SetGlobalLevel(zerolog.DebugLevel)
	case "INFO":
		zerolog.SetGlobalLevel(zerolog.InfoLevel)
	case "WARN":
		zerolog.SetGlobalLevel(zerolog.WarnLevel)
	case "ERROR":
		zerolog.SetGlobalLevel(zerolog.ErrorLevel)
	case "FATAL":
		zerolog.SetGlobalLevel(zerolog.FatalLevel)
	case "PANIC":
		zerolog.SetGlobalLevel(zerolog.PanicLevel)
	default:
		zerolog.SetGlobalLevel(zerolog.DebugLevel)
	}
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})
}

// LogError logs the error
func LogError(err error) string {
	var output string
	pc, file, line, ok := runtime.Caller(1)

	if ok {
		// Create a string that contains the function name and the file name and line number
		output = "Error: " + err.Error() + " in " + runtime.FuncForPC(pc).Name() + " at " + file + ":" + fmt.Sprint(line)

	}

	return output

}
