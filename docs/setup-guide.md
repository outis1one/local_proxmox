# Dell R730xd — Proxmox VE 9.1 Setup Guide

Complete walkthrough from bare metal to running VMs with GPU passthrough,
Coral USB, and per-VM disk assignments.

---

## What You Need Before Starting

- USB drive (8GB+) for the Proxmox installer
- A second machine or phone to read this guide and SSH
- The iDRAC IP or physical access to a monitor + keyboard
- Internet connection on the server

---

## Phase 1 — Firmware Updates (do this first)

Outdated firmware causes mysterious IOMMU failures and fan issues. Do this
before anything else.

### Option A: Lifecycle Controller (no extra tools needed)

1. Power on the server, press **F10** when you see the Dell splash screen
2. Lifecycle Controller → **Firmware Update** → Check for updates
3. Point it at downloads.dell.com or a local repo
4. Update **iDRAC**, **BIOS**, **PERC H730**, and any NIC/HBA firmware
5. Let it reboot as many times as it needs

### Option B: Dell System Update (DSU) from bootable USB

A faster alternative if Lifecycle Controller is slow or unavailable — Dell
provides a bootable ISO that auto-detects and applies all updates.

---

## Phase 2 — iDRAC Setup

iDRAC is the out-of-band management interface. You need it configured for the
fan control script to work later.

1. Power on → press **F2** to enter System Setup → **iDRAC Settings**
2. **Network:**
   - Set a static IP (easier than DHCP for a server)
   - Note the IP — you'll use it for the fan control ipmitool commands
3. **User configuration:**
   - Change the default `root` password
4. **IPMI over LAN:**
   - iDRAC Settings → Network → IPMI Settings → **Enable IPMI over LAN: On**
   - This is required for `ipmitool` fan control from the Proxmox host

---

## Phase 3 — BIOS Settings

Still in F2 System Setup. These settings are **required** for GPU and USB
passthrough to work.

| Menu path | Setting | Value |
|-----------|---------|-------|
| Processor Settings | Virtualization Technology | **Enabled** |
| Processor Settings | C States | **Disabled** |
| PCI Configuration | SR-IOV Global Enable | **Enabled** |
| Boot Settings → BIOS Boot Settings | Boot Mode | **UEFI** (not Legacy/BIOS) |
| System Profile Settings | System Profile | **Custom** |
| System Profile Settings | CPU Power Management | **Maximum Performance** |

> **VT for Direct I/O (VT-d):** Newer R730xd BIOS versions (2.19+) removed
> this toggle — VT-d is enabled by default. Don't worry if you can't find it.
> Verify it's active after Proxmox is installed: `dmesg | grep -i iommu`
> should show `DMAR: IOMMU enabled`. The kernel cmdline (`intel_iommu=on
> iommu=pt`) in Phase 9 is still required.
>
> **Hard Disk Drive Sequencing** was also removed in newer BIOS — it is no
> longer present and is not needed.

> **Boot Mode must be UEFI.** Proxmox's EFI boot tool (`proxmox-boot-tool`)
> only works with UEFI. Legacy BIOS mode breaks the GPU passthrough script.

**Apply and exit. The server will reboot.**

---

## Phase 4 — H730 RAID Configuration (pre-Proxmox)

The two 2.5" rear drives are your Proxmox OS drives. You want them mirrored
so a single drive failure doesn't take down the hypervisor.

The 3.5" drives will be converted to non-RAID later **from within Proxmox**
using the `perc-nonraid.sh` script — do not touch them here.

### Configure the 2.5" OS drives

1. Reboot → press **Ctrl+R** during POST to enter the H730 configuration
   utility (or use Lifecycle Controller → RAID Configuration)
2. Select the controller
3. Find the two 2.5" rear drives
4. **Create new virtual disk:**
   - RAID level: **RAID 1** (mirror)
   - Select both 2.5" drives
   - Strip size: 64KB (default)
   - Name: `OS-Mirror` (optional)
   - Initialize: **Fast Initialize**
5. Press **Ctrl+Alt+Delete** to reboot

The H730 now presents a single ~X GB RAID1 virtual disk to the OS. Proxmox
will install onto this and never know there are two physical drives behind it.

> The 3.5" drives will show as "Unconfigured Good" in the H730 — that is fine.
> Leave them alone. `perc-nonraid.sh` handles them after Proxmox is installed.

---

## Phase 5 — Install Proxmox VE 9.1

### Prepare the USB installer

On another machine, download the Proxmox VE ISO from proxmox.com and write it
to a USB drive:

```bash
# Linux/macOS
dd if=proxmox-ve_*.iso of=/dev/sdX bs=1M status=progress conv=fsync
# or use Balena Etcher (Windows/Mac/Linux GUI)
```

### Boot and install

1. Plug the USB into the R730xd
2. Power on → press **F11** for the one-time boot menu
3. Select the USB drive
4. At the Proxmox boot menu: **Install Proxmox VE (Graphical)**
5. **Target disk:** select the RAID1 virtual disk (`OS-Mirror`)
   - Filesystem: **ext4** is simplest — the H730 RAID1 already gives you
     redundancy, so ZFS mirroring here would be double-redundant overkill
6. **Location and timezone:** set to your region
7. **Password and email:** set a strong root password, enter an email
8. **Network configuration:**
   - Management interface: the built-in NIC (usually `em1` or `eno1`)
   - Hostname: e.g. `pve.local`
   - IP: choose a static IP on your LAN (e.g. `192.168.1.10/24`)
   - Gateway and DNS: your router's IP
9. Click **Install**
10. Remove USB when prompted, let it reboot

### First login

Open a browser on your LAN machine and go to:

```
https://192.168.1.10:8006
```

Accept the self-signed certificate warning. Login: `root` / (your password),
Realm: **Linux PAM**.

---

## Phase 6 — Proxmox Post-Install (SSH)

SSH into the host from now on — it's faster than the web console for these
steps.

```bash
ssh root@192.168.1.10
```

### 6a. Fix the apt repositories

Proxmox shows "no valid subscription" warnings when using the enterprise repo
without a license. Switch to the free repo:

```bash
# Disable enterprise repos — PVE9 uses .sources (DEB822 format), not .list
echo "# disabled - no subscription" > /etc/apt/sources.list.d/pve-enterprise.sources
echo "# disabled - no subscription" > /etc/apt/sources.list.d/ceph.sources
# Also disable any legacy .list versions if present
echo "# disabled - no subscription" > /etc/apt/sources.list.d/pve-enterprise.list
echo "# disabled - no subscription" > /etc/apt/sources.list.d/ceph.list

# Add no-subscription repos (trixie = Proxmox 9 / Debian 13)
echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list
echo "deb http://download.proxmox.com/debian/ceph-squid trixie no-subscription" \
  > /etc/apt/sources.list.d/ceph-no-subscription.list

apt update && apt dist-upgrade -y
reboot
```

### 6b. Install tools used by the scripts

```bash
apt install -y ipmitool lsscsi ledmon hdparm git
```

### 6c. Clone this repo onto the host

```bash
git clone https://github.com/outis1one/local_proxmox.git /opt/local_proxmox
cd /opt/local_proxmox
chmod +x scripts/*.sh
```

---

## Phase 7 — H730: Set 3.5" Drives to Non-RAID Mode

Now that Proxmox is running, convert the 3.5" drives to per-disk (non-RAID)
mode. The OS drives (RAID1 virtual disk) are **not affected** — the script only
targets unconfigured physical disks.

### Install perccli

Try apt first — it's in the Proxmox repos:

```bash
apt install -y perccli
```

If not found, download the `.deb` manually: go to `dell.com/support`, enter
your service tag, then Drivers → Storage → search "PERCCLI", download the
Linux package, copy it to the host, and install:

```bash
dpkg -i perccli_*.deb
```

### Run the script

```bash
bash /opt/local_proxmox/scripts/perc-nonraid.sh
```

Review the output, confirm when prompted. **Reboot after completion.**

```bash
reboot
```

After rebooting, Proxmox will see the 3.5" drives as individual block devices
(`/dev/sdb`, `/dev/sdc`, etc.).

---

## Phase 8 — Map Physical Bays to Drives

```bash
bash /opt/local_proxmox/scripts/build-bay-map.sh
```

Walk the bays with `ledctl` to confirm which physical slot is which device:

```bash
ledctl locate=/dev/sdb   # LED blinks on the matching bay
ledctl locate_off=/dev/sdb
```

Fill in the `by-id` paths in `docs/hardware-layout.md`. You will need these
in Phase 11 when creating VMs.

---

## Phase 9 — GPU Passthrough Setup

```bash
bash /opt/local_proxmox/scripts/gpu-passthrough-setup.sh
```

The script:
- Adds `intel_iommu=on iommu=pt` to the kernel command line
- Blacklists `nouveau`/`nvidia` on the host
- Binds both Quadro P2200s to `vfio-pci`
- Rebuilds initramfs

**Note the PCI addresses it prints at the end** — you'll need them in Phase 11.

```bash
reboot
```

### Verify after reboot

```bash
lspci -nnk | grep -A3 -i nvidia
```

Both GPUs should show `Kernel driver in use: vfio-pci`. If they still show
`nouveau`, check that `/etc/modprobe.d/blacklist-gpu.conf` exists and
`update-initramfs -u` was run.

---

## Phase 10 — Fan Control and Staggered Spin-Up

### Fan control (prevents jet-engine noise from non-Dell GPUs)

```bash
cp /opt/local_proxmox/scripts/fan-control.sh /usr/local/sbin/fan-control.sh
cp /opt/local_proxmox/scripts/fan-control.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now fan-control.service
systemctl status fan-control.service
```

Test it worked — the fans should audibly slow down within 30 seconds.
To check current speed: `ipmitool sdr type Fan`

### Staggered spin-up

> **BIOS 2.19+ note:** `BIOS.StorageSettings.HddSeq` was removed from the
> R730xd firmware. The iDRAC/BIOS layer (Layer 1) no longer works — skip it
> and go straight to the Linux service below.

**Linux service** (staggers drives in standby at OS boot):

```bash
cp /opt/local_proxmox/scripts/stagger-spinup.sh /usr/local/sbin/stagger-spinup.sh
cp /opt/local_proxmox/scripts/stagger-spinup.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable stagger-spinup.service
```

---

## Phase 11 — Create the VMs

### Prepare the VM configs

Edit the three example configs and replace the placeholders:

```bash
cd /opt/local_proxmox/vm-configs

# Replace PLACEHOLDER_BAYx with real by-id paths from Phase 8
# Replace XX:00 with real PCI addresses from Phase 9
nano 100-frigate.conf.example
nano 101.conf.example
nano 102.conf.example
```

### Create OS disks for each VM

In the Proxmox web UI or via CLI, create the base OS disk for each VM:

```bash
# Creates the disk slots — Proxmox generates the correct scsi0 line
qm create 100 --memory 16384 --cores 8 --name frigate --net0 virtio,bridge=vmbr0
qm create 101 --memory 16384 --cores 8 --name vm101   --net0 virtio,bridge=vmbr0
qm create 102 --memory 8192  --cores 4 --name vm102   --net0 virtio,bridge=vmbr0
```

Then merge your edited conf into the generated config:

```bash
# Backup generated config, then append your hardware lines
cp /etc/pve/qemu-server/100.conf /etc/pve/qemu-server/100.conf.bak
cat 100-frigate.conf.example >> /etc/pve/qemu-server/100.conf
```

Or just open each VM in the Proxmox web UI → **Hardware** and add:
- PCI Device → your GPU (enable PCIe, enable Primary GPU for VM 100)
- USB Device → host device → `1a6e:089a` and `18d1:9302` (VM 100 only)
- Hard Disk → (use disk passthrough, SCSI controller, path = your by-id)

### Install a guest OS

Boot each VM from an ISO (upload ISOs to Proxmox under local storage →
ISO Images). Ubuntu Server 22.04 LTS is a good choice for the Frigate VM.

---

## Phase 12 — Set Up Frigate in VM 100

From inside VM 100 (SSH into the guest OS):

### Install Docker

```bash
apt update && apt install -y ca-certificates curl
curl -fsSL https://get.docker.com | sh
```

### Install NVIDIA driver + Container Toolkit

```bash
# Add NVIDIA apt repo
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt update
apt install -y nvidia-driver-535 nvidia-container-toolkit

# Configure Docker to use the NVIDIA runtime
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# Verify the GPU is visible
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

### Deploy Frigate

```bash
mkdir -p /opt/frigate && cd /opt/frigate

# Copy configs from the repo (or clone it inside the VM)
cp /path/to/local_proxmox/frigate/docker-compose.yml .
cp /path/to/local_proxmox/frigate/config.yml .

# Create the recordings directory (on your passthrough data drive)
# Mount your data drives first — if using ZFS:
zpool import <poolname>   # or create a new pool from the raw drives
mkdir -p /mnt/frigate

# Edit config.yml and add your camera RTSP URLs
nano config.yml

docker compose up -d
docker compose logs -f    # watch for errors on first start
```

Frigate UI: `http://<vm100-ip>:5000`

---

## Troubleshooting

### GPU not passing through — still shows `nouveau`

```bash
update-initramfs -u -k all && reboot
# After reboot:
lspci -nnk | grep -A3 -i nvidia   # must show vfio-pci
```

### IOMMU not enabled

```bash
dmesg | grep -i iommu
# Should show: "DMAR: IOMMU enabled"
# If not: re-check Phase 9 cmdline (intel_iommu=on); VT-d is on by default in newer BIOS
cat /etc/kernel/cmdline   # must contain intel_iommu=on iommu=pt
```

### Fan control not working

```bash
# Check iDRAC IP is reachable and IPMI over LAN is enabled (Phase 2)
ipmitool -I lan -H <idrac-ip> -U root -P <password> sdr type Fan
# Then check the service:
systemctl status fan-control.service
journalctl -u fan-control.service -n 50
```

### Coral not detected in Frigate

```bash
# In VM 100, check both USB IDs are present
lsusb | grep -E "1a6e|18d1"
# If missing, check the USB passthrough lines in the VM config
# Both usb0 (1a6e:089a) and usb1 (18d1:9302) must be present
```

### Drive not appearing after perc-nonraid.sh

```bash
lsblk
# If the drive is missing, check its state in perccli:
perccli /c0 /eall /sall show
# State should be "JBOD" or "UGood" — not "Offln" or "Msng"
```
