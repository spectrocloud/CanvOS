package internal

import (
	"errors"
	"testing"

	"github.com/shirou/gopsutil/mem"
	"golang.org/x/sys/unix"
)

type mockSystemInfoProvider struct {
	numCPU   int
	vMemory  *mem.VirtualMemoryStat
	diskStat *unix.Statfs_t
	goarch   string
}

func (m *mockSystemInfoProvider) NumCPU() int {
	return m.numCPU
}

func (m *mockSystemInfoProvider) VirtualMemory() (*mem.VirtualMemoryStat, error) {
	return m.vMemory, nil
}

func (m *mockSystemInfoProvider) DiskStat() (*unix.Statfs_t, error) {
	return m.diskStat, nil
}

func (m *mockSystemInfoProvider) GOARCH() string {
	return m.goarch
}

func TestCheckSystemSpecifications(t *testing.T) {
	mockProvider := &mockSystemInfoProvider{
		numCPU: 2,
		vMemory: &mem.VirtualMemoryStat{
			Free: MinMemory - 1,
		},
		diskStat: &unix.Statfs_t{
			Bfree: MinFreeSpace - 1,
			Bsize: 1,
		},
		goarch: "386",
	}
	response := checkSystemSpecifications(mockProvider)

	// Now we can be sure about what the checks are supposed to be
	for _, check := range response.Checks {
		if check.Success {
			t.Errorf("Check %s marked as success but it was supposed to fail", check.Name)
		}
	}
}

type MockCommandExecutor struct {
	Error error
}

func (m *MockCommandExecutor) RunCommand(name string, arg ...string) error {
	return m.Error
}

func TestCheckGitInstallation(t *testing.T) {
	mock := &MockCommandExecutor{Error: nil}
	result := checkGitInstallation(mock)
	if !result.Success {
		t.Error("Expected Git check to succeed, but it failed")
	}

	mock.Error = errors.New("command failed")
	result = checkGitInstallation(mock)
	if result.Success {
		t.Error("Expected Git check to fail, but it succeeded")
	}
}

func TestCheckDockerInstallation(t *testing.T) {
	mock := &MockCommandExecutor{Error: nil}
	result := checkDockerInstallation(mock)
	if !result.Success {
		t.Error("Expected Docker check to succeed, but it failed")
	}

	mock.Error = errors.New("command failed")
	result = checkDockerInstallation(mock)
	if result.Success {
		t.Error("Expected Docker check to fail, but it succeeded")
	}
}

func TestGetStatusText(t *testing.T) {
	successCheck := CheckResult{
		Name:    "Test Success",
		Success: true,
		Error:   "",
	}
	expectedSuccess := "✅ - Pass"
	if result := getStatusText(successCheck); result != expectedSuccess {
		t.Errorf("Expected '%s', but got '%s'", expectedSuccess, result)
	}

	failureCheck := CheckResult{
		Name:    "Test Failure",
		Success: false,
		Error:   "Some error",
	}
	expectedFailure := "❌ - Fail - Some error"
	if result := getStatusText(failureCheck); result != expectedFailure {
		t.Errorf("Expected '%s', but got '%s'", expectedFailure, result)
	}
}
