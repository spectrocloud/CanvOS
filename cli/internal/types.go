package internal

import "time"

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
	OsName              string `json:"osName"`
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
	Kubernetes       OptionsKubernetes       `json:"kubernetes"`
	OperatingSystems OptionsOperatingSystems `json:"operating_systems"`
	Cnis             OptionsCNIs             `json:"cnis"`
}
type OptionsKubernetes struct {
	Edgek3S      []string `json:"edge-k3s"`
	EdgeK8S      []string `json:"edge-k8s"`
	EdgeMicrok8S []string `json:"edge-microk8s"`
	EdgeRke2     []string `json:"edge-rke2"`
}
type OptionsOperatingSystems struct {
	EdgeNativeByoi []string `json:"edge-native-byoi"`
	Ubuntu         []string `json:"edge-native-ubuntu"`
	OpenSuSE       []string `json:"edge-native-opensuse"`
}
type OptionsCNIs struct {
	Calico  []string `json:"calico"`
	Flannel []string `json:"flannel"`
}
