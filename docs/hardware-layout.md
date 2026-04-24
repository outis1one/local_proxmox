# Hardware Layout

Dell R730xd — fill this in after running `scripts/build-bay-map.sh`.

## Bay → Device → VM Map

Run `scripts/build-bay-map.sh` on the Proxmox host to auto-populate the by-id column.
Confirm bay numbers by running `ledctl locate=<device>` to blink the drive LED.

| Bay | Assigned VM | Size | /dev/disk/by-id (fill in) | Notes |
|-----|-------------|------|---------------------------|-------|
| 1   | 100         |      |                           |       |
| 2   | 100         |      |                           |       |
| 3   | 100         |      |                           |       |
| 4   | 100         |      |                           |       |
| 5   | 100         |      |                           |       |
| 6   | 100         |      |                           |       |
| 7   | 100         |      |                           |       |
| 8   | 100         |      |                           |       |
| 9   | 101         |      |                           |       |
| 10  | 101         |      |                           |       |
| 11  | 102         |      |                           |       |
| 12  | 102         |      |                           |       |

## GPU Map

Run `lspci -nn | grep -i nvidia` on the Proxmox host and fill in the PCI addresses.

| Slot | PCI Address (fill in) | Assigned VM | Notes |
|------|-----------------------|-------------|-------|
| GPU 1 |                      | 100         | Frigate decode + display |
| GPU 2 |                      | 101         |       |

The GPU's HDMI audio function (same address, function 1) must be passed through alongside the GPU.
Example: GPU at `01:00.0` → also pass `01:00.1`.

## USB / TPU Map

| Device | VID:PID | Assigned VM | Notes |
|--------|---------|-------------|-------|
| Coral (pre-init)  | 1a6e:089a | 100 | Global Unichip — before first inference |
| Coral (post-init) | 18d1:9302 | 100 | Google — after first inference; pass both |

## IOMMU Groups

Run on Proxmox host to check groupings before passthrough:

```bash
for d in /sys/kernel/iommu_groups/*/devices/*; do
  n=${d#*/iommu_groups/*}; n=${n%%/*}
  printf 'IOMMU Group %s ' "$n"
  lspci -nns "${d##*/}"
done | sort -V
```

Each GPU should appear in its own group (with only its HDMI audio sibling).
If a GPU shares a group with other devices, those must be passed through together.

## Network

| VM  | Interface | Bridge | Notes |
|-----|-----------|--------|-------|
| 100 | net0      | vmbr0  |       |
| 101 | net0      | vmbr0  |       |
| 102 | net0      | vmbr0  |       |
