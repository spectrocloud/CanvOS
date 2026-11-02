# Kairos Ubuntu FIPS

| Release | Directory | Build |
| ------- | --------- | ----- |
| 24.04 (noble), FIPS + STIG | [`24.04/`](24.04/README.md) | `docker buildx bake --allow=fs.read=.. ubuntu-24-04-fips` |
| 22.04 (jammy), FIPS + STIG | [`22.04/`](22.04/README.md) | `docker buildx bake --allow=fs.read=.. ubuntu-22-04-fips` |

Run the bake commands from `base-images/`. Both releases need an Ubuntu Pro token.
They read it from the shared `pro-attach-config.yaml` in this directory, a
git-ignored copy of `pro-attach-config.yaml.template` that you fill in
(or a file named by `UBUNTU_PRO_CONFIG`), passed to the build as a BuildKit secret.
`docker buildx bake ubuntu-fips` builds both 22.04 and 24.04. Images are tagged
`<REGISTRY>/kairos-ubuntu:<22.04|24.04>-core-<ARCH>-<MODEL>-<KAIROS_VERSION>-fips-stig`
(`-fips` only when built with `ENABLE_STIG=false`)
and are always passed to Earthly explicitly as `BASE_IMAGE`.

Use the generated base image as input in installer generation with `earthly +iso`.

## Enabling FIPS at boot

The system is not enabling FIPS by default in kernel space.

To install with `fips` you need a cloud-config file similar to this one adding `fips=1` to the boot options:

```yaml
#cloud-config

install:
  # ...
  # Set grub options
  grub_options:
    # additional Kernel option cmdline to apply
    extra_cmdline: "fips=1"
```

The LiveCD is not running in FIPS mode.

## Verify FIPS is enabled

After install, you can verify that FIPS is enabled by running:

```bash
kairos@localhost:~$ cat /proc/sys/crypto/fips_enabled
1
kairos@localhost:~$ uname -r    # a -fips kernel
```
