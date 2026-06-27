#!/usr/bin/env bash
# Dell R730xd fan speed control for third-party PCIe cards (non-Dell GPUs)
#
# iDRAC detects non-Dell GPUs and slams fans to 100% indefinitely.
# This script disables iDRAC automatic fan control and manages speed based
# on inlet temperature, keeping the server quiet under normal load.
#
# Install:
#   apt install ipmitool
#   cp fan-control.sh /usr/local/sbin/fan-control.sh
#   chmod +x /usr/local/sbin/fan-control.sh
#   cp fan-control.service /etc/systemd/system/
#   systemctl daemon-reload && systemctl enable --now fan-control.service
#
# Manual speed test (without running as daemon):
#   fan-control.sh --set 25     # set fans to 25% and exit
#   fan-control.sh --auto       # restore iDRAC automatic control and exit

set -euo pipefail

IPMI="ipmitool raw 0x30 0x30"

# Fan speed thresholds by inlet temperature (°C → % speed)
# Tune these for your environment. Inlet temp sensor reads ambient air entering front.
declare -A SPEED_MAP=(
  [0]=15    # < 30°C  → 15% (near-silent)
  [30]=20   # 30–39°C → 20%
  [40]=30   # 40–44°C → 30%
  [45]=40   # 45–49°C → 40%
  [50]=55   # 50–54°C → 55%
  [55]=75   # 55–59°C → 75%
  [60]=100  # ≥ 60°C  → 100% (safety)
)

# Minimum speed floor — never go below this (protects drives and CPUs)
MIN_SPEED=15

get_inlet_temp() {
  ipmitool sdr type Temperature 2>/dev/null \
    | grep -i "Inlet Temp\|Ambient\|Inlet" \
    | grep -oP '\d+(?= degrees)' \
    | head -1 || echo "35"  # safe default if sensor read fails
}

pct_to_hex() {
  printf '0x%02x' "$(( $1 < 100 ? $1 : 100 ))"
}

set_fan_speed() {
  local pct=$1
  [[ $pct -lt $MIN_SPEED ]] && pct=$MIN_SPEED
  local hex
  hex=$(pct_to_hex "$pct")
  $IPMI 0x02 0xff "$hex"
}

disable_auto_fan() {
  $IPMI 0x01 0x00
  echo "$(date): iDRAC automatic fan control DISABLED"
}

enable_auto_fan() {
  $IPMI 0x01 0x01
  echo "$(date): iDRAC automatic fan control RE-ENABLED"
}

speed_for_temp() {
  local temp=$1
  local speed=$MIN_SPEED
  for threshold in $(echo "${!SPEED_MAP[@]}" | tr ' ' '\n' | sort -n); do
    [[ $temp -ge $threshold ]] && speed=${SPEED_MAP[$threshold]}
  done
  echo "$speed"
}

# ── Argument handling ─────────────────────────────────────────────────────────

case "${1:-}" in
  --auto)
    enable_auto_fan
    exit 0
    ;;
  --set)
    pct="${2:?Usage: fan-control.sh --set <0-100>}"
    disable_auto_fan
    set_fan_speed "$pct"
    echo "$(date): Fans set to ${pct}%"
    exit 0
    ;;
  --temp)
    echo "Inlet temp: $(get_inlet_temp)°C"
    exit 0
    ;;
  "")
    # Daemon mode — fall through to loop
    ;;
  *)
    echo "Usage: $0 [--auto | --set <pct> | --temp]"
    exit 1
    ;;
esac

# ── Daemon loop ───────────────────────────────────────────────────────────────

trap 'enable_auto_fan; exit 0' SIGTERM SIGINT

echo "$(date): Fan control daemon starting"
disable_auto_fan

last_speed=-1

while true; do
  temp=$(get_inlet_temp)
  target=$(speed_for_temp "$temp")

  if [[ $target -ne $last_speed ]]; then
    set_fan_speed "$target"
    echo "$(date): Inlet ${temp}°C → fans ${target}%"
    last_speed=$target
  fi

  sleep 30
done
