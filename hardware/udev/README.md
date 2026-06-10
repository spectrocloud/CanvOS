# Hardware udev Rules

Vendor-specific and NVMe persistent-naming udev rules shipped inside every CanvOS image.

These rules create stable `/dev` symlinks that survive reboots regardless of NVMe
enumeration order (`nvme0`, `nvme1`, `nvme2` ordering is not guaranteed by the kernel).
Users can set `install.device` in their cloud-config to one of these stable paths.

## Included rules

| File | Hardware | Stable symlink | Validated |
|------|----------|----------------|-----------|
| `99-dell-boss.rules` | Dell BOSS-N1 / BOSS-S1 (VXRail, PowerEdge) | `/dev/boss-os` | Yes — Kyle Jepson, Loves Energy |
| `99-hpe-nvme.rules` | HPE NS204i-p / NS204i-r (ProLiant Gen10+/Gen11) | `/dev/hpe-boot-os` | Needs hardware validation |
| `99-nvme-persistent.rules` | Any NVMe without a wwid/eui in firmware | `/dev/disk/by-id/nvme-<serial>-ns<id>` | Generic fallback |

## Adding rules for new hardware

1. Boot a live Ubuntu environment on the target node.
2. Run `udevadm info --name=/dev/nvmeXn1 --attribute-walk` and find a matchable attribute
   (`ATTRS{model}`, `ATTRS{vendor}`, `ATTRS{serial}`, etc.).
3. Add a new `.rules` file here following the naming convention `7X-<vendor>-<product>.rules`.
4. Copy it into the image in the Dockerfile:
   ```dockerfile
   COPY hardware/udev/ /etc/udev/rules.d/
   ```
5. Rebuild the image. The rules are also pulled into the initrd by dracut via the
   `--install` flag added to the dracut invocation.

## Testing a rule without rebuilding

On a running node:
```bash
udevadm test /sys/block/nvme0n1
udevadm trigger --name-match=nvme0n1
ls -la /dev/boss-os   # or whichever symlink the rule creates
```
