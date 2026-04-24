#!/usr/bin/env bash
# Map physical drive bays to stable /dev/disk/by-id paths.
# Run on the Proxmox host after perc-nonraid.sh and a reboot.
# Output is a table you can paste into docs/hardware-layout.md.
#
# Requires: lsscsi, ledmon (apt install lsscsi ledmon)
# Optional: perccli for enclosure/slot info

set -euo pipefail

for cmd in lsscsi; do
  command -v "$cmd" &>/dev/null || { echo "Missing: $cmd — run: apt install $cmd"; exit 1; }
done

echo "=== Drive inventory ==="
echo ""
printf "%-12s %-10s %-30s %-20s %s\n" "DEVICE" "SIZE" "MODEL" "SERIAL" "BY-ID PATH"
printf "%-12s %-10s %-30s %-20s %s\n" "------" "----" "-----" "------" "---------"

for dev in /dev/sd?; do
  [[ -b "$dev" ]] || continue

  size=$(lsblk -dn -o SIZE "$dev" 2>/dev/null || echo "?")
  model=$(cat "/sys/block/$(basename "$dev")/device/model" 2>/dev/null | tr -d ' ' || echo "?")
  serial=$(cat "/sys/block/$(basename "$dev")/device/serial" 2>/dev/null | tr -d ' ' || echo "?")

  # Prefer WWN-based by-id, fall back to scsi- or ata-
  byid=$(ls -1 /dev/disk/by-id/ 2>/dev/null \
    | grep -v "\-part" \
    | while read -r link; do
        target=$(readlink -f "/dev/disk/by-id/$link")
        [[ "$target" == "$dev" ]] && echo "$link" && break
      done | head -1 || echo "not found")

  printf "%-12s %-10s %-30s %-20s %s\n" "$dev" "$size" "$model" "$serial" "/dev/disk/by-id/$byid"
done

echo ""
echo "=== Bay identification via LED blink ==="
echo ""
echo "To confirm which physical bay a device is in, blink its LED:"
echo "  apt install ledmon"
echo "  ledctl locate=/dev/sdX      # LED on"
echo "  ledctl locate_off=/dev/sdX  # LED off"
echo ""

if command -v perccli &>/dev/null || command -v perccli64 &>/dev/null; then
  PERCCLI=$(command -v perccli || command -v perccli64)
  echo "=== PERC slot info ==="
  $PERCCLI /c0 /eall /sall show | grep -E "^[0-9]|Drive's position|SN|WWN" || true
fi

echo ""
echo "Copy the BY-ID paths into docs/hardware-layout.md."
