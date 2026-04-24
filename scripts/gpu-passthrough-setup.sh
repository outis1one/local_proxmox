#!/usr/bin/env bash
# Configure IOMMU + VFIO passthrough for two Quadro P2200 GPUs on Proxmox VE 9.x.
# Run on the Proxmox host. Requires a reboot to take effect.
#
# After running this script:
#   1. Reboot the host
#   2. Verify with: lspci -nnk | grep -A3 -i nvidia
#      Driver should show 'vfio-pci', not 'nouveau' or 'nvidia'
#   3. Assign GPUs to VMs via qm set or the Proxmox UI

set -euo pipefail

CMDLINE_FILE="/etc/kernel/cmdline"
MODPROBE_VFIO="/etc/modprobe.d/vfio.conf"
MODPROBE_BLACKLIST="/etc/modprobe.d/blacklist-gpu.conf"
INITRAMFS_MODULES="/etc/initramfs-tools/modules"

# ── Step 1: Check IOMMU groups ────────────────────────────────────────────────

echo "=== Current IOMMU groups (GPUs) ==="
for d in /sys/kernel/iommu_groups/*/devices/*; do
  n=${d#*/iommu_groups/*}; n=${n%%/*}
  dev=$(lspci -nns "${d##*/}" 2>/dev/null || true)
  [[ "$dev" =~ VGA|3D|Display|Audio ]] && printf 'Group %3s  %s\n' "$n" "$dev"
done
echo ""

# ── Step 2: Collect GPU PCI IDs ───────────────────────────────────────────────

echo "=== Detected NVIDIA devices ==="
lspci -nn | grep -i nvidia
echo ""

# Grab all NVIDIA PCI IDs (vendor:device) for vfio-pci binding
# This captures both the GPU (VGA) and its HDMI audio sibling
NVIDIA_IDS=$(lspci -nn | grep -i nvidia | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])' | sort -u | tr '\n' ',' | sed 's/,$//')

if [[ -z "$NVIDIA_IDS" ]]; then
  echo "ERROR: No NVIDIA devices found. Is the GPU installed and visible to lspci?"
  exit 1
fi

echo "GPU PCI IDs to bind to vfio-pci: $NVIDIA_IDS"
echo ""
read -rp "Proceed with configuring VFIO passthrough? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Step 3: Enable IOMMU in kernel cmdline ────────────────────────────────────

echo ""
echo "--- Configuring kernel cmdline for IOMMU ---"

if [[ ! -f "$CMDLINE_FILE" ]]; then
  echo "ERROR: $CMDLINE_FILE not found. Is this a Proxmox EFI system?"
  echo "For legacy GRUB: edit /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT instead."
  exit 1
fi

current_cmdline=$(cat "$CMDLINE_FILE")
new_cmdline="$current_cmdline"

[[ "$new_cmdline" =~ intel_iommu=on ]] || new_cmdline="$new_cmdline intel_iommu=on"
[[ "$new_cmdline" =~ iommu=pt ]]       || new_cmdline="$new_cmdline iommu=pt"

# Deduplicate spaces
new_cmdline=$(echo "$new_cmdline" | tr -s ' ' | sed 's/^ //;s/ $//')

echo "$new_cmdline" > "$CMDLINE_FILE"
echo "Written: $CMDLINE_FILE"
echo "  $new_cmdline"

proxmox-boot-tool refresh
echo "Boot tool refreshed."

# ── Step 4: Blacklist host GPU drivers ────────────────────────────────────────

echo ""
echo "--- Blacklisting nouveau and nvidia on host ---"
cat > "$MODPROBE_BLACKLIST" <<EOF
blacklist nouveau
blacklist nvidia
blacklist nvidiafb
blacklist nvidia_drm
blacklist nvidia_modeset
options nouveau modeset=0
EOF
echo "Written: $MODPROBE_BLACKLIST"

# ── Step 5: Bind GPUs to vfio-pci ────────────────────────────────────────────

echo ""
echo "--- Binding GPU IDs to vfio-pci ---"
cat > "$MODPROBE_VFIO" <<EOF
options vfio-pci ids=$NVIDIA_IDS
softdep nouveau pre: vfio-pci
softdep nvidia pre: vfio-pci
EOF
echo "Written: $MODPROBE_VFIO"
echo "  IDs: $NVIDIA_IDS"

# ── Step 6: Load vfio modules early in initramfs ─────────────────────────────

echo ""
echo "--- Adding vfio modules to initramfs ---"
for mod in vfio vfio_iommu_type1 vfio_pci vfio_pci_core; do
  grep -qxF "$mod" "$INITRAMFS_MODULES" 2>/dev/null || echo "$mod" >> "$INITRAMFS_MODULES"
done
echo "Updated: $INITRAMFS_MODULES"

update-initramfs -u -k all
echo "Initramfs updated."

# ── Step 7: Print PCI addresses for VM config ─────────────────────────────────

echo ""
echo "=== GPU PCI addresses for VM assignment ==="
echo "Use these in qm set or the Proxmox UI (Hardware → Add → PCI Device):"
echo ""
lspci -nn | grep -i nvidia | while read -r line; do
  addr=$(echo "$line" | awk '{print $1}')
  desc=$(echo "$line" | cut -d' ' -f2-)
  printf "  hostpciN: 0000:%s,pcie=1   # %s\n" "$addr" "$desc"
done

echo ""
echo "IMPORTANT: Pass each GPU + its HDMI audio sibling to the same VM."
echo "Example for GPU at 01:00.0 (audio at 01:00.1):"
echo "  hostpci0: 0000:01:00,pcie=1,x-vga=1"
echo "  (Proxmox will auto-include 01:00.1 when you use the .0 address)"
echo ""
echo "Done. Reboot the host to activate IOMMU and vfio-pci binding."
