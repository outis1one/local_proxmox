# local_proxmox

Proxmox VE 9.1 configuration, scripts, and VM layouts for a Dell R730xd homelab.

## Hardware

- **Host:** Dell PowerEdge R730xd
- **RAID controller:** PERC H730 (configured in Non-RAID/per-disk passthrough mode)
- **GPUs:** 2x Quadro P3300 4GB (VFIO passthrough, one per VM)
- **TPU:** Google Coral USB (Frigate object detection)
- **Bays:** 12x (not all populated)

## VM Layout

| VM ID | Role | Drives | GPU | Coral |
|-------|------|--------|-----|-------|
| 100 | Frigate NVR | Bays 1–8 | Quadro #1 (VFIO) | Yes |
| 101 | TBD | Bays 9–10 | Quadro #2 (VFIO) | No |
| 102 | TBD | Bays 11–12 | None | No |

## Setup Order

1. [`scripts/perc-nonraid.sh`](scripts/perc-nonraid.sh) — convert H730 to per-disk non-RAID mode
2. [`scripts/build-bay-map.sh`](scripts/build-bay-map.sh) — map physical bays to stable `/dev/disk/by-id` paths
3. [`scripts/gpu-passthrough-setup.sh`](scripts/gpu-passthrough-setup.sh) — configure IOMMU + VFIO for both Quadros
4. Apply VM configs from [`vm-configs/`](vm-configs/)
5. Deploy Frigate from [`frigate/`](frigate/)

## Docs

- [`docs/hardware-layout.md`](docs/hardware-layout.md) — bay/device/VM mapping worksheet
