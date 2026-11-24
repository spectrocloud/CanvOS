# kdump for Ubuntu images

Installed by the kdump block in the `Earthfile` on Ubuntu 24.04 amd64 images that are not FIPS, CIS or UKI. The pstore setting
is separate, in `overlay/pstore/`.

* `etc/`, `usr/` — copied to `/etc` and `/usr`: kdump-tools defaults, `kdump-merge`, unit drop-ins.
* `build-kdump.sh` — image-build step: checks that the defaults are in the image and that makedumpfile supports the image
  kernel, builds the dracut capture initrd,
  enables kdump-tools.service, removes the package's `/etc/default/kdump-tools`, and fails the build if the result could not
  produce a dump.

Turn kdump on per host with `crashkernel=` in `install.grub_options.extra_cmdline`.

Configuration:
* `/etc/default/kdump-tools.default` — image defaults (shipped).
* `/etc/default/kdump-tools.override` — operator overrides, KEY=value (`KDUMP_NUM_DUMPS`, `KDUMP_DUMP_DMESG`,
  `KDUMP_CMDLINE_APPEND`), written by a yip `files:` entry in the `initramfs` stage.
* `/etc/default/kdump-tools` — built by `kdump-merge` from the two above before each kdump-tools unit starts; the file
  kdump-tools reads. Not in the image. `kdump-merge` writes a plain copy of the defaults first, so if applying the overrides
  fails, kdump-tools still runs with the defaults and a capture boot still saves the dump and reboots.

Dumps are written to `/usr/local/kdump/<YYYYmmddHHMM>/`.

## Ubuntu releases

| Release | Status | makedumpfile |
|---|---|---|
| 24.04 | Enabled on amd64 (`OS_VERSION` guard inside the Earthfile's ubuntu + amd64 block) | `+makedumpfile-match`: Ubuntu's 1.7.9 source rebuilt for 24.04, supports kernels up to 7.0. The 24.04 archive package supports kernels only up to 6.8.4 |
| 22.04, 26.04 | Not enabled or validated | Would need the release's own makedumpfile check; enable by extending the `OS_VERSION` guard and running the test plan |

The files here have no release-specific content. `build-kdump.sh` fails the build when the image kernel is newer than the
makedumpfile limit recorded by `+makedumpfile-match` (`/usr/lib/kdump/makedumpfile-supported-kernel`).
