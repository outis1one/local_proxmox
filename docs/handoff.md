# Session Hand-off Document
## Dell R730xd — Proxmox VE 9.1 Homelab Setup

**Branch:** `claude/proxmox-hardware-passthrough-ylAYx`
**Repo:** `outis1one/local_proxmox`

---

## Hardware Summary

| Component | Detail |
|-----------|--------|
| Server | Dell PowerEdge R730xd |
| RAID controller | PERC H730 (configured in per-disk non-RAID mode for 3.5" drives) |
| OS drives | 2x 2.5" rear drives — RAID1 mirror via H730 |
| Data drives | Up to 12x 3.5" bays (not all populated) |
| GPUs | 2x Quadro P2200 5GB (VFIO passthrough, one per VM) |
| TPU | Google Coral USB (Frigate object detection, VM 100) |
| iDRAC | iDRAC8 **Express** — no virtual console, no virtual media |
| PSU | 750W (single or redundant pair — stagger spin-up configured to protect PSU) |

## VM Layout

| VM ID | Role | Drives | GPU | Coral |
|-------|------|--------|-----|-------|
| 100 | Frigate NVR | Bays 1–8 | P2200 #1 | Yes |
| 101 | General purpose | Bays 9–10 | P2200 #2 | No |
| 102 | Utility/storage | Bays 11–12 | None | No |

---

## What Is In The Repo

### scripts/
| File | Purpose | Status |
|------|---------|--------|
| `perc-nonraid.sh` | Converts H730 3.5" drives to per-disk non-RAID mode | Done |
| `build-bay-map.sh` | Maps physical bay numbers to /dev/disk/by-id paths via LED blink | Done |
| `gpu-passthrough-setup.sh` | Configures IOMMU + vfio-pci for both Quadro P2200s | Done |
| `fan-control.sh` | Manages fan speed via ipmitool — prevents 100% fan from non-Dell GPU | Done |
| `fan-control.service` | Systemd unit for fan-control.sh | Done |
| `stagger-spinup.sh` | Staggers drive spin-up at boot to limit PSU current surge | Done |
| `stagger-spinup.service` | Systemd unit for stagger-spinup.sh | Done |

### vm-configs/
| File | Purpose | Status |
|------|---------|--------|
| `100-frigate.conf.example` | VM 100 skeleton — GPU, Coral USB, 8 drive slots | **Needs PLACEHOLDER_BAYx filled in after Phase 8** |
| `101.conf.example` | VM 101 skeleton — GPU #2, 2 drive slots | **Needs PLACEHOLDER_BAYx filled in after Phase 8** |
| `102.conf.example` | VM 102 skeleton — 2 drive slots | **Needs PLACEHOLDER_BAYx filled in after Phase 8** |

### frigate/
| File | Purpose | Status |
|------|---------|--------|
| `docker-compose.yml` | Frigate container with nvidia runtime + Coral USB | Done |
| `config.yml` | Frigate config — NVDEC hwaccel, Coral detector, recording | **Needs real camera RTSP URLs added** |

### docs/
| File | Purpose | Status |
|------|---------|--------|
| `hardware-layout.md` | Bay/VM/GPU mapping worksheet | **Needs filling in after Phase 8** |
| `setup-guide.md` | High-level 12-phase overview | Done |
| `walkthrough-phases-1-3.md` | Full button-by-button: Firmware, iDRAC, BIOS | Done |
| `walkthrough-phases-4-6.md` | Full button-by-button: H730 RAID, Proxmox install, post-install | Done |
| `walkthrough-phases-7-9.md` | Full button-by-button: non-RAID drives, bay map, GPU passthrough | Done |
| `walkthrough-phases-10-12.md` | Fan control, VM creation, Frigate deploy | **NOT WRITTEN YET** |
| `complete-walkthrough.md` | All phases combined into one document | **NOT WRITTEN YET** |

---

## What Still Needs To Be Done

### 1. Write `docs/walkthrough-phases-10-12.md`

Three phases to cover in full button-by-button detail:

**Phase 10 — Fan control + stagger spin-up services**
- Copy fan-control.sh to /usr/local/sbin/, install and enable systemd service
- Verify fans slow down within 30 seconds (ipmitool sdr type Fan)
- Run stagger-spinup.sh --idrac for BIOS-level config (or iDRAC web UI path)
- Install stagger-spinup.service, enable (don't start manually — runs at boot)

**Phase 11 — Create VMs in Proxmox web UI**
- Upload Ubuntu 24.04 LTS ISO to Proxmox local storage
- Create VM 100 via web UI: General → OS → System (q35, OVMF, VirtIO SCSI Single) → Disks → CPU (host type) → Memory → Network
- Add hardware to VM 100: PCI device (GPU, All Functions, Primary GPU, PCI-Express), two USB devices (Coral 1a6e:089a and 18d1:9302), data drives via CLI (qm set)
- Install Ubuntu inside each VM via Proxmox console
- Repeat for VMs 101 and 102 (simpler — no Coral, different GPU or no GPU)
- Find VM IP addresses

**Phase 12 — Frigate inside VM 100**
- SSH into VM 100 guest OS
- Install Docker (get.docker.com script)
- Install nvidia-driver-535, reboot, verify with nvidia-smi
- Install nvidia-container-toolkit, configure Docker runtime, test with docker run nvidia-smi
- Create ZFS pool from 8 data drives (raidz2 recommended)
- Clone repo or copy frigate/ directory
- Edit config.yml with real camera RTSP URLs
- docker compose up -d, watch logs
- Access web UI at http://vm100-ip:5000

### 2. Write `docs/complete-walkthrough.md`

Combine walkthrough-phases-1-3.md + 4-6.md + 7-9.md + 10-12.md (once written)
into a single document. Remove the "next file" references at the end of each
phase section. Add a table of contents at the top.

---

## Key Facts To Know

- **iDRAC Express** — no KVM, no virtual media. Physical monitor + keyboard
  required through Phase 5 (Proxmox installer). After that SSH only.
- **iDRAC default credentials:** root / calvin — must be changed (Phase 2)
- **iDRAC static IP** set in Phase 2 — needed for fan control ipmitool commands
- **IPMI over LAN** must be enabled in iDRAC (Phase 2) for fan control to work
- **Boot mode must be UEFI** (Phase 3) — legacy BIOS breaks gpu-passthrough-setup.sh
- **VT-d must be Enabled** (Phase 3) — most common reason passthrough silently fails
- **H730 OS drives** — the 2x 2.5" rear drives are RAID1 and must NOT be touched
  by perc-nonraid.sh. The script targets only UGood (unconfigured) drives.
- **Quadro P2200** — 75W TDP, no external power connector needed, no Code 43
  issue, NVDEC handles H.264/H.265 decode for Frigate with near-zero CPU usage
- **Coral USB re-enumerates** — passes through as 1a6e:089a before first
  inference, then 18d1:9302 after. Both USB entries must be in the VM config.
- **Fan control** uses raw IPMI commands to iDRAC over LAN — works on Express

---

## Script Run Order (for reference)

When Proxmox is installed and SSH is working:

```
1. dpkg -i perccli_*.deb
2. bash scripts/perc-nonraid.sh          → reboot
3. bash scripts/build-bay-map.sh         → fill in hardware-layout.md and vm-configs
4. bash scripts/gpu-passthrough-setup.sh → note PCI addresses, reboot
5. install fan-control.sh + .service     → verify fans slow down
6. install stagger-spinup.sh + .service
7. create VMs via Proxmox web UI
8. install Ubuntu in each VM
9. set up Frigate in VM 100
```
