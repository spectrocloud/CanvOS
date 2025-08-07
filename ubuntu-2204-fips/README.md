# Kairos Ubuntu focal fips

- Edit `pro-attach-config.yaml` with your token
- run `bash build.sh [<base image>]`
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
    extra_cmdline: "fips=1"
```

Notes:
- Most of the Dockerfile configuration are: packages being installed by Ubuntu, and the framework files coming from Kairos containing FIPS-enabled packages

## Verify FIPS is enabled

After install, you can verify that fips is enabled by running:

```bash
kairos@localhost:~$ cat /proc/sys/crypto/fips_enabled
1
kairos@localhost:~$ uname -r
5.15.0-145-fips 
```
