# kdump and pstore on Ubuntu 24.04 images

This guide explains how to turn on kernel crash dumps (kdump) on a Palette Edge host built from a CanvOS
Ubuntu 24.04 image, how to change its settings, and how to read what a crash leaves behind. It also covers
pstore, which keeps the kernel log of crashes that kdump does not capture.

- kdump files: [`overlay/kdump/ubuntu/`](../overlay/kdump/ubuntu/), wired into the `base-image` target in the
  [`Earthfile`](../Earthfile) through the `KDUMP_UBUNTU` command.
- pstore file: [`overlay/pstore/`](../overlay/pstore/).

**Supported images:** Ubuntu **24.04**, `amd64`, GRUB boot, not FIPS, STIG, CIS-hardened or Trusted Boot (UKI).
kdump is not installed in those four kinds of image. FIPS, STIG and CIS images still get the pstore setting.

| | kdump | pstore |
|---|---|---|
| What it keeps | A filtered, compressed copy of kernel memory (`dump.<time>`) and the kernel log (`dmesg.<time>`) | The last ~25 KB of the kernel log |
| Where | `/usr/local/kdump/<YYYYmmddHHMM>/` on the persistent partition | The system journal (identifier `systemd-pstore`) |
| Turned on by | `crashkernel=` in the install user data; off by default | Nothing: on wherever the firmware supports it |
| Costs | 512 MB to 4 GB of reserved memory, and disk space | Nothing |

## Enable kdump

kdump is switched on by reserving memory for the capture kernel. Add the `crashkernel=` argument to
`install.grub_options.extra_cmdline` in the user data of the host:

```yaml
#cloud-config
install:
  grub_options:
    extra_cmdline: "crashkernel=2G-4G:512M,4G-32G:512M,32G-64G:1024M,64G-128G:2048M,128G-:4096M"
```

The argument is stored in `/oem/grubenv`, so kdump is armed on every boot afterwards. Nothing is reserved on a host
that does not carry the argument.

To enable it on a host that is already installed:

```bash
# keep any other extra arguments in the same value
sudo grub2-editenv /oem/grubenv list | grep extra_cmdline
sudo grub2-editenv /oem/grubenv set extra_cmdline="crashkernel=2G-4G:512M,4G-32G:512M,32G-64G:1024M,64G-128G:2048M,128G-:4096M"
sudo reboot
```

Check that it is armed:

```bash
cat /sys/kernel/kexec_crash_size     # bytes reserved; 0 means kdump is off
cat /sys/kernel/kexec_crash_loaded   # 1: the capture kernel is loaded
sudo kdump-config status             # "ready to kdump"
```

Look at `kexec_crash_loaded` or `kdump-config status`, not at the state of `kdump-tools.service`: if the reserved
memory is too small for the capture kernel, loading fails but the service still reports success.

`systemctl is-enabled kdump-tools` prints `disabled` on these images. The unit is enabled through a link under
`/usr/lib/systemd/system`, which that command does not count, and it is still started at every boot. Do not use it as
a check, and do not use `systemctl disable` to turn kdump off: it has no effect. Remove `crashkernel=` instead.

## Disable kdump

Remove the `crashkernel=` argument and reboot. If `extra_cmdline` holds other arguments, set it again without
`crashkernel=` instead of unsetting it:

```bash
sudo grub2-editenv /oem/grubenv list | grep extra_cmdline
sudo grub2-editenv /oem/grubenv unset extra_cmdline      # only when crashkernel= was the only argument
sudo reboot
```

No memory is reserved afterwards and `kdump-tools.service` is skipped with
`kdump-merge: kdump off: no crash kernel memory reserved`. Existing dumps stay in `/usr/local/kdump`.

## Sizing

| Host RAM | Memory reserved |
|---|---|
| Less than 2 GB | None: kdump stays off |
| 2 GB to 32 GB | 512 MB |
| 32 GB to 64 GB | 1 GB |
| 64 GB to 128 GB | 2 GB |
| 128 GB or more | 4 GB |

- A host with exactly 32 GB of RAM falls in the 32-64 GB band.
- The 2-4 GB band reserves 512 MB, where Ubuntu's own default is 320 MB: the capture kernel is started from a generic
  initrd that assembles the Kairos root, and 512 MB leaves it enough headroom.
- Reserved memory is not available to workloads. Ubuntu enables kdump by default only on hosts with at least 6 GB of
  RAM; on smaller hosts enable it only when you need full dumps.
- Disk: dumps hold kernel memory only (page cache, tmpfs, the memory of running processes and zero pages are left out),
  compressed. Memory freed shortly before the crash can still be in a dump, so treat dumps as sensitive. Expect
  65-130 MB on hosts up to 32 GB. Keep at least 1 GB free on `/usr/local` for such hosts, and more for larger ones.
  kdump-tools has no free-space check: if a save runs out of space, the kernel log is kept, the partial dump
  stays until it is removed or replaced, and the host reboots normally.

## Overrides

Three kdump-tools settings can be changed. Put them in `/etc/default/kdump-tools.override`, one `KEY=value` per line,
from a user data stage (`/etc/default` is not persistent, so the file must come from user data):

```yaml
stages:
  initramfs:
    - name: "kdump overrides"
      files:
        - path: /etc/default/kdump-tools.override
          permissions: 0644
          content: |
            KDUMP_NUM_DUMPS=2
            KDUMP_DUMP_DMESG=1
            KDUMP_CMDLINE_APPEND="loglevel=7"
```

| Setting | Allowed | Default | Meaning |
|---|---|---|---|
| `KDUMP_NUM_DUMPS` | 1-10 | 3 | Captures to keep; older ones are removed after each successful save |
| `KDUMP_DUMP_DMESG` | 0 or 1 | 1 | Also save the kernel log next to the dump |
| `KDUMP_CMDLINE_APPEND` | tokens of `A-Z a-z 0-9 _ . , : / + = -`, not starting with `=` | none | Extra capture-kernel arguments, put before the image's own |

How they are applied:

- `/etc/default/kdump-tools.default` (shipped) and the override file are merged into `/etc/default/kdump-tools` by
  `/usr/lib/kdump/kdump-merge` before each kdump-tools unit starts, in the normal boot and in the capture boot.
  `/etc/default/kdump-tools` is not in the image: it exists only while kdump is on.
- Any other key (for example `KDUMP_COREDIR`, `MAKEDUMP_ARGS`, `USE_KDUMP`) is ignored with a warning. So are capture
  arguments the image sets (`crashkernel`, `root`, `cos-img/filename`, `elfcorehdr`, `init`, `reset_devices`,
  `systemd.unit`, `nr_cpus`, `irqpoll`, `usbcore.nousb`, `kho`) and values outside the allowed range. The rest of the
  file still applies, and the file is read as data, never run.
- To see what was applied:

  ```bash
  head -2 /etc/default/kdump-tools                       # source, and any "# Rejected:" items
  sudo journalctl -b -u kdump-tools | grep kdump-merge   # applied overrides and warnings
  ```

- To try a change on a running host, edit the override file and run `sudo systemctl restart kdump-tools`. It applies
  to the next crash. Put it in user data to keep it.

## Output and retention

```
/usr/local/kdump/
  202610131230/                 capture time, YYYYmmddHHMM
    dmesg.202610131230          kernel log of the crashed kernel
    dump.202610131230           dump: flattened, compressed, makedumpfile -d 31
```

- The path and the dump level are fixed. The last `KDUMP_NUM_DUMPS` captures are kept; the oldest are removed after a
  successful save.
- Two captures in the same minute share a directory.
- A directory with `dump-incomplete` or `vmcore-incomplete`, or with only `dmesg.<time>`, is a save that did not finish
  (disk full, power loss). It counts towards the limit until later captures replace it.
- Dumps keep kernel-held data: file names, process names, mount paths, queued network data and keys held by the
  kernel. Handle them like the host's memory.

## Retrieve and analyze a dump

Copy the whole directory off the host before resetting it:

```bash
sudo tar -C /usr/local/kdump -czf /tmp/kdump-$(hostname)-<time>.tgz <time>
sudo chmod 0644 /tmp/kdump-*.tgz
# from your workstation
scp <user>@<host>:/tmp/kdump-*.tgz .
```

Delete the archive from `/tmp` afterwards: it is in memory. The kernel log is a text file and usually answers the
first question.

To analyze the dump on an x86-64 Linux workstation you need:

- **`crash` 9.0.1 or later.** Ubuntu 24.04's `crash` 8.0.4 cannot read dumps from the 7.0 kernel (it stops with
  `invalid structure member offset`). Ubuntu 26.04 ships 9.0.1.
- `makedumpfile` to convert the dump.
- The debug symbols of the host's exact kernel: the `linux-image-unsigned-<version>-dbgsym` package, about 2 GB,
  for the version shown by `uname -r` on the host.

```bash
dpkg-deb --fsys-tarfile linux-image-unsigned-<version>-dbgsym_*.ddeb | tar -x --wildcards './usr/lib/debug/boot/vmlinux-*'
makedumpfile -R vmcore < dump.<time>        # dumps are in makedumpfile's flattened format
crash ./usr/lib/debug/boot/vmlinux-<version> vmcore
# useful first commands: sys, bt, log, ps, kmem -i
```

## pstore

pstore is on wherever the firmware supports it: UEFI variables on UEFI hosts, ACPI ERST on servers that provide it.
Check the backend with `cat /sys/module/pstore/parameters/backend` (`efi_pstore` or `erst`; `(null)` means none).
Legacy BIOS virtual machines have no backend, so a crash with kdump off leaves no record there.

On a panic or an oops the kernel writes the end of its log to firmware storage, and `systemd-pstore` moves it into
the journal at the next boot. The image ships `/usr/lib/systemd/pstore.conf.d/persist.conf` (`Storage=journal`)
because the default directory, `/var/lib/systemd/pstore`, is in memory on Kairos. Trusted Boot (UKI) images keep the
default.

```bash
sudo journalctl -t systemd-pstore                                    # the archived records
sudo journalctl -b 0 -t systemd-pstore -o cat --output-fields=FILE   # kernel log of the crash before this boot, oldest part first
```

For an earlier crash use `-b -1`, `-b -2` and so on. Once archived, the firmware copy is deleted, so repeated crashes
do not fill the firmware storage.

## kdump and pstore together

When kdump is armed, a panic goes straight to the capture kernel and pstore records nothing. kdump also sets
`kernel.panic_on_oops=1` when it loads, so an oops is a panic too. pstore covers what kdump does not:

| Situation | kdump | pstore |
|---|---|---|
| kdump armed, panic or oops | dump and kernel log | nothing |
| Panic early in boot, before kdump loads | nothing | kernel log |
| Reserved memory too small, capture kernel not loaded | nothing | kernel log |
| kdump off, panic | none | kernel log |
| kdump off, oops | none | the host keeps running; the oops is in the journal |
| Disk full or power loss while saving | kernel log only | nothing |
| Panic in the recovery system | nothing (see below) | kernel log |

## Recovery system

kdump does not run in the recovery system (the one a Kairos reset boots into): it has no persistent storage, so a
capture there would be lost. `kdump-merge` detects it through `/run/cos/recovery_mode` and `kdump-tools.service` is
skipped with `kdump-merge: kdump off: recovery system (no persistent storage; pstore records panics instead)`.
The `crashkernel=` reservation still applies there, because `extra_cmdline` covers every boot entry.

## Reset and upgrade

- **Reset:** a Kairos reset formats the persistent partition, so the captures are removed. `crashkernel=` stays in
  `/oem/grubenv` and the user data stays in `/oem`, so kdump is armed again, with the same overrides, on the first
  boot after the reset. Copy dumps off the host first.
- **Upgrade:** every image carries its own kernel, capture initrd, makedumpfile and configuration, so the active slot
  always has a matching set. `crashkernel=` stays in `/oem/grubenv`.

## Limitations

- Dumps are written to the host only; sending them over SSH or NFS is not supported (the capture initrd has no
  networking).
- Only the three settings above can be changed.
- The makedumpfile in the image supports kernels up to the version recorded in
  `/usr/lib/kdump/makedumpfile-supported-kernel` (7.0.0 today). The image build fails when the kernel is newer;
  bump `MAKEDUMPFILE_SRC_VERSION` and `MAKEDUMPFILE_DSC_SHA256` of the `+makedumpfile-match` target.
- With kdump off, a crash on legacy BIOS hardware without ACPI ERST leaves no record.
