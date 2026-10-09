//go:build !unix

package linkimport

import (
	"os/exec"
	"time"
)

func configureCommand(cmd *exec.Cmd) {
	cmd.WaitDelay = 5 * time.Second
}
