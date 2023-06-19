package internal

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

type CliConfig struct {
	// Verbose is the verbosity level for the stdout output
	// DEBUG, INFO, WARN, ERROR, FATAL are the available levels
	Verbose *string
	//PaletteApiKey is the Palette API key
	PaletteApiKey *string
	//PaletteHost is the Palette API host
	PaletteHost *string
	// ProjectID is the Palette project ID
	ProjectID *string
	// ConfigFile is the path to the config file
	ConfigFile *string
	// GenerateExampleConfig is to generate an example config file
	GenerateExampleConfig *bool
}

// PaletteAuth is the authentication information for the Palette API
// Host: The Palette API host
// APIKey: The Palette API key
// ProjectID: The Palette project ID
type PaletteAuth struct {
	// Host is the Palette API host
	Host string
	// APIKey is the Palette API key
	APIKey string
	// ProjectID is the Palette project ID
	ProjectID string
}

// Pack is the JSON data for a Palette pack
type Packs struct {
	Items    []Pack   `json:"items"`
	Listmeta Listmeta `json:"listmeta"`
}
type Annotations struct {
	OwnerUID        string `json:"ownerUid"`
	Permissions     string `json:"permissions"`
	Scope           string `json:"scope"`
	ScopeVisibility string `json:"scopeVisibility"`
}
type Metadata struct {
	Annotations           Annotations `json:"annotations"`
	CreationTimestamp     time.Time   `json:"creationTimestamp"`
	DeletionTimestamp     time.Time   `json:"deletionTimestamp"`
	LastModifiedTimestamp time.Time   `json:"lastModifiedTimestamp"`
	Name                  string      `json:"name"`
	UID                   string      `json:"uid"`
}
type SpecAnnotations struct {
	ImageID             string `json:"imageId"`
	Olname              string `json:"olname"`
	OsSpectroVersion    string `json:"os_spectro_version"`
	VersionAutoSelected string `json:"versionAutoSelected"`
	VersionHint         string `json:"versionHint"`
}
type Schema struct {
	Format      string        `json:"format"`
	Hints       []string      `json:"hints"`
	ListOptions []interface{} `json:"listOptions"`
	Name        string        `json:"name"`
	Readonly    bool          `json:"readonly"`
	Regex       string        `json:"regex"`
	Required    bool          `json:"required"`
	Type        string        `json:"type"`
}
type Parameters struct {
	InputParameters  []interface{} `json:"inputParameters"`
	OutputParameters []interface{} `json:"outputParameters"`
}
type Template struct {
	Parameters Parameters `json:"parameters"`
}
type Spec struct {
	Annotations SpecAnnotations `json:"annotations"`
	CloudTypes  []string        `json:"cloudTypes"`
	Digest      string          `json:"digest"`
	DisplayName string          `json:"displayName"`
	Layer       string          `json:"layer"`
	LogoURL     string          `json:"logoUrl"`
	Manifests   interface{}     `json:"manifests"`
	Name        string          `json:"name"`
	Presets     []interface{}   `json:"presets"`
	RegistryUID string          `json:"registryUid"`
	Schema      []Schema        `json:"schema"`
	Template    Template        `json:"template"`
	Type        string          `json:"type"`
	Values      string          `json:"values"`
	Version     string          `json:"version"`
}
type Pack struct {
	Metadata Metadata    `json:"metadata"`
	Spec     Spec        `json:"spec"`
	Status   interface{} `json:"status"`
}
type Listmeta struct {
	Continue string `json:"continue"`
	Count    int    `json:"count"`
	Limit    int    `json:"limit"`
	Offset   int    `json:"offset"`
}

// The Options struct for the CLI menu options
type OptionsMenu struct {
	Kubernetes       OptionsKubernetes       `json:"kubernetes,omitempty"`
	OperatingSystems OptionsOperatingSystems `json:"operating_systems,omitempty"`
	Cnis             OptionsCNIs             `json:"cnis,omitempty"`
	PaletteVersions  []string                `json:"palette_versions,omitempty"`
}
type OptionsKubernetes struct {
	Edgek3S      AvailblePacks `json:"edge-k3s,omitempty"`
	EdgeK8S      AvailblePacks `json:"edge-k8s,omitempty"`
	EdgeMicrok8S AvailblePacks `json:"edge-microk8s,omitempty"`
	EdgeRke2     AvailblePacks `json:"edge-rke2,omitempty"`
}

type OptionsOperatingSystems struct {
	EdgeNativeByoi AvailblePacks `json:"edge-native-byoi,omitempty"`
	Ubuntu         AvailblePacks `json:"edge-native-ubuntu,omitempty"`
	OpenSuSE       AvailblePacks `json:"edge-native-opensuse,omitempty"`
}
type OptionsCNIs struct {
	Calico  AvailblePacks `json:"calico,omitempty"`
	Cilium  AvailblePacks `json:"cilium,omitempty"`
	Custom  AvailblePacks `json:"custom,omitempty"`
	Flannel AvailblePacks `json:"flannel,omitempty"`
}

type AvailblePacks struct {
	RegistryUID string        `json:"registryUid"`
	Versions    []PackVersion `json:"versions"`
}

type PackVersion struct {
	Version string `json:"version"`
	UID     string `json:"uid"`
}

// GetBYOOSVersions returns the available BYOOS versions
func (o *OptionsMenu) GetBYOOSVersions() []string {
	var byooVersions []string

	if len(o.OperatingSystems.EdgeNativeByoi.Versions) > 0 {
		for _, v := range o.OperatingSystems.EdgeNativeByoi.Versions {
			byooVersions = append(byooVersions, v.Version)
		}
	}

	return byooVersions
}

// GetKubernetesDistroPaletteValue returns the raw Palette value for the Kubernetes distro
func GetKubernetesDistroPaletteValue(value string) (string, error) {

	var output string

	lowerValue := strings.ToLower(value)

	switch lowerValue {
	case "k3s":
		output = "k3s"

	case "Palette eXtended Kubernetes - Edge (PXK-E)", "pxk-e", "k8s", "palette extended kubernetes - edge (pxk-e)":
		output = "k8s"

	case "microk8s":
		output = "microk8s"

	case "rke2":
		output = "rke2"
	case "kubeadm": // Kubeadm is PXK-E
		output = "k8s"

	default:
		return "", fmt.Errorf("invalid Kubernetes distro value: %s", value)
	}

	return output, nil
}

// GetKubernetesDistroOptions returns the available Kubernetes distros
func (o *OptionsMenu) GetKubernetesDistroOptions() []string {

	var k8sDistros []string

	if len(o.Kubernetes.Edgek3S.Versions) > 0 {
		k8sDistros = append(k8sDistros, "K3s")
	}

	// The following distros are not yet supported

	if len(o.Kubernetes.EdgeK8S.Versions) > 0 {
		k8sDistros = append(k8sDistros, "Palette eXtended Kubernetes - Edge (PXK-E)")
	}

	// if len(o.Kubernetes.EdgeMicrok8S.Versions) > 0 {
	// 	k8sDistros = append(k8sDistros, "MicroK8s")
	// }

	if len(o.Kubernetes.EdgeRke2.Versions) > 0 {
		k8sDistros = append(k8sDistros, "RKE2")
	}

	// // Add Kubeadm as an option
	// k8sDistros = append(k8sDistros, "Kubeadm")

	return k8sDistros
}

// GetOperatingSystemOptions returns the available operating systems version for a given Kubernetes distro
func (o *OptionsMenu) GetKubernetesDistroVersions(value string) []string {
	var k8sDistroVersions []string

	k8s := strings.ToLower(value)

	switch k8s {
	case "k3s":
		if len(o.Kubernetes.Edgek3S.Versions) > 0 {
			for _, v := range o.Kubernetes.Edgek3S.Versions {
				k8sDistroVersions = append(k8sDistroVersions, v.Version)
			}
		}
	case "k8s", "kubeadm":
		if len(o.Kubernetes.EdgeK8S.Versions) > 0 {
			for _, v := range o.Kubernetes.EdgeK8S.Versions {
				k8sDistroVersions = append(k8sDistroVersions, v.Version)
			}
		}
	case "microk8s":

		if len(o.Kubernetes.EdgeMicrok8S.Versions) > 0 {
			for _, v := range o.Kubernetes.EdgeMicrok8S.Versions {
				k8sDistroVersions = append(k8sDistroVersions, v.Version)
			}
		}
	case "rke2":
		for _, v := range o.Kubernetes.EdgeRke2.Versions {
			k8sDistroVersions = append(k8sDistroVersions, v.Version)
		}

	}

	return k8sDistroVersions
}

// getOperatingSystemDistroOptions returns the available operating system distros
func (o *OptionsMenu) GetOperatingSystemDistroOptions() []string {
	var osDistros []string

	if len(o.OperatingSystems.Ubuntu.Versions) > 0 {
		osDistros = append(osDistros, "Ubuntu")
	}

	if len(o.OperatingSystems.OpenSuSE.Versions) > 0 {
		osDistros = append(osDistros, "OpenSuSE")
	}

	return osDistros
}

// getOperatingSystemVersionOptions returns the available operating system versions for a given operating system distro
func (o *OptionsMenu) GetOperatingSystemVersionOptions(os string) []string {
	var osVersions []string

	str := strings.ToLower(os)

	if str == "ubuntu" {
		for _, v := range o.OperatingSystems.Ubuntu.Versions {
			osVersions = append(osVersions, v.Version)
		}
	}

	if str == "opensuse" || str == "opensuse leap" {
		for _, v := range o.OperatingSystems.OpenSuSE.Versions {
			osVersions = append(osVersions, v.Version)
		}
	}

	return osVersions
}

// getCniOptions returns the available CNI options
func (o *OptionsMenu) GetCniOptions() []string {
	var cniOptions []string

	if len(o.Cnis.Calico.Versions) > 0 {

		cniOptions = append(cniOptions, "Calico")

	}

	if len(o.Cnis.Flannel.Versions) > 0 {

		cniOptions = append(cniOptions, "Flannel")

	}

	if len(o.Cnis.Cilium.Versions) > 0 {

		cniOptions = append(cniOptions, "Cilium")

	}

	if len(o.Cnis.Custom.Versions) > 0 {

		cniOptions = append(cniOptions, "Custom CNI")

	}

	return cniOptions
}

// GetCNIPaletteValue returns the raw Palette value for the Kubernetes distro
func GetCNIPaletteValue(value string) (string, error) {

	var output string

	switch value {
	case "Calico", "calico", "CALICO":
		output = "calico"
	case "Flannel", "flannel", "FLANNEL":
		output = "flannel"
	case "Cilium", "cilium", "CILIUM":
		output = "cilium"
	case "Custom CNI", "custom cni", "CUSTOM CNI":
		output = "custom"
	default:
		return "", fmt.Errorf("invalid CNI value: %s", value)
	}

	return output, nil
}

// getCniVersionOptions returns the available CNI version options for a given CNI
func (o *OptionsMenu) GetCniVersionOptions(cni string) []string {
	var cniVersions []string

	str := strings.ToLower(cni)

	if str == "calico" {
		for _, calico := range o.Cnis.Calico.Versions {
			cniVersions = append(cniVersions, calico.Version)
		}
	}

	if str == "flannel" {
		for _, flannel := range o.Cnis.Flannel.Versions {
			cniVersions = append(cniVersions, flannel.Version)
		}
	}

	if str == "cilium" {
		for _, cilium := range o.Cnis.Cilium.Versions {
			cniVersions = append(cniVersions, cilium.Version)
		}
	}

	if str == "custom cni" {
		for _, custom := range o.Cnis.Custom.Versions {
			cniVersions = append(cniVersions, custom.Version)
		}
	}

	return cniVersions
}

// GetPackUIDs returns the pack and registry UID for a given Kubernetes distro and version
// The return values are  the PackUID and RegistryUID in that order
func (o *OptionsMenu) GetPackUIDs(name, version string) (string, string) {

	var packUID, registryUID string

	lname := strings.ToLower(name)

	if lname == "k3s" {
		for _, v := range o.Kubernetes.Edgek3S.Versions {
			if v.Version == version {
				packUID = v.UID
			}
		}
		registryUID = o.Kubernetes.Edgek3S.RegistryUID
	}

	if lname == "k8s" || lname == "kubeadm" {
		for _, v := range o.Kubernetes.EdgeK8S.Versions {
			if v.Version == version {
				packUID = v.UID
			}
		}
		registryUID = o.Kubernetes.EdgeK8S.RegistryUID
	}

	if lname == "microk8s" {
		for _, v := range o.Kubernetes.EdgeMicrok8S.Versions {
			if v.Version == version {
				packUID = v.UID
			}
		}
		registryUID = o.Kubernetes.EdgeMicrok8S.RegistryUID
	}

	if lname == "rke2" {
		for _, v := range o.Kubernetes.EdgeRke2.Versions {
			if v.Version == version {
				packUID = v.UID
			}
		}
		registryUID = o.Kubernetes.EdgeRke2.RegistryUID
	}

	if lname == "calico" {
		for _, v := range o.Cnis.Calico.Versions {
			if v.Version == version {
				packUID = v.UID
			}
		}
		registryUID = o.Cnis.Calico.RegistryUID
	}

	if lname == "cilium" {
		for _, v := range o.Cnis.Cilium.Versions {
			if v.Version == version {
				packUID = v.UID
			}
		}
		registryUID = o.Cnis.Cilium.RegistryUID
	}

	if lname == "custom cni" {
		for _, v := range o.Cnis.Custom.Versions {
			if v.Version == version {
				packUID = v.UID
			}
		}
		registryUID = o.Cnis.Custom.RegistryUID
	}

	if lname == "flannel" {
		for _, v := range o.Cnis.Flannel.Versions {
			if v.Version == version {
				packUID = v.UID
			}
		}
		registryUID = o.Cnis.Flannel.RegistryUID
	}

	if lname == "ubuntu" {
		for _, v := range o.OperatingSystems.Ubuntu.Versions {
			if v.Version == version {
				packUID = v.UID
			}
		}
		registryUID = o.OperatingSystems.Ubuntu.RegistryUID
	}

	if lname == "opensuse" || lname == "opensuse-leap" {
		for _, v := range o.OperatingSystems.OpenSuSE.Versions {
			if v.Version == version {
				packUID = v.UID
			}
		}
		registryUID = o.OperatingSystems.OpenSuSE.RegistryUID
	}

	if lname == "byoos" || name == "edge-native-byoi" {
		for _, v := range o.OperatingSystems.EdgeNativeByoi.Versions {
			if v.Version == version {
				packUID = v.UID
			}
		}
		registryUID = o.OperatingSystems.EdgeNativeByoi.RegistryUID
	}

	return packUID, registryUID

}

// The UserProvidedOptions holds the options provided by the user
type UserSelections struct {
	// The CLI wizard mode
	Mode wizardMode
	// BYOOSVersion is the BYOOS version
	BYOOSVersion string
	// KubernetesDistro is the Kubernetes distribution
	KubernetesDistro string
	// KubernetesVersion is the Kubernetes version
	KubernetesVersion string
	// OperatingSystemDistro is the operating system distribution
	OperatingSystemDistro string
	// OperatingSystemVersion is the operating system version
	OperatingSystemVersion string
	// CNI is the Container Network Interface (CNI)
	CNI string
	// CNIVersion is the Container Network Interface (CNI) version
	CNIVersion string
	// PaletteEdgeInstallerVersion is the Palette Edge Installer version
	PaletteEdgeInstallerVersion string
	// CreateClusterProfile is a flag to create a cluster profile
	CreateClusterProfile bool
	// ClusterProfileName is the suffix to append to the name of a cluster profile
	ClusterProfileSuffix string
	// ImageRegistryURL is the URL of the image registry
	ImageRegistryURL string
	//ImageRegistryRepository is the repository of the image registry
	ImageRegistryRepository string
	// ImageRegistryUsername is the username of the image registry
	ImageRegistryUsername string
	// ImageRegistryPassword is the password of the image registry
	ImageRegistryPassword string
	// ImageRegistryToken is the token of the image registry
	ImageRegistryToken string
	// TenantRegistrationToken for the Edge host
	TenantRegistrationToken string
	// ISOName is the name of the ISO file
	ISOName string
	// CustomTag is the custom tag to use for the provider images
	CustomTag string
	// Platform is the platform to use for the provider images
	Platform string
}

type wizardMode int

const (
	Demo wizardMode = iota
	Normal
)

// String returns the string representation of the wizard mode
func (m wizardMode) String() string {

	switch m {
	case Demo:
		return "Demo"
	case Normal:
		return "Normal"
	default:
		return "Unknown"
	}

}

// GetWizardMode returns the wizard mode based on the int provided
func GetWizardMode(n int) wizardMode {
	switch n {
	case 0:
		return Demo
	case 1:
		return Normal
	default:
		return Normal
	}
}

// GetWizardModeFromStr returns the wizard mode based on the string provided
func GetWizardModeFromStr(s string) wizardMode {

	str := strings.ToLower(s)

	switch str {
	case "demo":
		return Demo
	case "normal":
		return Normal
	default:
		return Normal
	}
}

// Cluster Profile Struct
type ClusterProfile struct {
	Metadata MetadataCP `json:"metadata"`
	Spec     SpecCP     `json:"spec"`
}
type AnnotationsCP struct {
	Description string `json:"description"`
}
type LabelsCP struct {
	CreatedBy string `json:"createdBy"`
	Type      string `json:"type"`
}
type MetadataCP struct {
	Name        string        `json:"name"`
	Annotations AnnotationsCP `json:"annotations"`
	Labels      LabelsCP      `json:"labels"`
}
type ParametersCP struct {
	InputParameters  []string `json:"inputParameters"`
	OutputParameters []string `json:"outputParameters"`
}
type TemplatePacks struct {
	Parameters ParametersCP `json:"parameters"`
}
type PacksCP struct {
	RegistryUID string        `json:"registryUid"`
	Name        string        `json:"name"`
	Tag         string        `json:"tag"`
	Values      string        `json:"values"`
	PackUID     string        `json:"packUid"`
	Logo        string        `json:"logo"`
	Template    TemplatePacks `json:"template"`
	Manifests   []string      `json:"manifests"`
	Type        string        `json:"type"`
	UID         string        `json:"uid"`
}
type SpecTemplate struct {
	CloudType string    `json:"cloudType"`
	Type      string    `json:"type"`
	Packs     []PacksCP `json:"packs"`
}
type SpecCP struct {
	Template SpecTemplate `json:"template"`
	Version  string       `json:"version"`
}

type PaletteAPIError struct {
	Code    string      `json:"code"`
	Details interface{} `json:"details"`
	Message string      `json:"message"`
	Ref     string      `json:"ref"`
}

// MashallClusterProfile marshalls the ClusterProfile struct into a JSON string.
func (cp *ClusterProfile) mashallClusterProfile() (string, error) {

	output, err := json.MarshalIndent(cp, " ", "  ")
	if err != nil {
		return "", err
	}

	return string(output), nil
}

type CreateClusterProfileResponse struct {
	UID string `json:"uid"`
}

// RegistryAuthConfig holds the authentication configuration for the image registry
type RegistryAuthConfig struct {
	// Username is the username to use for authentication with the registry
	Username string
	// Password is the password to use for authentication with the registry. This could also be a token.
	Password string
}

// getEncodedAuth gets the encoded authentication configuration
func (r *RegistryAuthConfig) GetEncodedAuth() (string, error) {
	authConfigBytes, err := json.Marshal(r)
	if err != nil {
		return "", err
	}

	return base64.URLEncoding.EncodeToString(authConfigBytes), nil
}

// The configuration file for creating the Edge artifacts
type ConfigFile struct {
	// Config is the configuration details for creating the Edge artifacts.
	Config *ConfigDetails `yaml:"config"`
}

type ConfigDetails struct {
	// Software is the software configuration for the Edge host
	Software *SoftwareDetails `yaml:"software" validate:"required,dive"`
	// RegistryConfig is the registry configuration for uploading the provider images
	RegistryConfig *RegistryConfigDetails `yaml:"registryConfig" validate:"required,dive"`
	// Palette contains the credentials for the Palette API
	Palette *PaletteDetails `yaml:"palette" validate:"dive"`
	// EdgeInstaller contains the tenant registration token for the Edge host and the version of the Palette Edge Installer
	EdgeInstaller *EdgeInstallerDetails `yaml:"edgeInstaller" validate:"required,dive"`
	// ClusterProfile contains the cluster profile details
	ClusterProfile *ClusterProfileDetails `yaml:"clusterProfile" validate:"required,dive"`
	// Select the target platform for the provider images
	Platform *string `yaml:"platform" validate:"required,oneof=linux/amd64"`
	// CustomTag is the custom tag to use for the provider images
	CustomTag *string `yaml:"customTag" validate:"required"`
}

type SoftwareDetails struct {
	OsDistro                         *string `yaml:"osDistro" validate:"required"`
	OsVersion                        *string `yaml:"osVersion" validate:"required"`
	KubernetesDistro                 *string `yaml:"kubernetesDistro" validate:"required"`
	ContainerNetworkInterface        *string `yaml:"containerNetworkInterface" validate:"required_with=CreateClusterProfile"`
	ContainerNetworkInterfaceVersion *string `yaml:"containerNetworkInterfaceVersion" validate:"required_with=ContainerNetworkInterface CreateClusterProfile"`
}

type RegistryConfigDetails struct {
	// RegistryURL is the URL of the image registry. This can be a public or private registry. Example: docker.io, ttl.sh, myDockerHub/myRepo
	RegistryURL *string `yaml:"registryURL" validate:"required"`
	// Empty values allowed for public registries.
	RegistryUsername *string `yaml:"registryUsername" validate:"alphanum"`
	// Empty values allowed for public registries.
	RegistryPassword *string `yaml:"registryPassword"`
}

type PaletteDetails struct {
	ApiKey      *string `yaml:"apiKey" validate:"alphanum"`
	ProjectID   *string `yaml:"projectID" validate:"alphanum"`
	PaletteHost *string `yaml:"paletteHost" validate:"url"`
}

type EdgeInstallerDetails struct {
	TenantRegistrationToken *string `yaml:"tenantRegistrationToken" validate:"required,alphanum"`
	InstallerVersion        *string `yaml:"installerVersion" validate:"required,semver"`
	IsoImageName            *string `yaml:"isoImageName"`
}

type ClusterProfileDetails struct {
	CreateClusterProfile *bool   `yaml:"createClusterProfile" validate:"boolean"`
	Suffix               *string `yaml:"suffix" validate:"alphanum,required_with=CreateClusterProfile"`
}

// Validate validates the configuration file
func (c *ConfigFile) Validate() error {

	if c.Config == nil {
		return errors.New("a config block is required")
	}

	if c.Config.Software == nil {
		return errors.New("a software block is required")
	}

	if c.Config.Software.OsDistro == nil {
		return errors.New("an osDistro is required")
	}

	if c.Config.Software.OsVersion == nil {
		return errors.New("an osVersion is required")
	}

	if c.Config.Software.KubernetesDistro == nil {
		return errors.New("a kubernetesDistro is required")
	}

	if c.Config.Software.ContainerNetworkInterface == nil {
		return errors.New("a containerNetworkInterface is required")
	}

	if c.Config.Software.ContainerNetworkInterfaceVersion == nil {
		return errors.New("a containerNetworkInterfaceVersion is required")
	}

	if c.Config.RegistryConfig == nil {
		return errors.New("a registryConfig block is required")
	}

	if c.Config.RegistryConfig.RegistryURL == nil {
		return errors.New("a registryURL is required")
	}

	if c.Config.RegistryConfig.RegistryUsername == nil {
		return errors.New("a registryUsername is required")
	}

	if c.Config.RegistryConfig.RegistryPassword == nil {
		return errors.New("a registryPassword is required")
	}

	if c.Config.EdgeInstaller == nil {
		return errors.New("an edgeInstaller block is required")
	}

	if c.Config.EdgeInstaller.InstallerVersion == nil {
		return errors.New("an installerVersion is required")
	}

	if c.Config.EdgeInstaller.TenantRegistrationToken == nil {
		return errors.New("a tenantRegistrationToken is required")
	}

	if c.Config.EdgeInstaller.IsoImageName == nil {
		return errors.New("an isoImageName is required")
	}

	if c.Config.ClusterProfile == nil {
		return errors.New("a clusterProfile block is required")
	}

	if c.Config.ClusterProfile.CreateClusterProfile == nil {
		return errors.New("a createClusterProfile is required")
	}

	if c.Config.ClusterProfile.Suffix == nil {
		return errors.New("a suffix is required")
	}

	if c.Config.Platform == nil {
		return errors.New("a platform is required")
	}

	if c.Config.CustomTag == nil {
		return errors.New("a customTag is required")
	}

	return nil
}
