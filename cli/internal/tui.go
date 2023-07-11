package internal

import "github.com/chzyer/readline"

// NoBellStdout is a wrapper around readline.Stdout that suppresses the bell sound that is triggered during a selection in the promptui library
type noBellStdout struct{}

// Write is a wrapper around readline.Stdout.Write that suppresses the bell sound that is triggered during a selection in the promptui library
func (n *noBellStdout) Write(p []byte) (int, error) {
	if len(p) == 1 && p[0] == readline.CharBell {
		return 0, nil
	}
	return readline.Stdout.Write(p)
}

// Close is a wrapper around readline.Stdout.Close that suppresses the bell sound that is triggered during a selection in the promptui library
func (n *noBellStdout) Close() error {
	return readline.Stdout.Close()
}

// NoBellStdout is an exported variable that is a wrapper around readline.Stdout that suppresses the bell sound that is triggered during a selection in the promptui library
var NoBellStdout = &noBellStdout{}
