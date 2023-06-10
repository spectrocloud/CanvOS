package internal

import (
	"fmt"
	"os/exec"
	"runtime"

	"github.com/shirou/gopsutil/mem"
	"golang.org/x/sys/unix"
	log "specrocloud.com/canvos/logger"
)

const (
	MinCPUs      = 4
	MinMemory    = 8 * 1024 * 1024 * 1024  // 8 GB in bytes
	MinFreeSpace = 50 * 1024 * 1024 * 1024 // 50 GB in bytes
)

type CheckResult struct {
	Name    string
	Success bool
	Error   string
}

type SystemCheckResponse struct {
	Checks []CheckResult
}

// checkSystemSpecifications checks the system specifications and returns a SystemCheckResponse
// containing the results of the checks.
// The following checks are performed:
// - CPU count: minimum 4 CPUs
// - Available memory: minimum 8 GB
// - Available disk space: minimum 50 GB
// - Architecture: only x86_64 (amd64) architecture is supported
func checkSystemSpecifications() SystemCheckResponse {
	var response SystemCheckResponse

	// Check CPU count
	cpuCount := runtime.NumCPU()
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
	v, err := mem.VirtualMemory()
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
	var stat unix.Statfs_t
	if err := unix.Statfs("/", &stat); err != nil {
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
	if runtime.GOARCH != "amd64" {
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
func checkDockerInstallation() CheckResult {
	cmd := exec.Command("docker", "--version")
	err := cmd.Run()
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

// checkGitInstallation checks if Git is installed and returns a CheckResult containing the result of the check.
func checkGitInstallation() CheckResult {
	cmd := exec.Command("git", "--version")
	err := cmd.Run()
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
func SystemPrerequisitesChecks() {

	var printFailedCheckMsg bool

	systemCheckResponse := checkSystemSpecifications()
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

	dockerCheckResult := checkDockerInstallation()
	log.InfoCLI("Docker: %s\n", getStatusText(dockerCheckResult))
	if !dockerCheckResult.Success {
		log.InfoCLI("Error: %s\n", dockerCheckResult.Error)
	}

	gitCheckResult := checkGitInstallation()
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
