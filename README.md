# CanvOS

CanvOS is designed to leverage the Spectro Cloud Edge Forge architecture to build edge artifacts.  These artifacts can then be used by Palette for building edge clusters with little to no touch by end users.

With CanvOS, we leverage Earthly to build all of the artifacts required for edge deployments.  From the installer iso to the Kubernetes Provider images, CanvOS makes it simple for you to build the images customized to your needs.  

The base image definitions reside in the Earthfile located in this repo.  This defines all of the elements that are required for building the artifacts that can be used by Palette for edge deployments.  If customized packages need to be added, simply add the reference to the Dockerfile as you would for any Docker image.  When the build command is run, the Earthfile will merge those custom packages into the final image.  For a quickstart tutorial see the Knowledgebase section of the Spectro Cloud Docs.  There you will find a quickstart tutorial for building your first CanvOS artifacts.

<h1 align="center">
  <br>
     <img alt="CanvOS Flow" src="https://raw.githubusercontent.com/spectrocloud/CanvOS/main/images/CanvOS.png">
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
git https://github.com/spectrocloud/CanvOS.git
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
```

```shell
v3.3.3
```

4. Checkout the desired tag

```shell
git checkout <tag version>
```

**Sample Output**

```shell
git checkout v3.3.3
Note: switching to 'v3.3.3'.

You are in 'detached HEAD' state. You can look around, make experimental
changes and commit them, and you can discard any commits you make in this
state without impacting any branches by switching back to a branch.

If you want to create a new branch to retain commits you create, you may
do so (now or later) by using -c with the switch command. Example:
```

5. Modify the `.arg` file as needed

**SAMPLE OUTPUT FOR IMAGE TAGS**  
`ttl.sh/ubuntu-demo:k3s-1.25.2-v3.3.3`

6. Build the images
```shell
./earthly.sh +build-all-images --PE_VERSION=$(git describe --abbrev=0 --tags)
```

8. The output can be used to populate your cluster profile in Palette.

9. Flash VM or Baremetal device with the generated ISO.

10. Build clusters in [Palette](https://console.spectrocloud.com)

### How-Tos

* [Building Edge Native Artifacts](https://docs.spectrocloud.com/knowledgebase/how-to/edge-native/edgeforge)

### Tutorials
