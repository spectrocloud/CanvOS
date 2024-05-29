# Kairos RHEL 8 and RHEL 9 images

To build the image provide username and password for Red Hat Subscription Manager to register the system and install packages during the build process.

To build RHEL 8 Kairos Image, execute:
```
docker build -t <local-registry>/<image>:<image-tag> --build-arg USERNAME=<RHSM username> --build-arg PASSWORD='<RHSM password>' -f Dockerfile.rhel8 .
```

To build RHEL 9 Kairos Image, execute:
```
docker build -t <local-registry>/<image>:<image-tag> --build-arg USERNAME=<RHSM username> --build-arg PASSWORD='<RHSM password>' -f Dockerfile.rhel9 .
```