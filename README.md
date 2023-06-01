# CanvOS

CanvOS is designed to leverage the Spectro Cloud Edge Forge architecture to build edge artifacts.  These artifacts can then be used by Palette for building edge clusters with little to no touch by end users.

With CanvOS, we leverage Earthly to build all of the artifacts required for edge deployments.  From the installer iso to the Kubernetes Provider images, CanvOS makes it simple for you to build the images customized to your needs.  

The base image definitions reside in the Earthfile located in this repo.  This defines all of the elements that are required for building the artifacts that can be used by Palette for edge deployments.  If customized packages need to be added, simply add the reference to the Dockerfile as you would for any Docker image.  When the build command is run, the Earthfile will merge those custom packages into the final image.  For a quickstart tutorial see the Knowledgebase section of the Spectro Cloud Docs.  There you will find a quickstart tutorial for building your first CanvOS artifacts.

<h1 align="center">
  <br>
     <img alt="Edge Components" src="https://raw.githubusercontent.com/spectrocloud/CanvOS/main/images/edge_components.png">
    <br>
<br>

## Image Build Architecture

### Base Image

From the Kairos project, this is derived from the operating system distribution chosen (currently Ubuntu and OpenSuse-Leap supported).  It is pulled down as the base image and some adjustments are made to better support Palette.  Those adjustments are used to clean and update the image as well as install some required packages.

### Provider Image

From the Base Image, the provider image is used to package in the Kubernetes distribution and version(s) that are part of the build.  This layer is required to initialize the system and prepare it for configuration to build the Kubernetes cluster.

### Installer Image

From the base image, this image is used to provide the initial flashing of a device (bare-metal or virtual machine).  This image contains the user-data configuration that has been provided in `user-data`.  It will also contain the contents of any content bundle for pre-staged builds.  Pre-staged builds can be used to embed all of the artifacts that are required to build a cluster.  These artifacts include Helm charts, manifests, and container images.  These images are loaded into containerd when the cluster is initialized elminating the need for the initial download.  For more information on how to build pre-loaded content checkout the Palette Docs at [Build your Own Content](https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/build-content-bundle).  

### Custom Configuration

For advanced use cases, there may be a need to add additional packages not included in the [Base Images](https://github.com/kairos-io/kairos/tree/master/images).  If those packages or configuration elements need to be added, they can be included in the empty `Dockerfile` located in this repo and they will be included in the build process and output artifacts.

### Basic Usage

1. Clone the repo at [CanvOS](https://github.com/spectrocloud/CanvOS.git)

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
```

4. Checkout the desired tag

```shell
git checkout <tag version>
```

**Sample Output**

```shell
git checkout v3.4.1
Note: switching to 'v3.4.1'.

You are in 'detached HEAD' state. You can look around, make experimental
changes and commit them, and you can discard any commits you make in this
state without impacting any branches by switching back to a branch.

If you want to create a new branch to retain commits you create, you may
do so (now or later) by using -c with the switch command. Example:
```
<<<<<<< HEAD
5. Copy the .arg.template file to .arg

```shell
cp .arg.template .arg
```

6. Modify the `.arg` file as needed. Primarily, you must define the tag you want to use for your images. For example, if the operating system is `ubuntu` and the tag is `demo`, the image artefact will name as `ttl.sh/ubuntu:k3s-1.25.2-v3.4.1-demo`. The **.arg** file defines the following variables:
=======

5. Modify the `.arg` file as needed. Primarily, you must define the tag you want to use for your images. For example, if the operating system is `ubuntu` and the tag is `demo`, the image artefact will name as `ttl.sh/ubuntu:k3s-1.25.2-v3.4.1-demo`. The **.arg** file defines the following variables:
>>>>>>> 8a06bb0 (Initial Commit)

| Parameter        | Description                                                                                                                             | Type   | Default Value          |
|------------------|-----------------------------------------------------------------------------------------------------------------------------------------|--------|------------------------|
| CUSTOM_TAG       | Environment name for provider image tagging. The default value is `demo`.                                                                | String | `demo`                 |
| IMAGE_REGISTRY   | Image registry name that will store the image artifacts. The default value points to the *ttl.sh* image registry, an anonymous and ephemeral Docker image registry where images live for a maximum of 24 hours by default. If you wish to make the images exist longer than 24 hours, you can use any other image registry to suit your needs. | String | `ttl.sh`               |
| OS_DISTRIBUTION  | OS distribution of your choice. For example, it can be `ubuntu` or `opensuse-leap`.                                                     | String | `ubuntu`               |
| IMAGE_REPO       | Image repository name in your chosen registry.                                                                                          | String | `$OS_DISTRIBUTION`     |
| OS_VERSION       | OS version. For Ubuntu, the possible values are `20`, and `22`. Whereas for openSUSE Leap, the possible value is `15.4`. This example uses `22` for Ubuntu.                                         | String | `22`                   |
| K8S_DISTRIBUTION | Kubernetes distribution name. It can be one of these: `k3s`, `rke2`, or `kubeadm`.                                                       | String | `k3s`                  |
| ISO_NAME         | Name of the Edge installer ISO image. In this example, the name is *palette-edge-installer*.                                             | String | `palette-edge-installer`|

<<<<<<< HEAD
7. Build the images with the following command. Use the `system.uri` output when creating the cluster profile for the Edge host.
=======



6. Build the images with the following command. Use the `system.uri` output when creating the cluster profile for the Edge host.
>>>>>>> 8a06bb0 (Initial Commit)
  
```shell
./earthly.sh +build-all-images --PE_VERSION=$(git describe --abbrev=0 --tags)
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
system.peVersion: v3.4.0
system.customTag: demo
system.osVersion: 22
```
<<<<<<< HEAD

8. Validate the expected artifacts are created, the ISO image and the provider OS images.
=======
  
  
7. Validate the expected artifacts are created, the ISO image and the provider OS images.
>>>>>>> 8a06bb0 (Initial Commit)
  
```shell
ls build/ && docker images

palette-edge-installer.iso      
palette-edge-installer.iso.sha256  

# Output
REPOSITORY        TAG                       IMAGE ID        CREATED         SIZE
ttl.sh/ubuntu     k3s-1.25.2-v3.4.1-demo    b3c4956ccc0a    6 minutes ago   2.49GB
ttl.sh/ubuntu     k3s-1.24.7-v3.4.1-demo    fe1486da25df    6 minutes ago   2.49GB
earthly/earthly   v0.7.4                    d771cc8edc38     2 weeks ago    333MB
```

<<<<<<< HEAD
9. The provider images are by default not pushed to a registry. You can push the images by using the `docker push` command and reference the created imgages. 
=======
8. The provider images are by default not pushed to a registry. You can push the images by using the `docker push` command and reference the created imgages. 
>>>>>>> 8a06bb0 (Initial Commit)

```shell
docker push ttl.sh/ubuntu-demo:k3s-v1.25.2-v3.4.1 && \
docker push ttl.sh/ubuntu-demo:k3s-v1.24.7-v3.4.1
```

> ⚠️ The default registry, [ttl.sh](https://ttl.sh/) is a short-lived registry. Images in the ttl.sh registry have a default time to live of
24 hours. Once the time limit is up, the images will automatically be removed. To use a permanent registry, set the `.arg` file's `IMAGE_REGISTRY` parameter with the URL of your image registry.
 
  
<<<<<<< HEAD
10. Create a cluster profile using the command output. Use the [Model Edge Cluster Profile](https://docs.spectrocloud.com/clusters/edge/site-deployment/model-profile) to help you complete this step.
  

11. Flash VM or Baremetal device with the generated ISO. Refer to the [Prepare Edge Host for Installation](https://docs.spectrocloud.com/clusters/edge/site-deployment/stage) guide for additonal guidance.


12. Register the Edge host with Palette. Checkout the [Register Edge Host](https://docs.spectrocloud.com/clusters/edge/site-deployment/site-installation/edge-host-registration) guide.


13. Build a cluster in [Palette](https://console.spectrocloud.com). 
=======
9. Create a cluster profile using the command output. Use the [Model Edge Cluster Profile](https://docs.spectrocloud.com/clusters/edge/site-deployment/model-profile) to help you complete this step.
  

10. Flash VM or Baremetal device with the generated ISO. Refer to the [Prepare Edge Host for Installation](https://docs.spectrocloud.com/clusters/edge/site-deployment/stage) guide for additonal guidance.


10. Register the Edge host with Palette. Checkout the [Register Edge Host](https://docs.spectrocloud.com/clusters/edge/site-deployment/site-installation/edge-host-registration) guide.


11. Build a cluster in [Palette](https://console.spectrocloud.com). 
>>>>>>> 8a06bb0 (Initial Commit)

### How-Tos

* [Building Edge Native Artifacts]([https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/palette-canvos](https://deploy-preview-1318--docs-spectrocloud.netlify.app/clusters/edge/edgeforge-workflow/palette-canvos))

