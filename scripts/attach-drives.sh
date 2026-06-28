#!/usr/bin/env bash
# Generate qm set commands to attach data drives to a Proxmox VM.
# Run on the Proxmox host. Skips the OS drive (sda) and any drives
# already attached to any VM.
#
# Usage:
#   ./attach-drives.sh              # preview commands (dry run)
#   ./attach-drives.sh --apply      # actually run the commands
#   ./attach-drives.sh --vm 100     # target a specific VM (default: 100)
#
# Example:
#   ./attach-drives.sh --vm 100 --apply

set -euo pipefail

VM_ID=100
APPLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vm)    VM_ID="$2"; shift 2 ;;
    --apply) APPLY=true; shift ;;
    *)       echo "Usage: $0 [--vm <id>] [--apply]"; exit 1 ;;
  esac
done

# ── Find drives already attached to any VM ────────────────────────────────────

attached_ids=()
for conf in /etc/pve/qemu-server/*.conf; do
  while IFS= read -r line; do
    if [[ "$line" =~ /dev/disk/by-id/([^,]+) ]]; then
      attached_ids+=("${BASH_REMATCH[1]}")
    fi
  done < "$conf"
done

is_attached() {
  local id="$1"
  for a in "${attached_ids[@]:-}"; do
    [[ "$a" == "$id" ]] && return 0
  done
  return 1
}

# ── Find next free scsi slot for the target VM ────────────────────────────────

next_slot() {
  local conf="/etc/pve/qemu-server/${VM_ID}.conf"
  local slot=1
  while grep -q "^scsi${slot}:" "$conf" 2>/dev/null; do
    (( slot++ ))
  done
  echo "$slot"
}

# ── Inventory all block devices ───────────────────────────────────────────────

echo "=== Available data drives (not yet attached to any VM) ==="
echo ""
printf "%-12s %-10s %-35s %s\n" "DEVICE" "SIZE" "BY-ID PATH" "MODEL"
printf "%-12s %-10s %-35s %s\n" "------" "----" "----------" "-----"

candidates=()

for dev in /dev/sd?; do
  [[ -b "$dev" ]] || continue
  name=$(basename "$dev")

  # Skip OS drive (sda — the PERC RAID array Proxmox is installed on)
  [[ "$name" == "sda" ]] && continue

  # Skip USB devices (small drives < 100G are likely USB sticks)
  size_bytes=$(lsblk -dn -o SIZE -b "$dev" 2>/dev/null || echo 0)
  size_human=$(lsblk -dn -o SIZE "$dev" 2>/dev/null || echo "?")
  if [[ "$size_bytes" -lt 107374182400 ]]; then   # < 100 GiB
    printf "%-12s %-10s %-35s %s\n" "$name" "$size_human" "(skipped — looks like USB stick)" ""
    continue
  fi

  model=$(cat "/sys/block/${name}/device/model" 2>/dev/null | xargs || echo "?")

  # Find best by-id (prefer ata- over scsi-)
  byid=""
  for link in /dev/disk/by-id/ata-* /dev/disk/by-id/scsi-3*; do
    [[ -L "$link" ]] || continue
    [[ "$(readlink -f "$link")" == "$dev" ]] || continue
    [[ "$link" =~ -part ]] && continue
    byid=$(basename "$link")
    [[ "$byid" == ata-* ]] && break   # prefer ata- if found
  done

  if [[ -z "$byid" ]]; then
    printf "%-12s %-10s %-35s %s\n" "$name" "$size_human" "(no by-id found — skip)" "$model"
    continue
  fi

  if is_attached "$byid"; then
    printf "%-12s %-10s %-35s %s\n" "$name" "$size_human" "${byid} [already attached]" "$model"
    continue
  fi

  printf "%-12s %-10s %-35s %s\n" "$name" "$size_human" "$byid" "$model"
  candidates+=("$byid")
done

echo ""

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "No unattached data drives found."
  exit 0
fi

# ── Generate qm set commands ──────────────────────────────────────────────────

echo "=== Commands to attach to VM ${VM_ID} ==="
echo ""

slot=$(next_slot)
cmds=()
for byid in "${candidates[@]}"; do
  cmd="qm set ${VM_ID} --scsi${slot} /dev/disk/by-id/${byid}"
  cmds+=("$cmd")
  echo "  $cmd"
  (( slot++ ))
done

echo ""

if $APPLY; then
  echo "--- Applying ---"
  for cmd in "${cmds[@]}"; do
    echo "  Running: $cmd"
    eval "$cmd"
  done
  echo ""
  echo "Done. Verify with:"
  echo "  grep scsi /etc/pve/qemu-server/${VM_ID}.conf"
else
  echo "Dry run — no changes made. Re-run with --apply to attach drives."
  echo ""
  echo "  ./attach-drives.sh --vm ${VM_ID} --apply"
fi
