# SUSE Linux Enterprise Micro (SLE Micro 5.5) Kairos base image

Builds a Kairos base image from `registry.suse.com/suse/sle-micro/5.5:latest`.

There is no "SLE Micro for Rancher" 5.5 image (that flavor stopped at 5.4), so we
use the standard SLE Micro 5.5 image and register it against SCC at build time to
pull the version-matched SLE 15 SP5 repos. Mixing in older openSUSE Leap packages
instead leads to kernel/dracut/mkinitrd conflicts, so registration is required.

## Pre-requisites

* A host with **Docker (with BuildKit)** — it does **not** need to be a SLE Micro
  host. Registration happens inside the container build.
* A valid **SUSE registration code** (trial codes work).
* Outbound network access to `scc.suse.com` and `registry.suse.com`.

## Build

```
./build.sh <REGISTRATION_CODE> [<OUTPUT_TAG>]
```

Example:

```
./build.sh 1234567890 slem-kairos:5.5
```

The registration code is passed to the build as a BuildKit secret and the
subscription is deregistered + scrubbed at the end, so neither the code nor the
SCC credentials remain in the resulting image.

## Notes

* `KAIROS_INIT_IMAGE`, `KAIROS_VERSION`, and `TRUSTED_BOOT` can be overridden via
  `--build-arg` (see the `ARG`s in the `Dockerfile`).
* `PackageHub/15.5/x86_64` is registered in addition to the base product because
  some packages kairos-init installs (e.g. `htop`, `nethogs`, `iw`) live there.
