# CanvOS

CanvOS is designed to leverage the Spectro Cloud Edge Forge architecture to build edge artifacts. These artifacts can then be used by Palette for building edge clusters with little to no touch by end users.

With CanvOS, we leverage Earthly to build all of the artifacts required for edge deployments. From the installer iso to the Kubernetes Provider images, CanvOS makes it simple for you to build the images customized to your needs.

The base image definitions reside in the Earthfile located in this repo. This defines all of the elements that are required for building the artifacts that can be used by Palette for edge deployments. If customized packages need to be added, simply add the reference to the Dockerfile as you would for any Docker image. When the build command is run, the Earthfile will merge those custom packages into the final image. For a quickstart tutorial see the Knowledgebase section of the Spectro Cloud Docs. There you will find a quickstart tutorial for building your first CanvOS artifacts.

<h1 align="center">
  <br>
     <img alt="Edge Components" src="https://raw.githubusercontent.com/spectrocloud/CanvOS/main/images/edge_components.png">
    <br>
<br>

## Image Build Architecture

### Base Image

From the Kairos project, this is derived from the operating system distribution chosen (currently Ubuntu and OpenSuse-Leap supported). It is pulled down as the base image and some adjustments are made to better support Palette. Those adjustments are used to clean and update the image as well as install some required packages.

### Provider Image

From the Base Image, the provider image is used to package in the Kubernetes distribution and version(s) that are part of the build. This layer is required to initialize the system and prepare it for configuration to build the Kubernetes cluster.

### Installer Image

From the base image, this image is used to provide the initial flashing of a device (bare-metal or virtual machine). This image contains the user-data configuration that has been provided in `user-data`. It will also contain the contents of any content bundle for pre-staged builds. Pre-staged builds can be used to embed all of the artifacts that are required to build a cluster. These artifacts include Helm charts, manifests, and container images. These images are loaded into containerd when the cluster is initialized eliminating the need for the initial download. For more information on how to build pre-loaded content checkout the Palette Docs at [Build your Own Content](https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/build-content-bundle).

### Custom Configuration

For advanced use cases, there may be a need to add additional packages not included in the [Base Images](https://github.com/kairos-io/kairos/tree/master/images). If those packages or configuration elements need to be added, they can be included in the empty `Dockerfile` located in this repo and they will be included in the build process and output artifacts.

### Custom Hardware Specs Lookup

A custom hardware specs lookup file can be provided to extend or override the default GPU specifications. This is useful for adding custom hardware entries or overriding default specifications.

#### Location

Place the custom lookup file at:
```
overlay/files/usr/local/spectrocloud/custom-hardware-specs-lookup.json
```

This file will be copied to `/usr/local/spectrocloud/custom-hardware-specs-lookup.json` in the final image.

#### Configuration

The file must be a valid JSON array. These entries will be merged with the default hardware specs lookup table, with the custom entries taking precedence for matching `vendorID` and `deviceID` combinations.

#### Sample Entry

Here's an example entry structure:

```json
[
  {
    "marketingName": "NVIDIA Quadro RTX 6000",
    "vRAM": 24,
    "migCapable": false,
    "vendor": "NVIDIA",
    "vendorID": "10de",
    "deviceID": [
      "1e36",
      "1e78"
    ],
    "architecture": "Turing"
  }
]
```

#### Field Descriptions

| Field | Description | Example |
|-------|-------------|---------|
| `marketingName` | Display name for the hardware | `"NVIDIA Quadro RTX 6000"` |
| `vRAM` | Video RAM in GB (decimal) | `24` |
| `migCapable` | Whether Multi-Instance GPU is supported (for NVIDIA GPUs) | `false` |
| `vendor` | Vendor name | `"NVIDIA"`, `"AMD"`, `"Intel"` |
| `vendorID` | PCI vendor ID in hexadecimal (lowercase) | `"10de"` |
| `deviceID` | Array of PCI device IDs in hexadecimal (can have multiple IDs for same model) | `["1e36", "1e78"]` |
| `architecture` | GPU architecture name | `"Turing"`, `"Ampere"`, `"Hopper"`, `"Blackwell"` |

#### Usage

There are two ways to provide the custom hardware specs lookup file:

##### Method 1: During CanvOS Build (Recommended for Pre-staged Images)

1. Create the file at `overlay/files/usr/local/spectrocloud/custom-hardware-specs-lookup.json`
2. Add custom entries as a JSON array
3. Build the images - the custom lookup file will be included automatically
4. Custom entries will override default entries for matching `vendorID`+`deviceID` combinations

##### Method 2: Via user-data (Runtime Configuration)

The custom hardware specs lookup file can be provided via user-data using the `initramfs.after` stage (recommended) or `boot` or `boot.after` stage.

Add the following to the `user-data` file (replace the example entry with actual hardware specs):

```yaml
#cloud-config
stages:
  initramfs.after:
    - files:
        - path: "/usr/local/spectrocloud/custom-hardware-specs-lookup.json"
          permissions: 0644
          owner: 0
          group: 0
          content: |
            [
              {
                "marketingName": "NVIDIA Quadro RTX 6000",
                "vRAM": 24,
                "migCapable": false,
                "vendor": "NVIDIA",
                "vendorID": "10de",
                "deviceID": [
                  "1e36",
                  "1e78"
                ],
                "architecture": "Turing"
              }
            ]
      name: "Configure custom hardware specs lookup"
```

### Basic Usage

1. Clone the repo at [CanvOS](https://github.com/spectrocloud/CanvOS.git)

Note: If you are building the images behind a proxy server, you may need to configure your git to let it use your proxy server.

```
git config --global http.proxy <your-proxy-server>
git config --global https.proxy <your-proxy-server>
git config --global http.sslCAinfo <your-cert-path>
git config --global https.sslCAinfo <your-cert-path>
# git config --global http.sslVerify False
# git config --global https.sslVerify False
```

```shell
git clone https://github.com/spectrocloud/CanvOS.git
```

**Sample Output**

```shell
Cloning into 'CanvOS'...
remote: Enumerating objects: 133, done.
remote: Counting objects: 100% (133/133), done.
remote: Compressing objects: 100% (88/88), done.
Receiving objects: 100% (133/133), 40.16 KiB | 5.02 MiB/s, done.
Resolving deltas: 100% (60/60), done.
remote: Total 133 (delta 60), reused 101 (delta 32), pack-reused 0
```

2. Change into the `CanvOS` directory that was created.

```shell
cd CanvOS
```

3. View Available tags

```shell
git tag

v3.3.3
v3.4.0
v3.4.1
v3.4.3

v4.1.0
v4.2.3

v4.5.11
```

4. Checkout the desired tag

> **Note:** If you have a dedicated or on-prem instance of Palette, identify the correct agent version and checkout the corresponding tag. For example, if your agent version is v4.6.16, checkout tag v4.6.16.
>
> ```shell
> curl --location --request GET 'https://<palette-endpoint>/v1/services/stylus/version' --header 'Content-Type: application/json' --header 'Apikey: <api-key>'  | jq --raw-output '.spec.latestVersion.content | match("version: ([^\n]+)").captures[0].string'
> # Sample Output
> v4.6.16
>
> ```

```shell
git checkout <tag version>
```

**Sample Output**

```shell
git checkout v4.2.3
Note: switching to 'v4.2.3'.

You are in 'detached HEAD' state. You can look around, make experimental
changes and commit them, and you can discard any commits you make in this
state without impacting any branches by switching back to a branch.

If you want to create a new branch to retain commits you create, you may
do so (now or later) by using -c with the switch command. Example:
```

1. Copy the .arg.template file to .arg

```shell
cp .arg.template .arg
```

6. To build RHEL core, RHEL FIPS or Ubuntu fips, sles base images switch to respective directories and build the base image.
   The base image built can be passed as argument to build the installer and provider images.
   Follow the instructions in the respective sub-folders (rhel-fips, ubuntu-fips) to create base images.
   For ubuntu-fips, this image can be used as base image - `gcr.io/spectro-images-public/ubuntu-fips:v3.0.11`
   Skip this step if your base image is ubuntu or opensuse-leap. If you are building ubuntu or opensuse-leap installer images, do not pass the BASE_IMAGE attribute as an arg to build command.

7. Modify the `.arg` file as needed. Primarily, you must define the tag you want to use for your images. For example, if the operating system is `ubuntu` and the tag is `demo`, the image artefact will name as `ttl.sh/ubuntu:k3s-1.25.2-v3.4.3-demo`. The **.arg** file defines the following variables:

| Parameter                   | Description                                                                                                                                                                                                                                                                                                                                    | Type    | Default Value              |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | -------------------------- |
| CUSTOM_TAG                  | Environment name for provider image tagging. The default value is `demo`.                                                                                                                                                                                                                                                                      | String  | `demo`                     |
| IMAGE_REGISTRY              | Image registry name that will store the image artifacts. The default value points to the _ttl.sh_ image registry, an anonymous and ephemeral Docker image registry where images live for a maximum of 24 hours by default. If you wish to make the images exist longer than 24 hours, you can use any other image registry to suit your needs. | String  | `ttl.sh`                   |
| OS_DISTRIBUTION             | OS distribution of your choice. For example, it can be `ubuntu`, `opensuse-leap`, `rhel` or `sles`                                                                                                                                                                                                                                             | String  | `ubuntu`                   |
| IMAGE_REPO                  | Image repository name in your chosen registry.                                                                                                                                                                                                                                                                                                 | String  | `$OS_DISTRIBUTION`         |
| OS_VERSION                  | OS version. For Ubuntu, the possible values are `20`, and `22`. Whereas for openSUSE Leap, the possible value is `15.6`. For sles, possible values are `5.4`. This example uses `22` for Ubuntu.                                                                                                                                               | String  | `22`                       |
| K8S_DISTRIBUTION            | Kubernetes distribution name. It can be one of these: `k3s`, `rke2`, `kubeadm`, `kubeadm-fips`, or `nodeadm`.                                                                                                                                                                                                                                  | String  | `k3s`                      |
| ISO_NAME                    | Name of the Edge installer ISO image. In this example, the name is _palette-edge-installer_.                                                                                                                                                                                                                                                   | String  | `palette-edge-installer`   |
| ARCH                        | Type of platform to use for the build. Used for Cross Platform Build (arm64 to amd64 as example).                                                                                                                                                                                                                                              | string  | `amd64`                    |
| BASE_IMAGE                  | Base image to be used for building installer and provider images.                                                                                                                                                                                                                                                                              | String  |                            |
| FIPS_ENABLED                | to generate FIPS compliant binaries. `true` or `false`                                                                                                                                                                                                                                                                                         | string  | `false`                    |
| HTTP_PROXY                  | URL of the HTTP Proxy server to be used if needed (Optional)                                                                                                                                                                                                                                                                                   | string  |                            |
| HTTPS_PROXY                 | URL of the HTTPS Proxy server to be used if needed (Optional)                                                                                                                                                                                                                                                                                  | string  |                            |
| NO_PROXY                    | URLS that should be excluded from proxying (Optional)                                                                                                                                                                                                                                                                                          | string  |                            |
| UPDATE_KERNEL               | Determines whether to upgrade the Kernel version to the latest from the upstream OS provider                                                                                                                                                                                                                                                   | boolean | `false`                    |
| DISABLE_SELINUX             | Disable selinux in the operating system. Some applications (like Kubevirt) do not like selinux                                                                                                                                                                                                                                                 | boolean | `true`                     |
| CLUSTERCONFIG               | Path of the cluster config                                                                                                                                                                                                                                                                                                                     | string  |                            |
| IS_UKI                      | Build UKI(Trusted boot) images                                                                                                                                                                                                                                                                                                                 | boolean | `false`                    |
| UKI_BRING_YOUR_OWN_KEYS     | Bring your own public/private key pairs if this is set to true. Otherwise, CanvOS will generate the key pair.                                                                                                                                                                                                                                  | boolean | `false`                    |
| INCLUDE_MS_SECUREBOOT_KEYS  | Include Microsoft 3rd Party UEFI CA certificate in generated keys                                                                                                                                                                                                                                                                              | boolean | `true`                     |
| AUTO_ENROLL_SECUREBOOT_KEYS | Auto enroll SecureBoot keys when device boots up and is in setup mode of secure boot                                                                                                                                                                                                                                                           | boolean | `true`                     |
| EDGE_CUSTOM_CONFIG          | Path to edge custom configuration file                                                                                                                                                                                                                                                                                                         | string  | `.edge-custom-config.yaml` |
| MAAS_IMAGE_NAME             | Custom name for the final MAAS image (without .raw.gz extension). Only used when building MAAS images.                                                                                                                                                                         | string  | `kairos-ubuntu-maas`       |
| IS_MAAS                     | Build MAAS-compatible disk images. Set to `true` when building for MAAS deployment.                                                                                                                                                                                                                                                           | boolean | `false`                    |

>For use cases where UEFI installers are burned into a USB and then edge hosts are booted with the USB. Use the OSBUILDER_VERSION=0.300.4 in the .arg file with canvos when building the installer.
Version 0.300.3 does not support UEFI builds loading from USB.

> If there are certs to be added, place them in the `certs` folder.

1. (Optional) If you are building the images behind a proxy server, you may need to modify your docker daemon settings to let it use your proxy server. You can refer this [tutorial](https://docs.docker.com/config/daemon/systemd/#httphttps-proxy).

2. Build the images with the following command. Use the `system.uri` output when creating the cluster profile for the Edge host.

```shell
./earthly.sh +build-all-images --ARCH=amd64
```

To build FIPS complaint images or ARM images, specify the BASE_IMAGE and ARCH in the .arg file or as command line arguments.
`k3s` does not FIPS and rke2 is by default `FIPS` compliant.

To build just the installer image

```shell
./earthly.sh +iso --ARCH=amd64
```

To build the provider images

```shell
./earthly.sh +build-provider-images --ARCH=amd64
```

To build the fips enabled ubuntu installer image

```shell
./earthly.sh +iso --BASE_IMAGE=gcr.io/spectro-images-public/ubuntu-fips:v3.0.11 --FIPS_ENABLED=true --ARCH=amd64 --PE_VERSION=v4.4.0
```

Output

```shell
###################################################################################################

PASTE THE CONTENTS BELOW INTO YOUR CLUSTER PROFILE IN PALETTE BELOW THE "OPTIONS" ATTRIBUTE

###################################################################################################


system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"


system.registry: ttl.sh
system.repo: ubuntu
system.k8sDistribution: k3s
system.osName: ubuntu
system.peVersion: v4.2.3
system.customTag: demo
system.osVersion: 22
```

10. Validate the expected artifacts are created, the ISO image and the provider OS images.

```shell
ls build/ && docker images

palette-edge-installer.iso
palette-edge-installer.iso.sha256

# Output
REPOSITORY                                     TAG                                  IMAGE ID       CREATED        SIZE
ttl.sh/ubuntu                                  k3s-1.24.6-v4.2.3-demo               cad8acdd2797   17 hours ago   4.62GB
ttl.sh/ubuntu                                  k3s-1.24.6-v4.2.3-demo_linux_amd64   cad8acdd2797   17 hours ago   4.62GB
ttl.sh/ubuntu                                  k3s-1.25.2-v4.2.3-demo               f6e490f53971   17 hours ago   4.62GB
ttl.sh/ubuntu                                  k3s-1.25.2-v4.2.3-demo_linux_amd64   f6e490f53971   17 hours ago   4.62GB
```

Earthly is a multi-architecture build tool. In this example we are building images for AMD64 hardware which is reflected by the tags above. In the future we will support ARM64 builds and those tags will be included. We only need to push the image tag that DOES NOT have the architecture reference i.e `linux_amd64` in the above example.

11. The provider images are by default not pushed to a registry. You can push the images by using the `docker push` command and reference the created images.

```shell
docker push ttl.sh/ubuntu:k3s-1.25.2-v4.2.3-demo
```

> ⚠️ The default registry, [ttl.sh](https://ttl.sh/) is a short-lived registry. Images in the ttl.sh registry have a default time to live of
> 24 hours. Once the time limit is up, the images will automatically be removed. To use a permanent registry, set the `.arg` file's `IMAGE_REGISTRY` parameter with the URL of your image registry.

12. Create a cluster profile using the command output. Use the [Model Edge Cluster Profile](https://docs.spectrocloud.com/clusters/edge/site-deployment/model-profile) to help you complete this step.

13. Flash VM or Baremetal device with the generated ISO. Refer to the [Prepare Edge Host for Installation](https://docs.spectrocloud.com/clusters/edge/site-deployment/stage) guide for additional guidance.

14. Register the Edge host with Palette. Checkout the [Register Edge Host](https://docs.spectrocloud.com/clusters/edge/site-deployment/site-installation/edge-host-registration) guide.

15. Build a cluster in [Palette](https://console.spectrocloud.com).

### How-Tos

- [Building Edge Native Artifacts](<[https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/palette-canvos](https://deploy-preview-1318--docs-spectrocloud.netlify.app/clusters/edge/edgeforge-workflow/palette-canvos)>)

### Building ARM64 Artifacts for Nvidia Jetson devices

1. Your .arg file should contain these values

```shell
BASE_IMAGE=quay.io/kairos/ubuntu:20.04-core-arm64-nvidia-jetson-agx-orin-v2.4.3
ARCH=arm64
platform=linux/arm64
```

2. `./earthly.sh +build-all-images`

### Prepare keys for Trusted Boot

1. In .arg, we have these options to configure the key generation for Trusted Boot.

```
UKI_BRING_YOUR_OWN_KEYS=false # set to true if you want to to use your own public/private key pairs to generate SecureBoot keys
INCLUDE_MS_SECUREBOOT_KEYS=true # if you want to include Microsoft 3rd Party UEFI CA certificate in generated keys
```

2. Copy required keys into secure-boot directory. It should look like this:

```shell
secure-boot/
|   enrollment
|   exported-keys <-- keys exported from hardware
|   |   db
|   |   KEK
|   private-keys <-- Will be used if UKI_BRING_YOUR_OWN_KEYS=true, otherwise CanvOS will generate the keys
|   |   db.key
|   |   KEK.key
|   |   PK.key
|   |   tpm2-pcr-private.pem
|   public-keys <-- Will be used if UKI_BRING_YOUR_OWN_KEYS=true, otherwise CanvOS will generate the keys
|   |   db.pem
|   |   KEK.pem
|   |   PK.pem
```

3. Generate keys for Trusted Boot

```shell
./earthly.sh +uki-genkey --MY_ORG="ACME Corp" --EXPIRATION_IN_DAYS=5475
```

### Build Trusted Boot Images

1. Your .arg file should contain these values.

```shell
IS_UKI=true
AUTO_ENROLL_SECUREBOOT_KEYS=false # Auto enroll SecureBoot keys when device boots up and is in setup mode of secure boot
```

2. `./earthly.sh +build-all-images`

### Building MAAS Images

MAAS (Metal as a Service) is Canonical's bare-metal provisioning tool. CanvOS can build MAAS-compatible disk images in `dd.gz` format that can be uploaded directly to MAAS for deployment.

#### Prerequisites

- MAAS image builds only support Ubuntu (OS_DISTRIBUTION must be set to `ubuntu`)
- The build process requires privileged mode (handled automatically by `earthly.sh`)

#### Configuration

1. In your `.arg` file, ensure the following settings:

```shell
OS_DISTRIBUTION=ubuntu
OS_VERSION=22  # or 20, 24, etc.
ARCH=amd64
```

2. (Optional) Set a custom name for the MAAS image:

```shell
MAAS_IMAGE_NAME=my-custom-maas-image
```

If not specified, the default name will be `kairos-ubuntu-maas`. The final output will be in `dd.gz` format (e.g., `my-custom-maas-image.raw.gz`).

#### Building the MAAS Image

Run the following command to build the MAAS image:

```shell
./earthly.sh +maas-image
```

The build process consists of two steps:
1. **Step 1**: Generates the Kairos raw disk image from the installer image
2. **Step 2**: Creates a composite MAAS image that includes:
   - Kairos OS partitions (EFI, OEM, Recovery)
   - Ubuntu root filesystem for MAAS deployment
   - Curtin hooks for MAAS integration
   - Cloud-init scripts for post-deployment configuration

#### Output

After a successful build, you will find the compressed MAAS image in the `build/` directory:

```shell
ls build/

my-custom-maas-image.raw.gz
my-custom-maas-image.raw.gz.sha256
```

The output includes:
- **Compressed disk image** (`.raw.gz`): The MAAS-compatible disk image in `dd.gz` format
- **SHA256 checksum** (`.sha256`): Checksum file for verification

#### Uploading to MAAS

1. Upload the `.raw.gz` file to MAAS as a custom image:
   - Go to MAAS UI → Images → Custom Images
   - Click "Upload custom image"
   - Select the `.raw.gz` file
   - Specify format as `dd.gz`
   - MAAS will automatically decompress the image during upload

2. The image is now ready to be deployed to bare-metal servers via MAAS.

#### Image Contents

The MAAS image includes:
- **Content bundles**: Pre-staged container images and artifacts (if provided during build)
- **Cluster config (SPC)**: Cluster definition files (if `CLUSTERCONFIG` is set in `.arg`)
- **Local UI**: Local management interface (if `local-ui.tar` is provided)
- **Curtin hooks**: Custom installation hooks for MAAS deployment
- **Cloud-init integration**: Automatic userdata processing and recovery mode boot

#### Troubleshooting

- **Build fails with "OS_DISTRIBUTION is not set"**: Ensure `OS_DISTRIBUTION=ubuntu` is set in your `.arg` file
- **Build fails with "OS_DISTRIBUTION is not ubuntu"**: MAAS images only support Ubuntu. Change `OS_DISTRIBUTION` to `ubuntu` in your `.arg` file
- **Image not found after build**: Check that the build completed successfully and look for the `.raw.gz` file in the `build/` directory

### Building with private registry

1. Make sure you have logged into your registry using docker login
2. In .arg, add following entries

```shell
SPECTRO_LUET_REPO=reg.xxx.com
SPECTRO_PUB_REPO=reg.xxx.com
KAIROS_BASE_IMAGE_URL=reg.xxx.com
```

3. Make sure you have following images and your base image retagged to your repo

```shell
gcr.io/spectro-images-public/earthly/earthly:v0.8.5 to reg.xxx.com/earthly/earthly:v0.8.5
gcr.io/spectro-images-public/earthly/buildkitd:v0.8.5 to reg.xxx.com/earthly/buildkitd:v0.8.5
gcr.io/spectro-images-public/canvos/alpine-cert:v1.0.0 to reg.xxx.com/canvos/alpine-cert:v1.0.0
gcr.io/spectro-images-public/osbuilder-tools:v0.7.11 to reg.xxx.com/osbuilder-tools:v0.7.11
gcr.io/spectro-images-public/stylus-framework-linux-amd64:v4.3.2 to reg.xxx.com/stylus-framework-linux-amd64:v4.3.2
gcr.io/spectro-images-public/kairos-io/provider-kubeadm:v4.3.1 to reg.xxx.com/kairos-io/provider-kubeadm:v4.3.1
gcr.io/spectro-images-public/kairos-io/provider-k3s:v4.2.1 to reg.xxx.com/kairos-io/provider-k3s:v4.2.1
gcr.io/spectro-images-public/kairos-io/provider-rke2:v4.1.1 to reg.xxx.com/kairos-io/provider-rke2:v4.1.1
```

4. Prepare luet auth config

```shell
cp spectro-luet-auth.yaml.template spectro-luet-auth.yaml
# modify serveraddess, username and password in spectro-luet-auth.yaml to yours
```

5. Build the image using earthly installed on the host

```shell
earthly --push +build-all-images
```

### Building Installer Image with public key for verifying signed content

1. Copy the .edge.custom-config.yaml.template file to .edge.custom-config.yaml

```shell
cp .edge.custom-config.yaml.template .edge.custom-config.yaml
```

2. Edit the property signing.publicKey in `.edge.custom-config.yaml`

3. Include the following property in `.arg` file

```
...

EDGE_CUSTOM_CONFIG=/path/to/.edge.custom-config.yaml
```

4. Build the image using earthly installed on the host

```shell
earthly --push +build-all-images
```

### Audit Logs User Customisation

#### Configuration

rsyslog config file: `overlay/files/etc/rsyslog.d/49-stylus.conf` copied to `/etc/rsyslog.d/49-stylus.conf`
logrotate config file: `overlay/files/etc/logrotate.d/stylus.conf` copied to `/etc/logrotate.d/stylus.conf`

#### Send stylus audit events to user file

Users can log stylus audit events to additional files, in addition to `/var/log/stylus-audit.log`. To log stylus audit events to custom files, create a configuration file in the `overlay/files/etc/rsyslog.d` directory named `<filename>.conf` (must be before `49-stylus.conf` lexicographically).

Example: `48-audit.conf`

Users can use the following configuration as a base for their filtering logic. replace `<log file name>` with the desired file name

```
$PrivDropToUser root
$PrivDropToGroup root
if ($syslogfacility-text == 'local7' and $syslogseverity-text == 'notice' and $syslogtag contains 'stylus-audit') then {
    action(
        type="omfile"
        file="<log file name>"
    )
}
```

#### Send user application audit events to stylus audit file

To include user application audit events in the `/var/log/stylus-audit.log` file, add the following to the same configuration file (e.g. `48-audit.conf`) or create a new config file before `49-stylus.conf`:

`<user app name>` : user application name or tag

```
$PrivDropToUser root
$PrivDropToGroup root
$Umask 0000
$template ForwardFormat,"<%pri%>1 %timestamp:::date-rfc3339% %HOSTNAME% %syslogtag% %procid% - - %msg%\n"
if ($syslogfacility-text == 'local7' and $syslogseverity-text == 'notice' and $syslogtag contains '<user app name>') then {
    action(
        type="omfile"
        file="/var/log/stylus-audit.log"
        FileCreateMode="0600"
        fileowner="root"
        template="ForwardFormat"
    )
}
```

To display user audit entries on the Local UI dashboard, audit entries must be logged in RFC 5424 format with the message (`msg`) part in JSON format. This JSON message must include the following keys: `edgeHostId`, `contentMsg`, `action`, `actor`, `actorType`, `resourceId`, `resourceName`, `resourceKind`

Example syslog entry

```
<189>1 2024-07-23T15:35:32.644461+00:00 edge-ce0a38422e4662887313fb673bbfb2a2 stylus-audit[2911]: 2911 - - {"edgeHostId":"edge-ce0a38422e4662887313fb6 73bbfb2a2","contentMsg":"kairos password reset failed","action":"activity","actor":"kairos","actorType":"user","resourceId":"kairos","resourceName":"kairos","resourceKind":"user"}
```

Entries without these keys in the MSG part of RFC 5424 will still be logged to the stylus-audit.log file but will not be displayed on LocalUI.
