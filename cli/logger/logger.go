package logging

import (
	"bufio"
	"fmt"
	"io"
	logging "log"
	"os"
	"runtime"
	"strings"

	"github.com/sirupsen/logrus"
	"github.com/spectrocloud/palette-cli/models"
)

// The global logger's standard methods (i.e., log.Infof, log.Debugf, etc.)
// write log entries to disk. The file location varies based on the subcommand
// being invoked, e.g.:
//
//   palette pde ... logs to ~/.palette/pde/logs/palette.log
//   palette vm ... logs to ~/.palette/vm/logs/palette.log
//   ... etc.
//
// The log.InfoCLI method logs entries to the console. It is used to guide users
// through an interactive TUI experience.

var (
	log                 *logrus.Logger
	logFile, statusFile string
	Newline             = true
)

func init() {
	log = &logrus.Logger{
		Out: io.Discard,
		Formatter: &logrus.TextFormatter{
			FullTimestamp: true,
		},
	}
}

func SetLevel(logLevel string) {
	level, err := logrus.ParseLevel(logLevel)
	if err != nil {
		logging.Fatalf("error setting log level: %v", err)
	}
	log.SetLevel(level)
}

func SetOutput(runLoc string) {
	logFile = fmt.Sprintf("%s/logs/palette.log", runLoc)
	statusFile = fmt.Sprintf("%s/status/status", runLoc)

	f, err := os.OpenFile(logFile, os.O_RDWR|os.O_CREATE|os.O_APPEND, 0666)
	if err != nil {
		logging.Fatalf("error opening file: %v", err)
	}
	log.SetOutput(f)
}

// logContext recovers the original caller context of each log message
func logContext() *logrus.Entry {
	if pc, file, line, ok := runtime.Caller(2); ok {
		file = file[strings.LastIndex(file, "/")+1:]
		funcFull := runtime.FuncForPC(pc).Name()
		funcName := funcFull[strings.LastIndex(funcFull, ".")+1:]
		entry := log.WithField("src", fmt.Sprintf("%s:%s:%d", file, funcName, line))
		return entry
	}
	return nil
}

// Debug ...
func Debug(format string, v ...interface{}) {
	entry := logContext()
	entry.Debugf(format, v...)
}

// Info ...
func Info(format string, v ...interface{}) {
	entry := logContext()
	entry.Infof(format, v...)
}

// Warn ...
func Warn(format string, v ...interface{}) {
	entry := logContext()
	entry.Warnf(format, v...)
}

// Error ...
func Error(format string, v ...interface{}) {
	entry := logContext()
	entry.Errorf(format, v...)
}

// FatalCLI prints a message to the terminal & exits
func FatalCLI(format string, v ...interface{}) {
	printToConsole(format, v...)

	entry := logContext()
	entry.Fatalf(format, v...)
}

// InfoCLI prints a message to the terminal & creates a log entry
func InfoCLI(format string, v ...interface{}) {
	printToConsole(format, v...)

	entry := logContext()
	entry.Infof(format, v...)
}

func printToConsole(format string, v ...interface{}) {
	s := fmt.Sprintf(format, v...)
	fmt.Fprint(os.Stdout, strings.TrimSuffix(s, "\n"))
	if Newline {
		fmt.Fprintf(os.Stdout, "\n")
	}
}

// ReadLogs reads all log data for the active EC/PCG deployment from disk
func ReadLogs() (*models.V1Logs, error) {
	f, err := os.Open(logFile)
	if err != nil {
		Error("error opening log file: %v", err)
		return nil, err
	}
	defer f.Close()

	logData := models.V1Logs{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		logData = append(logData, scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		Error("error reading logs: %v", err)
		return nil, err
	}

	return &logData, nil
}

// ReadStatus reads the status of the active EC/PCG deployment from disk
func ReadStatus() (*models.V1Status, error) {
	b, err := os.ReadFile(statusFile)
	if err != nil {
		Error("error opening status file: %v", err)
		return nil, err
	}
	status := models.V1Status(string(b))
	return &status, nil
}

// WriteStatus writes the status of the active EC/PCG deployment to disk
func WriteStatus(status string) error {
	err := os.WriteFile(statusFile, []byte(status), 0666)
	if err != nil {
		Error("error updating status file: %v", err)
		return err
	}
	return nil
}

// Out returns the io.Writer used to write messages to the console
func Out() *os.File {
	return os.Stdout
}
