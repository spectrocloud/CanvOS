package internal

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"

	"github.com/rs/zerolog/log"
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
		log.Debug().Msg("Error creating the OS directory")
		return err
	}

	if err := os.MkdirAll(DefaultCanvOsDir+pathSeparator+"k8s", 0755); err != nil {
		log.Debug().Msg("Error creating the k8s directory")
		return err
	}

	if err := os.MkdirAll(DefaultCanvOsDir+pathSeparator+"cni", 0755); err != nil {
		log.Debug().Msg("Error creating the cni directory")
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
				log.Debug().Msgf("Error creating the template file for %s", p.Spec.Name)
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
				log.Debug().Msgf("Error creating the template file for %s", p.Spec.Name)
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
				log.Debug().Msgf("Error creating the template file for %s", p.Spec.Name)
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

// CreateMenuOptionsFile creates a JSON file for the menu options used by the build command
// This file will be located in the .canvos directory
func CreateMenuOptionsFile(packs []Packs) error {

	pathSeparator := string(os.PathSeparator)

	options := OptionsMenu{}

	for _, p := range packs {

		for _, pack := range p.Items {
			switch pack.Spec.Name {
			case "edge-k3s":
				options.Kubernetes.Edgek3S = append(options.Kubernetes.Edgek3S, pack.Spec.Version)
			case "edge-k8s":
				options.Kubernetes.EdgeK8S = append(options.Kubernetes.EdgeK8S, pack.Spec.Version)
			case "edge-microk8s":
				options.Kubernetes.EdgeMicrok8S = append(options.Kubernetes.EdgeMicrok8S, pack.Spec.Version)
			case "edge-rke2":
				options.Kubernetes.EdgeRke2 = append(options.Kubernetes.EdgeRke2, pack.Spec.Version)
			case "edge-native-byoi":
				options.OperatingSystems.EdgeNativeByoi = append(options.OperatingSystems.EdgeNativeByoi, pack.Spec.Version)
			case "cni-calico":
				options.Cnis.Calico = append(options.Cnis.Calico, pack.Spec.Version)
			case "cni-flannel":
				options.Cnis.Flannel = append(options.Cnis.Flannel, pack.Spec.Version)
			case "edge-native-opensuse":
				options.OperatingSystems.OpenSuSE = append(options.OperatingSystems.OpenSuSE, pack.Spec.Version)
			case "edge-native-ubuntu":
				options.OperatingSystems.Ubuntu = append(options.OperatingSystems.Ubuntu, pack.Spec.Version)
			}
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
