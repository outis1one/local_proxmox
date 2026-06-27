#!/usr/bin/env bash
# Convert PERC H730 drives to JBOD (per-disk passthrough) mode.
# Run once on the Proxmox host before assigning drives to VMs.
# Requires: perccli (install from Dell's website or local .deb)
#
# Dell PERC H730 requires two steps to expose drives to the OS:
#   1. Enable JBOD mode on the controller
#   2. Set each unconfigured drive to JBOD state
# Without both steps, drives show as UGood in perccli but are invisible to lsblk.

set -euo pipefail

PERCCLI=$(command -v perccli || command -v perccli64 || true)
if [[ -z "$PERCCLI" ]]; then
  echo "perccli not found. Install it:"
  echo "  curl -L --referer 'https://www.dell.com/' \\"
  echo "    --user-agent 'Mozilla/5.0' \\"
  echo "    'https://dl.dell.com/FOLDER03559396M/1/perccli-1.17.10-1.noarch.rpm' \\"
  echo "    -o /tmp/perccli.rpm"
  echo "  apt install -y alien && alien --to-deb /tmp/perccli.rpm"
  echo "  dpkg -i /tmp/perccli_*.deb"
  echo "  ln -s /opt/MegaRAID/perccli/perccli64 /usr/local/bin/perccli"
  exit 1
fi

echo "=== Controller overview ==="
$PERCCLI show

echo ""
echo "=== Drives on controller 0 ==="
$PERCCLI /c0 /eall /sall show

echo ""
read -rp "Proceed with converting all non-OS drives to JBOD mode? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# Step 1: Enable JBOD mode on the controller
echo ""
echo "--- Enabling JBOD mode on controller 0 ---"
$PERCCLI /c0 set jbod=on
echo ""

# Step 2: Set each UGood drive to JBOD state so the OS can see it
# Only targets UGood drives — skips Onln drives (OS RAID members)
ENCLOSURES=$($PERCCLI /c0 /eall show | awk '/^[0-9]/{print $1}' | sort -u)

for enc in $ENCLOSURES; do
  echo "=== Processing enclosure $enc ==="
  SLOTS=$($PERCCLI /c0 /e"$enc" /sall show | awk '/UGood/{print $2}' | sort -u)

  for slot in $SLOTS; do
    echo -n "  Slot $slot: setting to JBOD... "
    $PERCCLI /c0 /e"$enc" /s"$slot" set jbod 2>&1 | grep -i "success\|error\|already" || true
  done
done

echo ""
echo "=== Final drive state ==="
$PERCCLI /c0 /eall /sall show

echo ""
echo "Done. Drives should now be visible to the OS (check with lsblk)."
echo "No reboot required — drives appear immediately after JBOD transition."
echo "Run build-bay-map.sh to map bays to /dev/disk/by-id paths."
