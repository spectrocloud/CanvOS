package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/go-git/go-git/v5"
	log "specrocloud.com/canvos/logger"
)

// CreateCanvOsDir creates the directory for the CanvOS template files
// This will be located in the user's home directory
// The directory name will be .canvos
// If the directory already exists, do nothing
func CreateCanvOsDir(dir string) error {

	// Remove the directory if it already exists
	if _, err := os.Stat(dir); err == nil {
		if err := os.RemoveAll(dir); err != nil {
			return err
		}
	}

	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	return nil
}

// CreateTemplateFile creates the template file for the specified Pack
// The template files will be created in the CanvOS directory
// Each cluster profile layer will have its own directory
// The template file name will be <pack_name>-<pack_version>.yaml
func CreateTemplateFile(packs Packs) error {

	pathSeparator := string(os.PathSeparator)

	// Create the directory for each Cluster Profile layer
	// OS, K8s, CNI

	if err := os.MkdirAll(DefaultCanvOsDir+pathSeparator+"os", 0755); err != nil {
		log.Debug("Error creating the OS directory")
		return err
	}

	if err := os.MkdirAll(DefaultCanvOsDir+pathSeparator+"k8s", 0755); err != nil {
		log.Debug("Error creating the k8s directory")
		return err
	}

	if err := os.MkdirAll(DefaultCanvOsDir+pathSeparator+"cni", 0755); err != nil {
		log.Debug("Error creating the cni directory")
		return err
	}

	// Loop through the packs and create the template files
	for _, p := range packs.Items {

		// Filter out by layer
		switch p.Spec.Layer {
		case "os":

			filePath := DefaultCanvOsDir + pathSeparator + p.Spec.Layer + pathSeparator + p.Spec.Name + "-" + p.Spec.Version + ".yaml"
			file, err := os.Create(filePath)
			if err != nil {
				log.Debug("Error creating the template file for %s", p.Spec.Name)
				return err
			}
			defer file.Close()
			_, err = file.WriteString(p.Spec.Values)
			if err != nil {
				return err
			}

		case "k8s":
			filePath := DefaultCanvOsDir + pathSeparator + p.Spec.Layer + pathSeparator + p.Spec.Name + "-" + p.Spec.Version + ".yaml"
			file, err := os.Create(filePath)
			if err != nil {
				log.Debug("Error creating the template file for %s", p.Spec.Name)
				return err
			}
			defer file.Close()
			_, err = file.WriteString(p.Spec.Values)
			if err != nil {
				return err
			}
		case "cni":

			filePath := DefaultCanvOsDir + pathSeparator + p.Spec.Layer + pathSeparator + p.Spec.Name + "-" + p.Spec.Version + ".yaml"
			file, err := os.Create(filePath)
			if err != nil {
				log.Debug("Error creating the template file for %s", p.Spec.Name)
				return err
			}
			defer file.Close()
			_, err = file.WriteString(p.Spec.Values)
			if err != nil {
				return err
			}

		default:
			return errors.New("invalid Pack layer")

		}
	}

	return nil
}

// // CreateMenuOptionsFile creates a JSON file for the menu options used by the build command
// // This file will be located in the .canvos directory
func CreateMenuOptionsFile(packs []Packs, pv []string) error {

	pathSeparator := string(os.PathSeparator)

	options := OptionsMenu{}

	for _, p := range packs {
		for _, pack := range p.Items {
			switch pack.Spec.Name {
			case "edge-k3s":
				options.Kubernetes.Edgek3S.RegistryUID = pack.Spec.RegistryUID

				k3s := PackVersion{
					Version: pack.Spec.Version,
					UID:     pack.Metadata.UID,
				}
				options.Kubernetes.Edgek3S.Versions = append(options.Kubernetes.Edgek3S.Versions, k3s)

			case "edge-k8s":
				options.Kubernetes.EdgeK8S.RegistryUID = pack.Spec.RegistryUID

				k8s := PackVersion{
					Version: pack.Spec.Version,
					UID:     pack.Metadata.UID,
				}
				options.Kubernetes.EdgeK8S.Versions = append(options.Kubernetes.EdgeK8S.Versions, k8s)

			case "edge-microk8s":
				options.Kubernetes.EdgeMicrok8S.RegistryUID = pack.Spec.RegistryUID

				microk8s := PackVersion{
					Version: pack.Spec.Version,
					UID:     pack.Metadata.UID,
				}
				options.Kubernetes.EdgeMicrok8S.Versions = append(options.Kubernetes.EdgeMicrok8S.Versions, microk8s)

			case "edge-rke2":
				options.Kubernetes.EdgeRke2.RegistryUID = pack.Spec.RegistryUID

				rke2 := PackVersion{
					Version: pack.Spec.Version,
					UID:     pack.Metadata.UID,
				}

				options.Kubernetes.EdgeRke2.Versions = append(options.Kubernetes.EdgeRke2.Versions, rke2)

			case "edge-native-byoi":
				options.OperatingSystems.EdgeNativeByoi.RegistryUID = pack.Spec.RegistryUID

				byoi := PackVersion{
					Version: pack.Spec.Version,
					UID:     pack.Metadata.UID,
				}

				options.OperatingSystems.EdgeNativeByoi.Versions = append(options.OperatingSystems.EdgeNativeByoi.Versions, byoi)
			case "cni-calico":
				options.Cnis.Calico.RegistryUID = pack.Spec.RegistryUID

				calico := PackVersion{
					Version: pack.Spec.Version,
					UID:     pack.Metadata.UID,
				}

				options.Cnis.Calico.Versions = append(options.Cnis.Calico.Versions, calico)

			case "cni-flannel":
				options.Cnis.Flannel.RegistryUID = pack.Spec.RegistryUID

				flannel := PackVersion{
					Version: pack.Spec.Version,
					UID:     pack.Metadata.UID,
				}

				options.Cnis.Flannel.Versions = append(options.Cnis.Flannel.Versions, flannel)

			case "edge-native-ubuntu":
				options.OperatingSystems.Ubuntu.RegistryUID = pack.Spec.RegistryUID

				ubuntu := PackVersion{
					Version: pack.Spec.Version,
					UID:     pack.Metadata.UID,
				}

				options.OperatingSystems.Ubuntu.Versions = append(options.OperatingSystems.Ubuntu.Versions, ubuntu)

			case "edge-native-opensuse":
				options.OperatingSystems.OpenSuSE.RegistryUID = pack.Spec.RegistryUID

				opensuse := PackVersion{
					Version: pack.Spec.Version,
					UID:     pack.Metadata.UID,
				}

				options.OperatingSystems.OpenSuSE.Versions = append(options.OperatingSystems.OpenSuSE.Versions, opensuse)
			}
		}
	}

	// Add the palette versions
	options.PaletteVersions = pv

	filePath := DefaultCanvOsDir + pathSeparator + "options.json"

	data, err := json.MarshalIndent(options, "", "  ")
	if err != nil {
		return fmt.Errorf("error marshalling options to JSON: %v", err)
	}

	if err = os.WriteFile(filePath, data, 0700); err != nil {
		return fmt.Errorf("error writing JSON data to file: %v", err)
	}

	return nil
}

// DynamicCreateMenuOptionsFile creates a JSON file for the menu options used by the build command
// This function forgoes all type safety and uses a map of maps to create the JSON file
// This function is not recommended but might be useful if pack names and versions change rapidly
func DynamicCreateMenuOptionsFile(packs []Packs) error {
	pathSeparator := string(os.PathSeparator)

	options := make(map[string]map[string][]string)

	for _, p := range packs {
		for _, pack := range p.Items {
			layer := pack.Spec.Layer
			name := pack.Spec.Name
			version := pack.Spec.Version

			if _, ok := options[layer]; !ok {
				options[layer] = make(map[string][]string)
			}

			options[layer][name] = append(options[layer][name], version)

		}
	}

	filePath := DefaultCanvOsDir + pathSeparator + "options.json"

	data, err := json.MarshalIndent(options, "", "  ")
	if err != nil {
		return fmt.Errorf("error marshalling options to JSON: %v", err)
	}

	if err = os.WriteFile(filePath, data, 0700); err != nil {
		return fmt.Errorf("error writing JSON data to file: %v", err)
	}

	return nil
}

// removeDuplicates removes duplicate packs
func RemoveDuplicatePacks(packs *[]Packs) {
	seen := make(map[string]struct{})
	result := []Packs{}

	for _, p := range *packs {
		packsSet := Packs{
			Items:    []Pack{},
			Listmeta: p.Listmeta,
		}
		for _, item := range p.Items {
			if _, ok := seen[item.Metadata.UID]; !ok {
				seen[item.Metadata.UID] = struct{}{}
				packsSet.Items = append(packsSet.Items, item)
			}
		}
		result = append(result, packsSet)
	}

	*packs = result
}

// ReadOptionsFile reads the options file and returns the OptionsMenu struct
func ReadOptionsFile(path string) (*OptionsMenu, error) {

	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	byteValue, err := io.ReadAll(file)
	if err != nil {
		return nil, err
	}

	var optionsMenu OptionsMenu

	err = json.Unmarshal(byteValue, &optionsMenu)
	if err != nil {
		return nil, err
	}

	return &optionsMenu, nil
}

// CreateDemoUserData creates a user-data file for the demo
func CreateDemoUserData(token string) error {

	fileName := "user-data"

	file, err := os.Create(fileName)
	if err != nil {
		return err
	}
	defer file.Close()

	// Define the template with the placeholder for the token
	template := `
	#cloud-config
	stylus:
	  site:
		edgeHostToken: $token
	install:
	  poweroff: true
	users:
	  - name: kairos
		passwd: kairos
		`

	// Replace the placeholder with the actual token
	content := strings.Replace(template, "$token", token, -1)

	// Write the content to the file
	_, err = file.WriteString(content)
	if err != nil {
		return err
	}

	return nil
}

// CreateDemoArgsFile creates an args file for the demo
// The default file name is .arg but can be changed with the fileName parameter
func CreateArgsFile(fileName string, u UserSelections) error {

	if fileName == "" {
		fileName = ".arg"
	}
	file, err := os.Create(fileName)
	if err != nil {
		log.Debug("error creating args file")
		return err
	}
	defer file.Close()

	u.KubernetesDistro = strings.ToLower(u.KubernetesDistro)
	u.OperatingSystemDistro = strings.ToLower(u.OperatingSystemDistro)
	// The following logic is to handle allowed values in the .args file and to ensure correct output matching the earthly generated output
	if u.KubernetesDistro == "k8s" {
		u.KubernetesDistro = "kubeadm"

	}

	if u.OperatingSystemDistro == "opensuse" {
		u.OperatingSystemDistro = "opensuse-leap"
	}

	template := `
CUSTOM_TAG=$CUSTOM_TAG
IMAGE_REGISTRY=$IMAGE_REGISTRY
OS_DISTRIBUTION=$OS_DISTRIBUTION
IMAGE_REPO=$IMAGE_REPO
OS_VERSION=$OS_VERSION   
K8S_DISTRIBUTION=$K8S_DISTRIBUTION
ISO_NAME=$ISO_NAME
PE_VERSION=v$TAG
platform=$PLATFORM
	`

	content := strings.Replace(template, "$CUSTOM_TAG", u.CustomTag, -1)
	content = strings.Replace(content, "$IMAGE_REGISTRY", u.ImageRegistryURL, -1)
	content = strings.Replace(content, "$OS_DISTRIBUTION", u.OperatingSystemDistro, -1)
	content = strings.Replace(content, "$IMAGE_REPO", u.ImageRegistryRepository, -1)
	// The Eartly scrips adds the version to the end of the OS version string so we only need to provide the major release
	content = strings.Replace(content, "$OS_VERSION", getOSMajorRelease(u.OperatingSystemVersion), -1)
	content = strings.Replace(content, "$K8S_DISTRIBUTION", strings.ToLower(u.KubernetesDistro), -1)
	content = strings.Replace(content, "$ISO_NAME", u.ISOName, -1)
	content = strings.Replace(content, "$TAG", u.PaletteEdgeInstallerVersion, -1)
	content = strings.Replace(content, "$PLATFORM", u.Platform, -1)

	// Write the content to the file
	_, err = file.WriteString(content)
	if err != nil {
		log.Debug("error writing to args file")
		return err
	}

	return nil
}

// getOSMajorRelease returns the major release of the OS
// The first characters before the first dot
// are considered the major release
func getOSMajorRelease(osVersion string) string {

	// Split the string by the dot
	s := strings.Split(osVersion, ".")
	// Get the first element
	majorRelease := s[0]

	return majorRelease
}

// CloneCanvOS clones the CanvOS repo
func CloneCanvOS(ctx context.Context) error {
	// get the first characters before the first dot
	// Example: 20.04.2
	// Result: 20
	path := DefaultCanvOsDir + string(os.PathSeparator) + "canvOS"

	_, err := git.PlainCloneContext(ctx, path, false, &git.CloneOptions{
		URL:   "https://github.com/spectrocloud/CanvOS.git",
		Depth: 1,
	})
	if err != nil {
		log.Info("error cloning CanvOS repo: %v", err)
		return err
	}
	return nil
}

// StartBuildProcessScript starts the build process script
// This is the CanvOS Earthly build script
func StartBuildProcessScript(ctx context.Context, u UserSelections) error {
	err := moveRequiredCanvOSFiles()
	if err != nil {
		log.Debug("error moving required files: %v", err)
		return err
	}

	workingDir := DefaultCanvOsDir + string(os.PathSeparator) + "canvOS"
	// path := DefaultCanvOsDir + string(os.PathSeparator) + "canvOS" + string(os.PathSeparator) + "earthly.sh"

	cmd := exec.CommandContext(ctx, "sudo", "./earthly.sh", "+build-all-images")
	cmd.Dir = workingDir

	// Create pipes for capturing the output
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		log.InfoCLI("Error creating StdoutPipe: %v", err)
		return err
	}

	// Start the command
	if err := cmd.Start(); err != nil {
		log.InfoCLI("Error starting command: %s", err)
		return err
	}

	// Create a goroutine to read and display the command output
	go func() {
		_, err := io.Copy(os.Stdout, stdout)
		if err != nil {
			log.InfoCLI("Error copying output: %v", err)
			return
		}
	}()

	// Wait for the command to complete
	if err := cmd.Wait(); err != nil {
		log.InfoCLI("Command execution failed: %v", err)
		return err
	}

	return nil
}

// moveRequiredCanvOSFiles moves the required files from the .canvos repo to the .canvos/canvOS directory
// The two files are:
// 1. .arg
// 2. user-data
func moveRequiredCanvOSFiles() error {

	destinationFolder := DefaultCanvOsDir + string(os.PathSeparator) + "canvOS" + string(os.PathSeparator)
	argFile := ".arg"

	err := os.Rename(argFile, destinationFolder+string(os.PathSeparator)+".arg")
	if err != nil {
		log.Info("error moving %v to %v: %v", argFile, destinationFolder, err)
		return fmt.Errorf("error moving %v to %v: %w", argFile, destinationFolder, err)
	}

	userDataFile := "user-data"

	// Moving sourceFile2 to destinationDir
	err = os.Rename(userDataFile, destinationFolder+string(os.PathSeparator)+"user-data")
	if err != nil {
		log.Info("error moving %v to %v: %v", userDataFile, destinationFolder, err)
		return fmt.Errorf("error moving %v to %v: %w", userDataFile, destinationFolder, err)
	}

	return nil

}

// CopyTemplateFiles copies the default template files "Dockerfile" and "user-data" to the root directory
// If the files already exist, they are not copied
func CopyTemplateFiles() error {

	// Check if the files already exist
	// If they do, do not copy them
	// If they do not, copy them
	// Dockerfile
	_, err := os.Stat("Dockerfile")
	if os.IsNotExist(err) {
		// File does not exist
		// Copy the file
		err = copyFile(DefaultCanvOsDir+string(os.PathSeparator)+"canvOS"+string(os.PathSeparator)+"Dockerfile", "Dockerfile")
		if err != nil {
			log.Debug("error copying Dockerfile: %v", err)
			return fmt.Errorf("error copying Dockerfile: %w", err)
		}
	}

	// user-data
	_, err = os.Stat("user-data")
	if os.IsNotExist(err) {
		// File does not exist
		// Copy the file
		err = copyFile(DefaultCanvOsDir+string(os.PathSeparator)+"canvOS"+string(os.PathSeparator)+"user-data.template", "user-data")
		if err != nil {
			log.Debug("error copying user-data: %v", err)
			return fmt.Errorf("error copying user-data: %w", err)
		}
	}

	return nil
}

// copyFile copies a file from source to destination
func copyFile(sourcePath, destinationPath string) error {
	// Open the source file for reading
	sourceFile, err := os.Open(sourcePath)
	if err != nil {
		return err
	}
	defer sourceFile.Close()

	// Create the destination file
	destinationFile, err := os.OpenFile(destinationPath, os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	defer destinationFile.Close()

	// Copy the contents of the source file to the destination file
	_, err = io.Copy(destinationFile, sourceFile)
	if err != nil {
		return err
	}

	return nil
}

// CopyDirectory copies a directory from source to destination
func CopyDirectory(srcDir, dstDir string) error {
	return filepath.Walk(srcDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return fmt.Errorf("error walking the path %q: %w", path, err)
		}

		relativePath, err := filepath.Rel(srcDir, path)
		if err != nil {
			return fmt.Errorf("error getting relative path %q: %w", path, err)
		}
		dstPath := filepath.Join(dstDir, relativePath)

		if info.IsDir() {
			if _, err := os.Stat(dstPath); os.IsNotExist(err) {
				os.MkdirAll(dstPath, info.Mode())
			}
		} else {
			if _, err := os.Stat(filepath.Dir(dstPath)); os.IsNotExist(err) {
				os.MkdirAll(filepath.Dir(dstPath), os.ModePerm)
			}

			srcFile, err := os.Open(path)
			if err != nil {
				return fmt.Errorf("error opening the source file %q: %w", path, err)
			}
			defer srcFile.Close()

			dstFile, err := os.OpenFile(dstPath, os.O_CREATE|os.O_WRONLY, info.Mode())
			if err != nil {
				return fmt.Errorf("error creating the destination file %q: %w", dstPath, err)
			}
			defer dstFile.Close()

			_, err = io.Copy(dstFile, srcFile)
			if err != nil {
				return fmt.Errorf("error copying content from %q to %q: %w", path, dstPath, err)
			}
		}

		return nil
	})
}
