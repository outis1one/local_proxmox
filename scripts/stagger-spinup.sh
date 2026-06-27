#!/usr/bin/env bash
# Stagger hard drive spin-up on Dell R730xd to avoid PSU current surge at boot.
#
# 12 x 3.5" HDDs spinning up simultaneously can spike ~240W for 2-3 seconds.
# Staggering them 2-3 seconds apart keeps the surge well within PSU limits.
#
# TWO layers of protection:
#   1. iDRAC BIOS setting — fires at POST, before the OS loads (preferred)
#   2. Linux systemd service — staggers drives that weren't spun up at POST
#
# SETUP
# ─────
# Layer 1 (iDRAC, run once):
#   bash stagger-spinup.sh --idrac
#   # Requires racadm and iDRAC network access, then reboot to apply.
#
# Layer 2 (Linux service, run once):
#   cp stagger-spinup.sh /usr/local/sbin/stagger-spinup.sh
#   chmod +x /usr/local/sbin/stagger-spinup.sh
#   Install the systemd unit below, then:
#   systemctl daemon-reload && systemctl enable stagger-spinup.service

set -euo pipefail

STAGGER_SECONDS=3   # delay between each drive spin-up
HDPARM=$(command -v hdparm || true)

# ── iDRAC BIOS method (Layer 1) ───────────────────────────────────────────────

configure_idrac() {
  # BIOS.StorageSettings.HddSeq was removed in R730xd BIOS 2.19+.
  # The BIOS-level stagger is no longer available; rely on Layer 2 (Linux service).
  echo "NOTE: BIOS.StorageSettings.HddSeq was removed in R730xd BIOS 2.19+."
  echo "The iDRAC/BIOS layer for staggered spin-up is not available on this firmware."
  echo ""
  echo "Use the Linux systemd service (Layer 2) instead — it handles the same"
  echo "job by staggering drives that are in standby at OS boot time."
  echo ""
  echo "To install the service:"
  echo "  cp stagger-spinup.sh /usr/local/sbin/stagger-spinup.sh"
  echo "  chmod +x /usr/local/sbin/stagger-spinup.sh"
  echo "  # copy stagger-spinup.service to /etc/systemd/system/"
  echo "  systemctl daemon-reload && systemctl enable stagger-spinup.service"
}

# ── Linux spin-up stagger (Layer 2) ──────────────────────────────────────────
# Called by the systemd service early in boot.
# Reads each block device in sequence with a short delay, causing drives in
# standby to spin up one at a time rather than simultaneously.

stagger_linux() {
  if [[ -z "$HDPARM" ]]; then
    echo "hdparm not found — apt install hdparm"
    exit 1
  fi

  mapfile -t drives < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}' | sort)

  if [[ ${#drives[@]} -eq 0 ]]; then
    echo "No block devices found."
    exit 0
  fi

  echo "$(date): Staggering spin-up for ${#drives[@]} drives (${STAGGER_SECONDS}s apart)..."

  for dev in "${drives[@]}"; do
    # Skip if device is already active (check power mode)
    state=$($HDPARM -C "$dev" 2>/dev/null | grep -oP '(?<=drive state is:  )\S+' || echo "unknown")

    if [[ "$state" == "standby" || "$state" == "sleeping" ]]; then
      echo "$(date):  Waking $dev (was: $state)"
      # A zero-length read is enough to trigger spin-up
      dd if="$dev" of=/dev/null bs=512 count=1 status=none 2>/dev/null || true
      sleep "$STAGGER_SECONDS"
    else
      echo "$(date):  $dev already active (state: $state) — skipping"
    fi
  done

  echo "$(date): Stagger complete."
}

# ── Argument dispatch ─────────────────────────────────────────────────────────

case "${1:-}" in
  --idrac)
    configure_idrac
    ;;
  --linux|"")
    stagger_linux
    ;;
  *)
    echo "Usage: $0 [--idrac | --linux]"
    echo "  --idrac   Configure iDRAC BIOS staggered spin-up (one-time setup)"
    echo "  --linux   Stagger drives via hdparm now (run by systemd service)"
    exit 1
    ;;
esac
