# CanvOS

CanvOS is designed to leverage the Spectro Cloud Edge Forge architecture to build edge artifacts.  These artifacts can then be used by Palette for building edge clusters with little to no touch by end users.

With CanvOS, we leverage Earthly to build all of the artifacts required for edge deployments.  From the installer iso to the Kubernetes Provider images, CanvOS makes it simple for you to build the images customized to your needs.  

The base image definitions reside in the Earthfile located in this repo.  This defines all of the elements that are required for building the artifacts that can be used by Palette for edge deployments.  If customized packages need to be added, simply add the reference to the Dockerfile as you would for any Docker image.  When the build command is run, the Earthfile will merge those custom packages into the final image.  For a quickstart tutorial see the Knowledgebase section of the Spectro Cloud Docs.  There you will find a quickstart tutorial for building your first CanvOS artifacts.

<h1 align="center">
  <br>
     <img alt="CanvOS Flow" src="https://raw.githubusercontent.com/spectrocloud/CanvOS/main/images/CanvOS.png">
    <br>
<br>

## Knowledgebase

### How-Tos

* [Building Edge Native Artifacts](https://docs.spectrocloud.com/knowledgebase/how-to/edge-native/edgeforge)

### Tutorials

