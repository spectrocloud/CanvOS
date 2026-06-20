# Installer Debug Menu & Log Collection

A field-debugging aid for CanvOS / Palette Edge installer ISOs.

When an install fails at a customer site, the default installer often reboots or
drops to a console with no usable diagnostics, and the most useful logs only
exist *if you re-run the install with verbose debug flags enabled*. This feature
adds a single, fully-automatic debug boot entry that does exactly that.

> **Scope:** This iteration covers **GRUB / non-UKI ISOs** (`IS_UKI=false`, the
> default). UKI / secure-boot ISOs are a documented follow-up (their cmdline is
> baked into a signed UKI and cannot be edited at boot — debug entries must be
> generated at build time via `enki`).

---

## How to use it (at the edge)

1. Boot the installer ISO.
2. At the GRUB menu choose **"Palette Edge Debug Install (verbose - AUTO log
   capture)"**.
3. The screen shows a 10-second prompt: **start your serial-console capture or
   screen recording now.** (On a Dell/iDRAC use the virtual serial console; the
   entry sets `console=ttyS0,115200`.)
4. Do nothing else. The install re-runs with full debug instrumentation. If it
   fails, hangs, or drops to a blank/emergency console, logs are collected
   **automatically**:
   - If a **writable USB stick or disk** is attached, a bundle is written to
     `…/palette-debug/palette-debug-<host>-<timestamp>.tar.gz` and the exact
     path + SHA256 are printed to the console.
   - If **no writable media** is found, the bundle is printed to the console as
     base64 (between clear BEGIN/END markers) so it can be recovered from your
     recording.
5. Send the `.tar.gz` (or the decoded base64) to support.

To recover a base64-streamed bundle from a captured console log:

```bash
# paste the lines between the BEGIN/END markers into bundle.b64
base64 -d bundle.b64 > palette-debug.tar.gz
```

---

## What gets enabled (debug cmdline)

The debug entry boots the **same** installer as the default entry, but:

- removes `vga=795 nomodeset` so the console is actually visible;
- uses `console=ttyS0,115200` for serial capture;
- adds the marker **`palette.debug=1`** (this is what arms auto-collection);
- enables verbose tracing:
  `rd.debug rd.udev.debug udev.log_level=debug rd.immucore.debug systemd.log_level=debug systemd.log_target=console`;
- force-loads common storage drivers so enumeration is traced even when the
  default probe order misses them:
  `rd.driver.pre=nvme,nvme_core,ahci,megaraid_sas,mpt3sas,iscsi_tcp,libiscsi,scsi_transport_iscsi,usb_storage`
  (covers NVMe / Dell BOSS-N1, Dell BOSS-S (Marvell AHCI), PERC (megaraid_sas),
  HBA330 (mpt3sas), and iSCSI).

---

## How auto-collection works (no manual steps)

`/opt/spectrocloud/bin/collect-debug-bundle.sh` is the collector. It is triggered
by whichever of these fires first — all gated on
`ConditionKernelCommandLine=palette.debug`, so they are completely inert on a
normal (non-debug) boot:

| Trigger | Covers |
|---|---|
| `emergency.service` / `rescue.service` drop-ins | install crash / failed mount / blank screen that drops to emergency |
| `palette-debug-watchdog.timer` (`OnBootSec=8min`) | hangs / stalls that never reach a failure target |
| `kairos-agent.service` `OnFailure=` drop-in | install agent exits non-zero (best-effort; name may vary by framework build) |

The collector is **idempotent** (single-flight lock + per-boot marker), so
multiple triggers produce one bundle. It is best-effort and never blocks the
boot.

### Why this works without an initramfs/dracut module

"Install disk not found" (iSCSI / NVMe / Dell BOSS / PERC) is a **post-pivot**
failure: the live ISO boots fine from USB/virtual media, and it is
`kairos-agent` running in normal userspace that fails to enumerate the *target*
disk. So `dmesg` / journal / udev traces are all available after pivot and the
collector captures them with **no initrd changes**. The only case truly stuck in
initramfs is "cannot mount the live image itself" — for that, the verbose
console output (captured by your recording) is the diagnostic.

### What's in the bundle

Boot/cmdline/uname/modules, full + error journal, failed units, **storage
enumeration** (`lsblk -O`, `blkid`, `lspci -nnk`, `nvme list`, `iscsiadm`,
`multipath`, `/dev/disk/by-*`, storage-related dmesg), network state, hardware
inventory (`dmidecode`), and Kairos/Stylus install artifacts (`/var/log`,
`/oem`, `/run/cos`, `/run/immucore`, installer.log, rendered cloud-config).
**Secrets (tokens, pairing keys, passwords, private keys) are redacted.**

---

## Analyzing a bundle

`scripts/analyze-debug-bundle.sh` is an offline, rule-based root-cause analyzer
(coreutils + tar + grep only). Point it at a bundle:

```bash
scripts/analyze-debug-bundle.sh palette-debug-edge01-<ts>.tar.gz
```

It prints a severity-ranked list of likely root causes with evidence lines.
Current signatures: target disk not found, storage controller/driver not bound
(NVMe/BOSS/PERC/HBA/iSCSI), disk too small, immucore/sysroot failure, network/
registration unreachable, blank-screen/emergency, content-bundle extraction,
K8s provider/luet failures, kernel panic/OOM. Add a signature by copying a
`check_*` function and registering it in `main()`.

---

## Files

| Path | Role |
|---|---|
| `overlay/files-iso/boot/grub2/grub.cfg` | the debug menu entry |
| `overlay/files/opt/spectrocloud/bin/collect-debug-bundle.sh` | the collector |
| `overlay/files/etc/systemd/system/palette-debug-collector.service` | OnFailure target |
| `overlay/files/etc/systemd/system/palette-debug-watchdog.{service,timer}` | stall/hang sweep |
| `overlay/files/etc/systemd/system/{emergency,rescue}.service.d/10-palette-debug.conf` | collect before failure shell |
| `overlay/files/etc/systemd/system/kairos-agent.service.d/10-palette-debug.conf` | best-effort OnFailure |
| `scripts/analyze-debug-bundle.sh` | offline analyzer |

All overlay files are copied into the live installer rootfs by the existing
`COPY overlay/files/ /` step in the `Earthfile` `iso-image` target — **no
Earthfile or Dockerfile changes are required**, and the production (non-debug)
boot path is unchanged.

---

## Testing

Boot the built ISO under `hack/launch-qemu.sh`:

1. **No target disk attached** → exercises "install disk not found" auto-capture.
2. **Tiny disk** → install failure path.
3. **Attach a second blank disk/USB** → confirm the bundle is written and the
   path is echoed; with none attached, confirm base64 console streaming.
4. **Normal (non-debug) entry** → confirm boot is unchanged and none of the
   `palette-debug-*` units activate.

---

## Follow-ups

- **UKI / secure-boot support:** bake a signed debug-cmdline UKI entry in the
  `+build-uki-iso` target via `enki` (cmdline is measured and cannot be edited
  at boot).
- **Optional network upload:** add an opt-in `scp`/`curl` push of the bundle to
  a support endpoint when a network is available.
