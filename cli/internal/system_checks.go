package internal

import (
	"fmt"
	"os/exec"
	"runtime"

	"github.com/shirou/gopsutil/mem"
	"golang.org/x/sys/unix"
	log "specrocloud.com/canvos/logger"
)

type CheckResult struct {
	Name    string
	Success bool
	Error   string
}

type HostSystemProvider struct{}

func (r *HostSystemProvider) NumCPU() int {
	return runtime.NumCPU()
}

func (r *HostSystemProvider) VirtualMemory() (*mem.VirtualMemoryStat, error) {
	return mem.VirtualMemory()
}

func (r *HostSystemProvider) DiskStat() (*unix.Statfs_t, error) {
	var stat unix.Statfs_t
	err := unix.Statfs("/", &stat)
	return &stat, err
}

func (r *HostSystemProvider) GOARCH() string {
	return runtime.GOARCH
}

type SystemCheckResponse struct {
	Checks []CheckResult
}

type SystemInfoProvider interface {
	NumCPU() int
	VirtualMemory() (*mem.VirtualMemoryStat, error)
	DiskStat() (*unix.Statfs_t, error)
	GOARCH() string
}

type CommandExecutor interface {
	RunCommand(name string, arg ...string) error
}

type HostCommandExecutor struct{}

func (h *HostCommandExecutor) RunCommand(name string, arg ...string) error {
	cmd := exec.Command(name, arg...)
	return cmd.Run()
}

func checkSystemSpecifications(infoProvider SystemInfoProvider) SystemCheckResponse {
	var response SystemCheckResponse

	// Check CPU count
	cpuCount := infoProvider.NumCPU()
	if cpuCount < MinCPUs {
		response.Checks = append(response.Checks, CheckResult{
			Name:    "CPU Count",
			Success: false,
			Error:   "Insufficient CPU count. Minimum requirement: 4 CPUs",
		})
	} else {
		response.Checks = append(response.Checks, CheckResult{
			Name:    "CPU Count",
			Success: true,
		})
	}

	// Check available memory
	v, err := infoProvider.VirtualMemory()
	if err != nil {
		response.Checks = append(response.Checks, CheckResult{
			Name:    "Memory",
			Success: false,
			Error:   "Failed to retrieve system memory information",
		})
	} else {
		availableMemory := v.Free
		if availableMemory < MinMemory {
			response.Checks = append(response.Checks, CheckResult{
				Name:    "Memory",
				Success: false,
				Error:   "Insufficient memory. Minimum requirement: 8 GB",
			})
		} else {
			response.Checks = append(response.Checks, CheckResult{
				Name:    "Memory",
				Success: true,
			})
		}
	}

	// Check available disk space
	stat, err := infoProvider.DiskStat()
	if err != nil {
		response.Checks = append(response.Checks, CheckResult{
			Name:    "Disk Space",
			Success: false,
			Error:   "Failed to retrieve disk space information",
		})
	} else {
		availableSpace := stat.Bfree * uint64(stat.Bsize)
		if availableSpace < MinFreeSpace {
			response.Checks = append(response.Checks, CheckResult{
				Name:    "Disk Space",
				Success: false,
				Error:   "Insufficient disk space. Minimum requirement: 50 GB",
			})
		} else {
			response.Checks = append(response.Checks, CheckResult{
				Name:    "Disk Space",
				Success: true,
			})
		}
	}

	// Check architecture
	if infoProvider.GOARCH() != "amd64" {
		response.Checks = append(response.Checks, CheckResult{
			Name:    "Architecture",
			Success: false,
			Error:   "Unsupported architecture. Only x86_64 (amd64) architecture is supported.",
		})
	} else {
		response.Checks = append(response.Checks, CheckResult{
			Name:    "Architecture",
			Success: true,
		})
	}

	return response
}

// checkDockerInstallation checks if Docker is installed and returns a CheckResult containing the result of the check.
func checkDockerInstallation(executor CommandExecutor) CheckResult {
	err := executor.RunCommand("docker", "--version")
	if err != nil {
		return CheckResult{
			Name:    "Docker",
			Success: false,
			Error:   "Docker is not installed",
		}
	}

	return CheckResult{
		Name:    "Docker",
		Success: true,
	}
}

func checkGitInstallation(executor CommandExecutor) CheckResult {
	err := executor.RunCommand("git", "--version")
	if err != nil {
		return CheckResult{
			Name:    "Git",
			Success: false,
			Error:   "Git is not installed",
		}
	}

	return CheckResult{
		Name:    "Git",
		Success: true,
	}
}

// SystemPrerequisitesChecks performs the system prerequisites checks and prints the results to the CLI.
// SystemInfoProvider accepts a SystemInfoProvider interface that provides the system information.
func SystemPrerequisitesChecks(s SystemInfoProvider) {

	var printFailedCheckMsg bool

	systemCheckResponse := checkSystemSpecifications(s)
	if len(systemCheckResponse.Checks) > 0 {
		log.InfoCLI("System checks summary:")
		for _, check := range systemCheckResponse.Checks {
			log.InfoCLI("%s: %s\n", check.Name, getStatusText(check))
			if !check.Success {
				printFailedCheckMsg = true
			}
		}
	} else {
		log.InfoCLI("No system checks performed.")
	}

	cmdOnHost := &HostCommandExecutor{}

	dockerCheckResult := checkDockerInstallation(cmdOnHost)
	log.InfoCLI("Docker: %s\n", getStatusText(dockerCheckResult))
	if !dockerCheckResult.Success {
		log.InfoCLI("Error: %s\n", dockerCheckResult.Error)
	}

	gitCheckResult := checkGitInstallation(cmdOnHost)
	log.InfoCLI("Git: %s\n", getStatusText(gitCheckResult))
	if !gitCheckResult.Success {
		log.InfoCLI("Error: %s\n", gitCheckResult.Error)
	}

	if printFailedCheckMsg {
		log.InfoCLI("")
		log.InfoCLI("")
		log.InfoCLI("⚠️  System checks failed. The build command may not complete successfully.")
		log.InfoCLI("")
		log.InfoCLI("")
	}

}

// getStatusText returns the status text for a check result.
func getStatusText(c CheckResult) string {

	if c.Success {
		return "✅ - Pass"
	}

	msg := fmt.Sprintf("❌ - Fail - %s", c.Error)

	return msg

}
