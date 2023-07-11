package internal

import (
	"context"
	"os"
	"reflect"
	"testing"
)

func TestDetermineFileTypeYaml(t *testing.T) {
	want := "yaml"
	got, err := determineFileType(context.Background(), "../tests/config_test.yml")
	if err != nil {
		t.Fatalf("Failed to determine file type due to error: %s", err.Error())
	}
	if got != want {
		t.Fatalf("Failed to determine the file type. Expected %s but received %s", want, got)
	}
}

func TestReadConfigFileYaml(t *testing.T) {
	// Prepare
	filePath := "../tests/config_test.yml"
	// Act
	config, err := readConfigFileYaml(context.Background(), filePath)
	if err != nil {
		t.Fatalf("Failed to read the config file: %s", err.Error())
	}

	// Assert
	// Here you would add specific checks to make sure the config file was correctly read.
	// For example, if you know the config file should have "ubuntu" as the osDistro:
	if *config.Config.Software.OsDistro != "ubuntu" {
		t.Fatalf("Unexpected osDistro. Expected ubuntu but received %s", *config.Config.Software.OsDistro)
	}
	if *config.Config.Palette.ApiKey != "1234567890" {
		t.Fatalf("Unexpected api key. Expected 1234567890 but received %s", *config.Config.Palette.ApiKey)
	}
	if *config.Config.CustomTag != "palette-learn" {
		t.Fatalf("Unexpected custom tag. Expected palette-learn but received %s", *config.Config.CustomTag)
	}
	if *config.Config.RegistryConfig.RegistryURL != "myUsername/edge" {
		t.Fatalf("Unexpected registry url. Expected myUsername/edge but received %s", *config.Config.RegistryConfig.RegistryURL)
	}

	// Add more checks based on your specific config structure and expected values...
}

func TestReadConfigFileFailureYaml(t *testing.T) {
	// Prepare
	filePath := "../tests/config_test_fail.yml"
	// An error is expected here because the config file is invalid
	_, err := readConfigFileYaml(context.Background(), filePath)
	if err == nil {
		t.Fatal("An error was expected but none was received")
	}

}

func TestGenerateExampleConfigFile(t *testing.T) {
	err := GenerateExampleConfigFile(context.Background())
	if err != nil {
		t.Fatalf("Failed to generate config file: %s", err.Error())
	}

	// Check if file exists
	_, err = os.Stat("config.yml")
	if os.IsNotExist(err) {
		t.Fatalf("The config file was not created")
	} else if err != nil {
		t.Fatalf("Failed to verify if config file exists: %s", err.Error())
	}

	// Clean up: delete the file after the test
	err = os.Remove("config.yml")
	if err != nil {
		t.Errorf("Failed to clean up: %s", err.Error())
	}
}

func TestGetUserValues(t *testing.T) {
	tests := []struct {
		name        string
		inputFile   string
		wantErr     bool
		wantUserSel UserSelections
		wantCliConf CliConfig
	}{
		{
			name:      "Valid config file",
			inputFile: "../tests/config_test.yml",
			wantErr:   false,
			wantUserSel: UserSelections{
				OperatingSystemDistro:       "ubuntu",
				OperatingSystemVersion:      "16.04",
				KubernetesDistro:            "kubeadm",
				CNI:                         "calico",
				CNIVersion:                  "0.12.5",
				ImageRegistryURL:            "myUsername",
				ImageRegistryRepository:     "edge",
				ImageRegistryUsername:       "myUsername",
				ImageRegistryPassword:       "superSecretPassword",
				PaletteEdgeInstallerVersion: "3.4.3",
				TenantRegistrationToken:     "1234567890",
				ISOName:                     "palette-learn",
				CreateClusterProfile:        true,
				ClusterProfileSuffix:        "learn",
				Platform:                    "linux/amd64",
				CustomTag:                   "palette-learn",
			},
			wantCliConf: CliConfig{
				PaletteApiKey: StrPtr("1234567890"),
				ProjectID:     StrPtr("1234567890"),
				PaletteHost:   StrPtr("https://api.spectrocloud.com"),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			userSel, cliConf, err := GetUserVaues(context.Background(), tt.inputFile)

			if (err != nil) != tt.wantErr {
				t.Errorf("GetUserVaues() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !reflect.DeepEqual(userSel, tt.wantUserSel) {
				t.Errorf("GetUserVaues() got = %v, want %v", userSel, tt.wantUserSel)
			}
			if !reflect.DeepEqual(cliConf, tt.wantCliConf) {
				t.Errorf("GetUserVaues() got = %v, want %v", cliConf, tt.wantCliConf)
			}
		})
	}
}
