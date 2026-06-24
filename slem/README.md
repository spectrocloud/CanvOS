# SUSE Linux Enterprise Micro (for Rancher) 5.5 Kairos base image

Builds a Kairos base image from `registry.suse.com/suse/sle-micro/5.5:latest`.

Despite the path, that image is **"SLE Micro for Rancher 5.5"** (os-release
`ID=sle-micro-rancher`). kairos-init recognises this flavor and builds it using
the public **openSUSE Leap 15.5 OSS** repo, so **no SUSE subscription /
registration code is required**.

Two 5.5-specific fixes are applied in the `Dockerfile` before kairos-init runs:

1. Import the **SuSE Package Signing Key** (`suse-build-key.asc`) — the Leap OSS
   packages are signed with it and it is missing from this image's keyring
   (otherwise installs fail with `NOKEY`).
2. Pre-align **dracut** and install `dracut-mkinitrd-deprecated` — the base ships
   a newer dracut than Leap OSS, and the OSS kernel needs the `mkinitrd`
   capability paired with the older dracut, which zypper would otherwise refuse
   to downgrade non-interactively.

## Pre-requisites

* A host with **Docker**.
* Outbound access to `registry.suse.com`, `quay.io`, and
  `download.opensuse.org`.

## Build

```
./build.sh [<OUTPUT_TAG>]
```

Example:

```
./build.sh slem-kairos:5.5
```

`KAIROS_INIT_IMAGE`, `KAIROS_VERSION`, and `TRUSTED_BOOT` can be overridden via
`--build-arg` (see the `ARG`s in the `Dockerfile`).
