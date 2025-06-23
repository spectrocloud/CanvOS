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


- use the generated base image as input in installer generation with `earthly +iso`

The system is not enabling FIPS by default in kernel space. 

To Install with `fips` you need a cloud-config file similar to this one adding `fips=1` to the boot options:

```yaml
#cloud-config

install:
  # ...
  # Set grub options
  grub_options:
    # additional Kernel option cmdline to apply
    extra_cmdline: "fips=1 selinux=0"
```

Notes:
- Most of the Dockerfile configuration are: packages being installed by fedora, and the framework files coming from Kairos containing FIPS-enabled packages
- The LiveCD is not running in fips mode
- You must add `selinux=0`. SELinux is not supported yet and must be explicitly disabled

## Verify FIPS is enabled

After install, you can verify that fips is enabled by running:

```bash
kairos@localhost:~$ cat /proc/sys/crypto/fips_enabled
1
kairos@localhost:~$ uname -a
Linux localhost 5.4.0-1007-fips #8-Ubuntu SMP Wed Jul 29 21:42:48 UTC 2020 x86_64 x86_64 x86_64 GNU/Linux
```
