# Configuration File Specifications

### ConfigDetails
| Parameter | Description | Required |
|-----------|-------------|----------|
| software | The software configuration for the Edge host | Yes |
| registryConfig | The registry configuration for uploading the provider images | Yes |
| palette | The credentials for the Palette API | No |
| edgeInstaller | The tenant registration token for the Edge host and the version of the Palette Edge Installer | Yes |
| clusterProfile | The cluster profile details | Yes |
| platform | Select the target platform for the provider images | Yes |
| customTag | The custom tag to use for the provider images | Yes |

### SoftwareDetails
| Parameter | Description | Required |
|-----------|-------------|----------|
| osDistro | Operating system distribution | Yes |
| osVersion | Operating system version | Yes |
| kubernetesDistro | Kubernetes distribution | Yes |
| containerNetworkInterface | Container network interface | Yes, if `CreateClusterProfile` is true |
| containerNetworkInterfaceVersion | Container network interface version | Yes, if `CreateClusterProfile` and `ContainerNetworkInterface` are true |

### RegistryConfigDetails
| Parameter | Description | Required |
|-----------|-------------|----------|
| registryURL | Registry URL | Yes |
| registryUsername | Registry Username. Empty values allowed for public registries. | No |
| registryPassword | Registry Password. Empty values allowed for public registries. | No |

### PaletteDetails
| Parameter | Description | Required |
|-----------|-------------|----------|
| apiKey | API key | No |
| projectID | Project ID | No |
| paletteHost | Palette Host URL | No |

### EdgeInstallerDetails
| Parameter | Description | Required |
|-----------|-------------|----------|
| tenantRegistrationToken | Tenant Registration Token | Yes |
| installerVersion | Installer Version | Yes |
| isoImageName | ISO Image Name | No |

### ClusterProfileDetails
| Parameter | Description | Required |
|-----------|-------------|----------|
| createClusterProfile | Create Cluster Profile | No |
| suffix | Suffix | Yes, if `CreateClusterProfile` is true |

# Example Configuration

```yaml
config:
  # The foundation software distributions and versions to use for the  Edge host
  # All the supported Kubernetes versions will be created by default.
  software:
    # Allowed values are: ubuntu, opensuse-leap 
    osDistro: ubuntu
    osVersion: 16.04
    # Allowed values are: k3s, rke2, kubeadm
    # kubeadm is the equivalent of Palette eXtended Kubernetes - Edge (PXK -E)
    kubernetesDistro: kubeadm
    containerNetworkInterface: calico
    containerNetworkInterfaceVersion: 0.12.5
  # The registry configuration values to use when uploading the provider images
  registryConfig:
    registryURL: myUsername/edge
    # Empty values allowed for public registries
    registryUsername: myUsername
    # Empty values allowed for public registries
    registryPassword: superSecretPassword

  # Palette credentials and project ID. If the project ID is not provided, then the default scope is Tenant.
  palette:
    apiKey: 1234567890
    projectID: 1234567890
    paletteHost: https://api.spectrocloud.com

  # The Edge Installer configuration values to use when creating the Edge Installer ISO
  edgeInstaller:
    tenantRegistrationToken: 1234567890
    installerVersion: 3.4.3
    isoImageName: palette-learn

  # The Cluster Profile configuration values to use when creating the Cluster Profile
  clusterProfile:
    createClusterProfile: true
    # The suffix is part of the cluster profile name. The name format is: edge-<suffix>-<YYYY-MM-DD>-<SHA-256>
    suffix: learn

  # Allowed values: linux/amd64
  platform: linux/amd64
  # The custom tag to apply to the provider images. 
  # The provider images name follow the format: <kubernetesDistro>-<k8sVersion>-v<installerVersion>-<customTag>_<platform>
  customTag: palette-learn
```