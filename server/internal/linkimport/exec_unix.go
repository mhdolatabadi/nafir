//go:build unix

package linkimport

import (
	"os/exec"
	"syscall"
	"time"
)

// configureCommand runs yt-dlp in its own process group, so a timeout also
// stops the ffmpeg it starts.
func configureCommand(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}
	cmd.WaitDelay = 5 * time.Second
}
