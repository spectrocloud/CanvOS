#!/usr/bin/env bash
# trim-gpu-firmware.sh — drop AMD/NVIDIA GPU firmware (+ matching DRM modules)
# from a Kairos Ubuntu rootfs to keep UKI size under the ~1 GiB UEFI limit.
#
# Workaround until Ubuntu splits linux-firmware (LP#1958518):
#   https://bugs.launchpad.net/ubuntu/+source/linux-firmware/+bug/1958518
#
# Env:
#   KEEP_GPU_FIRMWARE=true  — no-op (keep full set)
set -euo pipefail

KEEP_GPU_FIRMWARE="${KEEP_GPU_FIRMWARE:-false}"

if [ "${KEEP_GPU_FIRMWARE}" = "true" ]; then
    echo "[trim-gpu-firmware] KEEP_GPU_FIRMWARE=true — leaving AMD/NVIDIA firmware in place"
    mkdir -p /etc/canvos
    cat > /etc/canvos/uki-gpu-firmware-policy <<EOF
kept
reason=KEEP_GPU_FIRMWARE=true (opt-in full linux-firmware GPU set)
removed_firmware_paths=0
removed_module_trees=0
keep_gpu_firmware=true
kept_gpu_vendors=nvidia,amdgpu
EOF
    exit 0
fi

echo "[trim-gpu-firmware] Removing AMD/NVIDIA GPU firmware (LP#1958518 workaround)"

# Firmware may live under /lib/firmware and/or /usr/lib/firmware (often the same
# tree via symlink on Noble). Deduplicate by realpath so we only walk once.
fw_roots=()
seen_roots=""
for d in /lib/firmware /usr/lib/firmware; do
    [ -d "$d" ] || continue
    real="$(readlink -f "$d" 2>/dev/null || echo "$d")"
    case " ${seen_roots} " in
        *" ${real} "*) continue ;;
    esac
    seen_roots="${seen_roots} ${real}"
    fw_roots+=("$real")
done

# Vendor trees that belong to discrete AMD/NVIDIA GPUs. Do NOT touch:
#   amd-ucode / intel-ucode (CPU), amd/ (SEV), i915, NIC/wifi, etc.
gpu_fw_names=(
    nvidia
    amdgpu
)

removed_fw=0
for root in "${fw_roots[@]}"; do
    for name in "${gpu_fw_names[@]}"; do
        # Exact vendor dir first, then any name-* siblings if present.
        for path in "${root}/${name}" "${root}/${name}"-*; do
            if [ -e "$path" ] || [ -L "$path" ]; then
                echo "[trim-gpu-firmware]   rm -rf $path"
                rm -rf "$path"
                removed_fw=$((removed_fw + 1))
            fi
        done
    done
done

# In-tree DRM modules for those GPUs (smaller than firmware, but useless without
# matching blobs and still contribute to UKI size).
removed_mod=0
for kver_dir in /lib/modules/*; do
    [ -d "$kver_dir" ] || continue
    for rel in \
        kernel/drivers/gpu/drm/amd \
        kernel/drivers/gpu/drm/nouveau
    do
        path="${kver_dir}/${rel}"
        if [ -e "$path" ]; then
            echo "[trim-gpu-firmware]   rm -rf $path"
            rm -rf "$path"
            removed_mod=$((removed_mod + 1))
        fi
    done
    if command -v depmod >/dev/null 2>&1; then
        kver="$(basename "$kver_dir")"
        depmod -a "$kver" || true
    fi
done

mkdir -p /etc/canvos
cat > /etc/canvos/uki-gpu-firmware-policy <<EOF
trimmed
reason=LP#1958518 linux-firmware still monolithic; UKI ~1GiB UEFI limit
removed_firmware_paths=${removed_fw}
removed_module_trees=${removed_mod}
keep_gpu_firmware=false
EOF

echo "[trim-gpu-firmware] Done (firmware paths touched=${removed_fw}, module trees=${removed_mod})"
echo "[trim-gpu-firmware] Marker: /etc/canvos/uki-gpu-firmware-policy"
