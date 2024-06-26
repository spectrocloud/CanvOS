# Kairos RHEL 8 and RHEL 9 images

## Build the image using Red Hat Subscription

Follow steps below to execute the build process on the host with access to Red Hat Subscription Management system (redhat.com) and by using Red Hat username and password.

To build the image provide username and password for Red Hat Subscription Manager to register the system and install packages during the build process.

To build RHEL 8 Kairos Image, execute:
```
docker build -t <local-registry>/<image>:<image-tag> --build-arg USERNAME=<RHSM username> --build-arg PASSWORD='<RHSM password>' -f Dockerfile.rhel8.
```

To build RHEL 9 Kairos Image, execute:
```
docker build -t <local-registry>/<image>:<image-tag> --build-arg USERNAME=<RHSM username> --build-arg PASSWORD='<RHSM password>' -f Dockerfile.rhel9 .
```

**In case of any errors during package installation steps - these errors might be caused by previous build attempts. Execute `docker build` command again by providing argument `--no-cache` to build the image from scratch**

## Build the image using Red Hat Satellite and mirrored repositories

This scenario is for the environment where Red Hat Satellite must be used and access to public Red Hat repositories is not possible. For this case use Dockerfiles `Dockerfile.rhel9.sat` and `Dockerfile.rhel8.sat` - these files are modified to use Red Hat Satellite Activation key to register host and install all required packages.

### Prerequisites

1. Mirror base RHEL UBI image (`registry.access.redhat.com/ubi9-init:9.4-6`) to the internal Container registry. Provide image path for the build process by using argument `BASE_IMAGE`. 

2. Mirror Kairos framework image (`quay.io/kairos/framework:v2.7.41`) to the internal Container registry. Provide image path for the build process by using argument `KAIROS_FRAMEWORK_IMAGE`. 

3. Have the following repostiories synced and available on Red Hat Satellite:

For RHEL9:
* rhel-9-for-x86_64-appstream-rpms
* rhel-9-for-x86_64-baseos-rpms
* EPEL9 (upstream URL https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/)

For RHEL8:
* rhel-8-for-x86_64-appstream-rpms
* rhel-8-for-x86_64-baseos-rpms
* EPEL8 (upstream URL https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/)


4. Create Activation Key in RH Satellite and add corresponding repositories listed above. Make these repositories enabled by default (set `Override Enabled` for these repositories in the Activation Key configuration). Provide Activation Key for the build process by using argument `KEYNAME`.

### Build the image

After all prerequisites completed, ensure all required build arguments are in place:

BASE_IMAGE - path to RHEL8/9 UBI image, for example `redhat.spectrocloud.dev/ubi9-init:9.4-6`

KAIROS_FRAMEWORK_IMAGE - path to Kairos framework image, for example `quay.spectrocloud.dev/kairos/framework:v2.7.33`

SATHOSTNAME - Red Hat Satellite hostname, for example `katello.spectrocloud.dev`

ORGNAME - Organization name in Red Hat Satellite, for example `test-org`

KEYNAME - Name of the Activation key with repositories attached, for example `rhel9-canvos-key`

To build RHEL 8 Kairos Image, execute:
```
docker build -t <local-registry>/<image>:<image-tag> --build-arg BASE_IMAGE=<base image path> --build-arg KAIROS_FRAMEWORK_IMAGE='<Kairos Framework Path>' --build-arg SATHOSTNAME=<Satellite hostname>  --build-arg ORGNAME=<Satellite Org Name> --build-arg KEYNAME=<Activation key name> -f Dockerfile.rhel8.sat .
```

To build RHEL 9 Kairos Image, execute:
```
docker build -t <local-registry>/<image>:<image-tag> --build-arg BASE_IMAGE=<base image path> --build-arg KAIROS_FRAMEWORK_IMAGE='<Kairos Framework Path>' --build-arg SATHOSTNAME=<Satellite hostname>  --build-arg ORGNAME=<Satellite Org Name> --build-arg KEYNAME=<Activation key name> -f Dockerfile.rhel9.sat .
```

For example, to build RHEL9 image:
```
docker build -t localhost/palette-rhel9:latest --build-arg BASE_IMAGE=redhat.spectrocloud.dev/ubi9-init:9.4-6 --build-arg KAIROS_FRAMEWORK_IMAGE=quay.spectrocloud.dev/kairos/framework:v2.7.33 --build-arg SATHOSTNAME=katello.spectrocloud.dev  --build-arg ORGNAME=test-org --build-arg KEYNAME=rhel9-canvos-key -f Dockerfile.rhel9.sat .
```

For example, to build RHEL8 image:
```
docker build -t localhost/palette-rhel8:latest --build-arg BASE_IMAGE=redhat.spectrocloud.dev/ubi8/ubi-init:8.7-10 --build-arg KAIROS_FRAMEWORK_IMAGE=quay.spectrocloud.dev/kairos/framework:v2.7.33 --build-arg SATHOSTNAME=katello.spectrocloud.dev  --build-arg ORGNAME=test-org --build-arg KEYNAME=rhel8-canvos-key -f Dockerfile.rhel8.sat .
```



