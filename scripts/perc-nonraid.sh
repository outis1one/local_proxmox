#!/usr/bin/env bash
# Convert PERC H730 drives to Non-RAID (per-disk passthrough) mode.
# Run once on the Proxmox host before assigning drives to VMs.
# Requires: perccli (install from Dell's website or local .deb)
#
# Dell PERC H730 does not have a true HBA/IT mode. Non-RAID mode is the
# equivalent — each disk is presented directly to the OS with SMART intact.

set -euo pipefail

PERCCLI=$(command -v perccli || command -v perccli64 || true)
if [[ -z "$PERCCLI" ]]; then
  echo "perccli not found. Install options:"
  echo "  1. apt install -y perccli   (try this first — in Proxmox repos)"
  echo "  2. Download from dell.com/support → enter service tag → Drivers → Storage"
  echo "     Look for 'PERCCLI' and download the Linux .deb, then: dpkg -i perccli_*.deb"
  exit 1
fi

echo "=== Controller overview ==="
$PERCCLI show

echo ""
echo "=== Drives on controller 0 ==="
$PERCCLI /c0 /eall /sall show

echo ""
read -rp "Proceed with converting all non-OS drives to Non-RAID mode? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# Identify enclosure IDs (typically 8 for the internal backplane on R730xd)
ENCLOSURES=$($PERCCLI /c0 /eall show | awk '/^[0-9]/{print $1}' | sort -u)

for enc in $ENCLOSURES; do
  echo ""
  echo "=== Processing enclosure $enc ==="
  SLOTS=$($PERCCLI /c0 /e"$enc" /sall show | awk '/UGood|Onln|JBOD|DHS/{print $2}' | sort -u)

  for slot in $SLOTS; do
    echo -n "  Slot $slot: setting to Good... "
    $PERCCLI /c0 /e"$enc" /s"$slot" set good force 2>&1 | grep -i "success\|error\|already" || true

    echo -n "  Slot $slot: setting to Non-RAID... "
    $PERCCLI /c0 /e"$enc" /s"$slot" set nonraid 2>&1 | grep -i "success\|error\|already" || true
  done
done

echo ""
echo "=== Final drive state ==="
$PERCCLI /c0 /eall /sall show

echo ""
echo "Done. Reboot the host for changes to take full effect."
echo "After reboot, run build-bay-map.sh to map bays to /dev/disk/by-id paths."
