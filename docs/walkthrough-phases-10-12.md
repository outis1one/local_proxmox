# Phases 10–12: Fan Control, VM Creation, Frigate Deploy
### Dell R730xd — Button-by-button walkthrough

---

## Phase 10 — Fan Control + Stagger Spin-Up Services

**What this phase does:** Fixes two hardware quirks that bite R730xd owners
running non-Dell gear:

1. **Fan control.** iDRAC detects the two Quadro P2200s as "non-Dell PCIe
   cards" and immediately pins every fan at 100% indefinitely to be safe.
   The server sounds like a jet engine and never stops. We disable iDRAC's
   automatic control and replace it with a daemon that sets fan speed based
   on the inlet temperature sensor.
2. **Staggered drive spin-up.** Twelve 3.5" HDDs spinning up simultaneously
   at boot spike about 240 W of inrush current for 2–3 seconds — enough to
   trip a 750 W PSU under load. We configure two layers of protection: the
   iDRAC BIOS setting that fires at POST (before the OS loads), and a Linux
   systemd service that handles any drives the BIOS setting missed.

**Prerequisites from earlier phases:**
- IPMI over LAN enabled in iDRAC (Phase 2) — required for `ipmitool`
- `ipmitool` and `hdparm` installed on the host (Phase 6.3)
- Repo cloned to `/opt/local_proxmox` (Phase 6.4)

---

### Step 10.1 — Test fan control manually before enabling the service

Before installing anything as a systemd service, verify that the script can
actually talk to iDRAC over IPMI. This catches misconfigured IPMI-over-LAN
credentials before you wonder why the service silently failed.

SSH into Proxmox:

```bash
ssh root@192.168.1.10
```

Check the current inlet temperature:

```bash
bash /opt/local_proxmox/scripts/fan-control.sh --temp
```

Expected output:

```
Inlet temp: 24°C
```

The number will vary with your room temperature — anywhere between 18–35°C
is typical for an idle server.

> **If you see `Inlet temp: 35°C` exactly every time** — that is the script's
> hard-coded fallback for when the sensor read fails. IPMI is not responding.
> Check Phase 2: iDRAC **Network → IPMI Settings → Enable IPMI Over LAN**
> must be checked, and the channel privilege level must be **Administrator**.

Now test a manual fan speed override. This is safe — the script has a 15%
minimum floor hard-coded, so you cannot accidentally stop the fans:

```bash
bash /opt/local_proxmox/scripts/fan-control.sh --set 20
```

Expected output:

```
<date>: iDRAC automatic fan control DISABLED
<date>: Fans set to 20%
```

**Within 10–30 seconds you should hear the fans audibly slow down.** The
R730xd is loud at 100% — the difference is immediate and obvious.

Confirm the fans actually dropped:

```bash
ipmitool sdr type Fan
```

Expected output:

```
Fan1A            | 30h | ok  |  7.1 | 2400 RPM
Fan1B            | 31h | ok  |  7.1 | 2160 RPM
Fan2A            | 32h | ok  |  7.1 | 2400 RPM
Fan2B            | 33h | ok  |  7.1 | 2160 RPM
Fan3A            | 34h | ok  |  7.1 | 2400 RPM
Fan3B            | 35h | ok  |  7.1 | 2160 RPM
...
```

At 20% you should see roughly 2000–3000 RPM. At iDRAC's panic 100% you
would see 12000–15000 RPM. If the numbers look like the former you are in
good shape.

Now hand control back to iDRAC before proceeding — we want the real service
to be what re-disables automatic control, not this test:

```bash
bash /opt/local_proxmox/scripts/fan-control.sh --auto
```

Expected output:

```
<date>: iDRAC automatic fan control RE-ENABLED
```

**The fans will immediately ramp back to 100% within a few seconds** — that
is iDRAC reacting to the Quadro again. This confirms the script was in fact
holding them down. Get the service installed quickly so the noise stops.

---

### Step 10.2 — Install the fan control script and service

Copy the script to the system directory and make it executable:

```bash
cp /opt/local_proxmox/scripts/fan-control.sh /usr/local/sbin/fan-control.sh
chmod +x /usr/local/sbin/fan-control.sh
```

Copy the systemd unit into place:

```bash
cp /opt/local_proxmox/scripts/fan-control.service /etc/systemd/system/
```

Tell systemd about the new unit, then enable and start it in one command:

```bash
systemctl daemon-reload
systemctl enable --now fan-control.service
```

`enable --now` both enables the unit for future boots and starts it right
now, so the fans should begin quieting within 30 seconds.

Verify the service is running:

```bash
systemctl status fan-control.service
```

Expected output (abbreviated):

```
● fan-control.service - Dell R730xd fan speed control (third-party GPU)
     Loaded: loaded (/etc/systemd/system/fan-control.service; enabled; preset: enabled)
     Active: active (running) since <time>
   Main PID: 12345 (fan-control.sh)
      Tasks: 2 (limit: 154321)
     Memory: 1.5M
     CGroup: /system.slice/fan-control.service
             ├─12345 /bin/bash /usr/local/sbin/fan-control.sh
             └─12350 sleep 30

<date>: Fan control daemon starting
<date>: iDRAC automatic fan control DISABLED
<date>: Inlet 24°C → fans 15%
```

The key lines to verify:
- **Active: active (running)** — the daemon is up
- **iDRAC automatic fan control DISABLED** — iDRAC is no longer in charge
- **Inlet NN°C → fans NN%** — it read the sensor and set a speed from the map

Press **q** to exit the status view.

---

### Step 10.3 — Verify fans actually slow down over time

Wait 60 seconds, then check fan RPMs again:

```bash
ipmitool sdr type Fan
```

At an idle inlet of 22–30°C, the speed map in `fan-control.sh` sets fans to
15–20%. You should see roughly 2000–3000 RPM across all fans. The server
should be noticeably quiet — closer to a desktop PC than a server.

If the server is still loud (fans 10000+ RPM):

```bash
journalctl -u fan-control.service -n 50
```

Look for errors from `ipmitool`. The most common failure is **Unable to
establish IPMI v2 / RMCP+ session** — that means IPMI over LAN is not
enabled in iDRAC. Revisit Phase 2's iDRAC IPMI settings.

> **Tuning the temperature curve:** The defaults in `fan-control.sh` are
> conservative — 15% below 30°C, scaling up to 100% at 60°C inlet. If the
> server runs hot (40°C+ inlet is common in a closed rack) and the fans feel
> too aggressive, edit the `SPEED_MAP` array in `/usr/local/sbin/fan-control.sh`,
> then `systemctl restart fan-control.service`. Never lower `MIN_SPEED=15` —
> below that the drives and CPUs have no airflow safety margin.

---

### Step 10.4 — Configure iDRAC staggered spin-up (BIOS layer)

The BIOS layer fires at POST, before the OS even starts. It tells the H730
to spin up drives one at a time during the power-on self-test. This is the
strongest protection because it runs when PSU inrush risk is highest.

Run the script's iDRAC helper:

```bash
bash /opt/local_proxmox/scripts/stagger-spinup.sh --idrac
```

**If `racadm` is installed** on the Proxmox host (it sometimes ships in the
Dell OMSA bundle), the script will run it directly:

```
Enabling iDRAC hard disk drive sequencing (staggered spin-up)...
[Key=BIOS.Setup.1-1#StorageSettings]
Object value modified successfully
RAC973: Successfully scheduled a job.
Job queued. Reboot for the BIOS setting to take effect.
```

**If `racadm` is not installed** — which is the normal case on a plain
Proxmox host — the script prints two manual options:

```
racadm not found.
Option A: Run from iDRAC SSH:
  ssh root@<idrac-ip>
  racadm set BIOS.StorageSettings.HddSeq Enabled
  racadm jobqueue create BIOS.Setup.1-1
  # Then reboot to apply.

Option B: iDRAC web UI:
  System BIOS → Power Management → Hard Disk Drive Sequencing → Enabled
  Apply and reboot.
```

**Use Option A (iDRAC SSH)** — it is the reliable one. The web UI path is
buried deep and the wording varies between firmware versions.

SSH directly to iDRAC using the static IP you set in Phase 2:

```bash
ssh root@192.168.1.11
```

(Enter the iDRAC root password you set in Phase 2.)

You will land in iDRAC's own shell — not the Proxmox shell. The prompt
looks like:

```
/admin1-> 
```

Run the two racadm commands:

```
racadm set BIOS.StorageSettings.HddSeq Enabled
racadm jobqueue create BIOS.Setup.1-1
```

Expected output for each:

```
/admin1-> racadm set BIOS.StorageSettings.HddSeq Enabled
[Key=BIOS.Setup.1-1#StorageSettings]
RAC1017: Successfully modified the object value and the change is in
         pending state.

/admin1-> racadm jobqueue create BIOS.Setup.1-1
RAC1024: Successfully scheduled a job.
Verify the job status using "racadm jobqueue view -i JID_xxxxxxxxxxxx"
Commit JID = JID_123456789012
Reboot Required = Yes
```

Type `exit` to leave the iDRAC shell. You are now back on the Proxmox
host.

The BIOS setting is **queued** but not yet applied — the server must POST
once for it to take effect. The next reboot (Step 10.5 will trigger one)
will apply it automatically.

> **Why not reboot right now?** Because we are about to install the Linux
> stagger service too, and one reboot covers both changes. Keep going.

---

### Step 10.5 — Install the Linux stagger spin-up service

The Linux layer is a safety net: if a drive did not spin up during BIOS POST
(for example, it was in standby from a previous run), this service wakes it
up during early boot, one at a time, before the storage stack comes online.

Copy the script into place:

```bash
cp /opt/local_proxmox/scripts/stagger-spinup.sh /usr/local/sbin/stagger-spinup.sh
chmod +x /usr/local/sbin/stagger-spinup.sh
```

Copy the systemd unit:

```bash
cp /opt/local_proxmox/scripts/stagger-spinup.service /etc/systemd/system/
```

Enable the service — **do not start it manually**. The unit is wired into
`sysinit.target` and is meant to run only during the early boot window.
Running it ad-hoc after boot is harmless (drives are already spun up, it
will log "already active — skipping" for each) but pointless:

```bash
systemctl daemon-reload
systemctl enable stagger-spinup.service
```

Expected output:

```
Created symlink /etc/systemd/system/sysinit.target.wants/stagger-spinup.service
  → /etc/systemd/system/stagger-spinup.service.
```

Verify the unit is enabled (but inactive, as expected):

```bash
systemctl status stagger-spinup.service
```

Expected output:

```
● stagger-spinup.service - Stagger hard drive spin-up to limit PSU current surge
     Loaded: loaded (/etc/systemd/system/stagger-spinup.service; enabled; preset: enabled)
     Active: inactive (dead)
```

`inactive (dead)` is correct — it is a `Type=oneshot` unit that ran once at
the last boot (when it did not yet exist) and will run on the next boot.

---

### Step 10.6 — Reboot to apply both the BIOS setting and the Linux service

```bash
reboot
```

**Pay attention during this boot.** You are testing two things at once:

1. **Listen to the drives.** Instead of the normal "all 12 drives click
   awake at once" chorus, you should hear them spin up in sequence — a
   quick series of individual clicks spread across 30–40 seconds during
   POST. This is the iDRAC BIOS setting doing its job.
2. **Watch the fans.** Right after POST they will briefly hit 100% again
   (iDRAC starts in automatic mode every boot). Within 30–60 seconds of
   Proxmox being up, the fan control service should take over and quiet
   them down.

Wait about 90 seconds after the reboot, then SSH back in:

```bash
ssh root@192.168.1.10
```

---

### Step 10.7 — Verify everything came back correctly

Fan service running and fans quiet:

```bash
systemctl is-active fan-control.service
# Expected: active

ipmitool sdr type Fan | head -3
# Expected: fans at ~2000–3000 RPM, not 12000+
```

Stagger service ran successfully at boot:

```bash
systemctl status stagger-spinup.service
```

Expected output:

```
● stagger-spinup.service - Stagger hard drive spin-up to limit PSU current surge
     Loaded: loaded (...; enabled; preset: enabled)
     Active: inactive (dead) since <boot time> — oneshot finished
    Process: 456 ExecStart=/usr/local/sbin/stagger-spinup.sh --linux (code=exited, status=0/SUCCESS)
   Main PID: 456 (code=exited, status=0/SUCCESS)
```

`status=0/SUCCESS` is the line that matters — the script ran and exited
cleanly.

Look at what it actually did:

```bash
journalctl -u stagger-spinup.service -b
```

Expected output (one line per drive):

```
Staggering spin-up for 12 drives (3s apart)...
 /dev/sda already active (state: active/idle) — skipping
 Waking /dev/sdb (was: standby)
 Waking /dev/sdc (was: standby)
 ...
 Waking /dev/sdm (was: standby)
Stagger complete.
```

Typical: the OS RAID1 mirror (`/dev/sda`) is already active from boot, and
each of the 12 data drives gets woken in sequence.

Confirm the iDRAC BIOS setting stuck (only works if you installed racadm
on the host, otherwise skip — the boot behavior above is the real test):

```bash
# Only if racadm is installed on Proxmox:
racadm get BIOS.StorageSettings.HddSeq
# Expected: HddSeq=Enabled
```

Otherwise SSH into iDRAC and run the same command there.

---

### Phase 10 complete — where you are now

| What is done | Status |
|---|---|
| Fan control daemon active, fans quiet | ✓ |
| iDRAC BIOS hard disk drive sequencing enabled | ✓ |
| Linux stagger spin-up service enabled for future boots | ✓ |
| Verified both survive a reboot cleanly | ✓ |

**Next:** Phase 11 — Create the three VMs in the Proxmox web UI, attach
GPUs / Coral USB / raw data drives, and install Ubuntu inside each.

---

## Phase 11 — Create the VMs

**What this phase does:** Creates three VMs in the Proxmox web interface, attaches
their hardware (GPUs, Coral USB, raw data drives), installs Ubuntu Server inside
each one, and verifies SSH access.

**Prerequisites from earlier phases:**
- GPU passthrough working: both GPUs show `vfio-pci` in `lspci` (Phase 9)
- Bay map filled in: `/dev/disk/by-id/...` paths known for all 12 drives (Phase 8)
- VM config examples updated with real paths and PCI addresses (Phases 8–9)
- Fan control and stagger services installed and verified (Phase 10)

---

### Step 11.1 — Download the Ubuntu installer ISO

The Frigate VM needs Ubuntu Server 24.04 LTS. On your workstation, go to
**ubuntu.com/download/server** and download
`ubuntu-24.04.1-live-server-amd64.iso` (or the latest 24.04 point release).

---

### Step 11.2 — Upload the ISO to Proxmox

In the **Proxmox web UI** (`https://192.168.1.10:8006`):

1. In the left panel, click your node name (e.g. **pve**) → **local** storage
2. Click the **ISO Images** tab
3. Click **Upload**
4. Click **Select File** → choose the `ubuntu-24.04.*-live-server-amd64.iso`
5. Click **Upload**

The upload progress bar shows while transferring. When it completes the ISO
appears in the list.

> **Faster alternative** — download directly on the Proxmox host:
> ```bash
> cd /var/lib/vz/template/iso/
> curl -LO "https://releases.ubuntu.com/24.04/ubuntu-24.04.1-live-server-amd64.iso"
> ```
> The ISO appears in the web UI list immediately after the download finishes.

---

### Step 11.3 — Create VM 100 (Frigate) via the wizard

In the Proxmox web UI, click **Create VM** (top-right button).

**Tab: General**

| Field | Value |
|-------|-------|
| Node | pve |
| VM ID | 100 |
| Name | frigate |

Click **Next**.

**Tab: OS**

| Field | Value |
|-------|-------|
| ISO image | ubuntu-24.04.1-live-server-amd64.iso |
| OS Type | Linux |
| Version | 6.x - 2.6 Kernel |

Click **Next**.

**Tab: System**

| Field | Value |
|-------|-------|
| Machine | q35 |
| BIOS | OVMF (UEFI) |
| Add EFI Disk | checked |
| EFI Storage | local-lvm |
| Pre-Enrolled Keys | **unchecked** |
| SCSI Controller | VirtIO SCSI Single |

> **Why q35 + OVMF?** GPU passthrough requires PCIe bus emulation, which only
> `q35` provides. `i440fx` (the older default) does not support PCIe correctly
> for VFIO passthrough.

> **Pre-Enrolled Keys must be unchecked.** Enabling it turns on Secure Boot,
> which blocks NVIDIA kernel modules from loading in the guest.

Click **Next**.

**Tab: Disks**

| Field | Value |
|-------|-------|
| Bus/Device | SCSI / 0 |
| Storage | local-lvm |
| Disk size (GiB) | 64 |
| Cache | Write back |
| Discard | checked (if local-lvm is on SSD) |

Click **Next**.

**Tab: CPU**

| Field | Value |
|-------|-------|
| Sockets | 1 |
| Cores | 8 |
| Type | host |

> **Why `host` CPU type?** It exposes the real CPU feature flags, which NVIDIA
> drivers expect. Without it, `nvidia-smi` may work but performance-sensitive
> GPU features fail silently.

Click **Next**.

**Tab: Memory**

| Field | Value |
|-------|-------|
| Memory (MiB) | 16384 |

Click **Next**.

**Tab: Network**

| Field | Value |
|-------|-------|
| Bridge | vmbr0 |
| Model | VirtIO (paravirt) |
| Firewall | checked |

Click **Next**, then **Finish**.

VM 100 now appears in the left panel. **Do not start it yet** — the GPU, Coral
USB, and data drives must be added first.

---

### Step 11.4 — Add GPU passthrough to VM 100

In the left panel, click **100 (frigate)** → **Hardware** tab.

Click **Add** → **PCI Device**.

| Field | Value |
|-------|-------|
| Raw Device | select GPU #1: e.g. `0000:03:00.0 NVIDIA GP106GL [Quadro P2200]` |
| All Functions | **checked** |
| Primary GPU | **checked** |
| PCI-Express | **checked** |

> **All Functions** passes both `03:00.0` (VGA) and `03:00.1` (HDMI audio) as
> a unit. Without it the audio sibling stays on the host.

> **Primary GPU** (`x-vga=1` in the config) tells the VM this is its display
> adapter. Required for console output in the guest before GPU drivers load.

Click **Add**.

---

### Step 11.5 — Add Coral USB to VM 100

Still in VM 100's **Hardware** tab.

Click **Add** → **USB Device**.

First entry (pre-init ID):

| Field | Value |
|-------|-------|
| Use USB Vendor/Device ID | selected |
| Vendor ID | 1a6e |
| Device ID | 089a |

Click **Add**.

Click **Add** → **USB Device** again.

Second entry (post-init ID):

| Field | Value |
|-------|-------|
| Use USB Vendor/Device ID | selected |
| Vendor ID | 18d1 |
| Device ID | 9302 |

Click **Add**.

> **Why two entries?** The Coral USB presents as `1a6e:089a` before Frigate
> loads firmware onto it, then re-enumerates as `18d1:9302` after firmware
> loads. Both must be passed through or the second enumeration will not be
> accessible inside the VM.

> **The Coral must be physically plugged in to the R730xd before starting the
> VM.** If it is not connected, the VM boots fine but the USB devices will
> not appear.

---

### Step 11.6 — Add raw data drives to VM 100 via CLI

The web UI does not support raw block device passthrough cleanly — use the
Proxmox CLI. SSH into the host:

```bash
ssh root@192.168.1.10
```

Run one `qm set` command per drive, replacing the `PLACEHOLDER_BAYx` paths
with the real by-id paths from your `hardware-layout.md`:

```bash
qm set 100 -scsi1 /dev/disk/by-id/PLACEHOLDER_BAY1
qm set 100 -scsi2 /dev/disk/by-id/PLACEHOLDER_BAY2
qm set 100 -scsi3 /dev/disk/by-id/PLACEHOLDER_BAY3
qm set 100 -scsi4 /dev/disk/by-id/PLACEHOLDER_BAY4
qm set 100 -scsi5 /dev/disk/by-id/PLACEHOLDER_BAY5
qm set 100 -scsi6 /dev/disk/by-id/PLACEHOLDER_BAY6
qm set 100 -scsi7 /dev/disk/by-id/PLACEHOLDER_BAY7
qm set 100 -scsi8 /dev/disk/by-id/PLACEHOLDER_BAY8
```

Each command is silent on success. Confirm all drives are attached:

```bash
grep scsi /etc/pve/qemu-server/100.conf
```

Expected output:

```
scsi0: local-lvm:vm-100-disk-0,cache=writeback,size=64G
scsi1: /dev/disk/by-id/scsi-35000cca23b7d4eb8,size=0
scsi2: /dev/disk/by-id/scsi-35000cca23b5e1234,size=0
...
scsi8: /dev/disk/by-id/scsi-35000cca23bab1234,size=0
```

> **`size=0` is correct** for raw disk passthrough — Proxmox defers sizing to
> the device itself. A non-zero size here indicates the drive was added wrong.

---

### Step 11.7 — Create VM 101 (general purpose with GPU)

Click **Create VM** in the web UI.

Use the same wizard settings as VM 100 except:

| Tab | Value |
|-----|-------|
| General | VM ID: **101**, Name: **vm101** |
| CPU | 8 cores, host |
| Memory | 16384 MiB |
| Disk | 64 GiB on local-lvm |

After the wizard completes, add the second GPU in the **Hardware** tab:

Click **Add** → **PCI Device** → select GPU #2 (e.g. `0000:04:00.0 NVIDIA
GP106GL [Quadro P2200]`). Check **All Functions**, **Primary GPU**,
**PCI-Express**. Click **Add**.

No Coral USB for VM 101.

Add the two data drives via CLI:

```bash
qm set 101 -scsi1 /dev/disk/by-id/PLACEHOLDER_BAY9
qm set 101 -scsi2 /dev/disk/by-id/PLACEHOLDER_BAY10
```

---

### Step 11.8 — Create VM 102 (storage/utility, no GPU)

Click **Create VM** again.

| Tab | Value |
|-----|-------|
| General | VM ID: **102**, Name: **vm102** |
| CPU | 4 cores, host |
| Memory | 8192 MiB |
| Disk | 32 GiB on local-lvm |

No PCI device, no USB devices.

Add the two data drives:

```bash
qm set 102 -scsi1 /dev/disk/by-id/PLACEHOLDER_BAY11
qm set 102 -scsi2 /dev/disk/by-id/PLACEHOLDER_BAY12
```

---

### Step 11.9 — Install Ubuntu in VM 100

In the left panel, click **100 (frigate)** → click **Start** (▶ button).

Open the console: click **Console** at the top. This opens a noVNC session in
your browser.

Wait for the Ubuntu GRUB menu to appear. Select **Try or Install Ubuntu
Server** and press Enter.

Work through the Ubuntu Server installer:

1. **Language:** English (or your preference)
2. **Keyboard:** your layout
3. **Type of install:** Ubuntu Server (not minimised — minimised is missing tools
   you need)
4. **Network connections:** the VirtIO NIC auto-detects and gets a DHCP IP.
   **Note the IP address** — you will use it for SSH in the next step.
5. **Proxy:** leave blank
6. **Ubuntu archive mirror:** leave at default (or a nearby mirror)
7. **Storage:**
   - **Guided storage layout** → **Use an entire disk**
   - Select the **64GB** virtual disk (the scsi0 OS disk — shows as ~64.4 GB)
   - Leave LVM enabled
   - **Do not select the large 3.6TB data drives** — those will become a ZFS
     pool in Phase 12
8. **Profile setup:**
   - Server's name: `frigate`
   - Username: `ubuntu` (or your preference)
   - Password: something strong
9. **SSH:** check **Install OpenSSH server** → Yes
10. **Featured server snaps:** skip all

Click **Done** on the summary screen. The install takes 5–10 minutes.

When installation finishes: **Reboot Now**. Proxmox ejects the ISO
automatically. When the login prompt appears in the console, the OS is ready.

---

### Step 11.10 — Find VM 100's IP and test SSH

Log in at the console. Check the assigned IP:

```bash
ip addr show ens18
```

Expected output:

```
2: ens18: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
    inet 192.168.1.XXX/24 brd 192.168.1.255 scope global ens18
```

From your workstation, verify SSH works:

```bash
ssh ubuntu@192.168.1.XXX
```

If SSH connects, close the noVNC console tab — you will not need it again.

> **Recommended:** Set a DHCP reservation in your router for VM 100's MAC
> address so its IP stays stable. Frigate's web UI and stream URLs depend on
> a predictable IP.

---

### Step 11.11 — Install Ubuntu in VMs 101 and 102

Repeat steps 11.9–11.10 for VMs 101 and 102. The installer flow is identical.
Use `vm101` and `vm102` as hostnames.

During the storage step in each VM: install Ubuntu only on the small OS disk.
Leave the large data drives untouched — they are for you to configure later.

---

### Phase 11 complete — where you are now

| What is done | Status |
|---|---|
| Ubuntu Server 24.04 ISO uploaded to Proxmox | ✓ |
| VM 100 created: GPU #1, Coral USB (×2), 8 raw data drives | ✓ |
| VM 101 created: GPU #2, 2 raw data drives | ✓ |
| VM 102 created: 2 raw data drives, no GPU | ✓ |
| Ubuntu installed and SSH accessible in all three VMs | ✓ |

**Next:** Phase 12 — install NVIDIA drivers, Docker, and Frigate inside VM 100.

---

## Phase 12 — Deploy Frigate in VM 100

**What this phase does:** Installs the NVIDIA driver and Docker inside VM 100,
creates a ZFS storage pool from the 8 data drives, then deploys Frigate NVR
with GPU-accelerated video decode and Coral object detection.

**Prerequisites:**
- VM 100 running Ubuntu Server 24.04 with SSH access (Phase 11)
- NVIDIA Quadro P2200 passed through (PCIe device visible in guest)
- Google Coral USB passed through (USB device visible in guest)
- 8 raw data drives visible as block devices inside the VM
- Frigate config files from this repo (`frigate/docker-compose.yml` and
  `frigate/config.yml`)

All commands in this phase run **inside VM 100** — not on the Proxmox host.

---

### Step 12.1 — SSH into VM 100 and switch to root

```bash
ssh ubuntu@192.168.1.XXX   # VM 100's IP from Phase 11
sudo -i
```

---

### Step 12.2 — Verify the GPU is visible

```bash
lspci | grep -i nvidia
```

Expected:

```
06:10.0 VGA compatible controller: NVIDIA Corporation GP106GL [Quadro P2200] (rev a1)
06:10.1 Audio device: NVIDIA Corporation GP106 High Definition Audio Controller (rev a1)
```

> **The PCI address inside the VM (e.g. `06:10.0`) will differ from the host
> address (`03:00.0`).** QEMU re-numbers the virtual PCIe bus. This is normal.

If neither device appears, check that `hostpci0` is set correctly in
`/etc/pve/qemu-server/100.conf` on the Proxmox host, and that Phase 9
completed successfully (GPU showing `vfio-pci` on the host).

---

### Step 12.3 — Install the NVIDIA driver

```bash
apt update
apt install -y nvidia-driver-535
```

This installs the driver and all required kernel modules. Takes 2–4 minutes.

> If the installer asks about Secure Boot MOK (Machine Owner Key), press OK
> to dismiss — Secure Boot is off in this VM (pre-enrolled-keys was unchecked
> in Phase 11), so the prompt has no effect.

Reboot the VM to load the driver:

```bash
reboot
```

SSH back in after ~30 seconds:

```bash
ssh ubuntu@192.168.1.XXX
sudo -i
```

---

### Step 12.4 — Verify nvidia-smi

```bash
nvidia-smi
```

Expected output:

```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 535.xxx.xx                 Driver Version: 535.xxx.xx    CUDA Version: 12.x |
|-----------------------------------------+------------------------+----------------------|
| GPU  Name                Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
|=========================================+========================+======================|
|   0  Quadro P2200            Off       | 00000000:06:10.0   Off |                  N/A |
| 41%   42C    P8              10W /  75W |      0MiB /  5120MiB  |      0%      Default |
+-----------------------------------------------------------------------------------------+
```

Key things to verify:
- **Driver Version: 535.xxx.xx** — driver loaded
- **Quadro P2200** — correct GPU model
- **5120 MiB** — full 5 GB memory visible (not a partial amount)

If `nvidia-smi` returns `No devices were found`:
```bash
dmesg | grep -i nvidia | tail -20
```
Look for Secure Boot signature errors. If present, confirm `pre-enrolled-keys=0`
in the VM's `efidisk0` line in Proxmox.

---

### Step 12.5 — Install Docker

```bash
curl -fsSL https://get.docker.com | sh
```

This runs Docker's official install script and installs Docker Engine with the
Compose plugin. Takes about 1 minute.

Verify:

```bash
docker version
```

Both Client and Server sections should show a version number.

Enable Docker to start at boot:

```bash
systemctl enable docker
```

---

### Step 12.6 — Install NVIDIA Container Toolkit

This allows Docker containers to access the GPU. Without it Frigate cannot use
the Quadro for hardware video decode.

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt update
apt install -y nvidia-container-toolkit

nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
```

Expected output from `nvidia-ctk`:

```
INFO    Configured /etc/docker/daemon.json
```

---

### Step 12.7 — Test GPU access in Docker

```bash
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

Expected: the same `nvidia-smi` table from Step 12.4, now running inside a
container. If you see `Error: no runtime "nvidia"`, run
`systemctl restart docker` and try again.

---

### Step 12.8 — Verify Coral USB

```bash
lsusb
```

Expected — one of these IDs should be present:

```
Bus 001 Device 002: ID 1a6e:089a Global Unichip Corp.
```

or (if previously initialized):

```
Bus 001 Device 002: ID 18d1:9302 Google Inc.
```

If neither appears: verify both USB passthrough entries (`usb0` and `usb1`)
are in the VM's Hardware tab, and that the Coral is physically plugged in to
the R730xd.

---

### Step 12.9 — Create the ZFS storage pool

Check which block devices are the data drives (the large ones — not the 64 GB
OS disk):

```bash
lsblk -d -o NAME,SIZE,TYPE | grep disk
```

Expected:

```
NAME   SIZE TYPE
sda     64G disk   ← OS disk — do NOT include in the pool
sdb    3.6T disk   ← data drive
sdc    3.6T disk
sdd    3.6T disk
sde    3.6T disk
sdf    3.6T disk
sdg    3.6T disk
sdh    3.6T disk
sdi    3.6T disk   ← data drive 8
```

Install ZFS:

```bash
apt install -y zfsutils-linux
```

Create a RAIDZ2 pool from all 8 data drives. RAIDZ2 tolerates up to 2
simultaneous drive failures:

```bash
zpool create -f frigate-data raidz2 \
  /dev/sdb /dev/sdc /dev/sdd /dev/sde \
  /dev/sdf /dev/sdg /dev/sdh /dev/sdi
```

> **Use `/dev/sdX` paths here, not by-id paths.** The drives have no firmware
> by-id identity inside the VM — ZFS generates its own stable identifiers from
> drive serial numbers.

Set the mount point:

```bash
zfs set mountpoint=/mnt/frigate frigate-data
```

Verify:

```bash
zpool status frigate-data
```

Expected:

```
  pool: frigate-data
 state: ONLINE
config:

    NAME         STATE     READ WRITE CKSUM
    frigate-data ONLINE       0     0     0
      raidz2-0   ONLINE       0     0     0
        sdb      ONLINE       0     0     0
        ...
        sdi      ONLINE       0     0     0
```

Confirm usable capacity:

```bash
df -h /mnt/frigate
```

With 8 × 4TB drives in RAIDZ2, expect roughly 22–24 TB usable.

---

### Step 12.10 — Get the Frigate config files

Clone the repo into the VM:

```bash
git clone https://github.com/outis1one/local_proxmox.git /opt/local_proxmox
```

Copy the Frigate files to the working directory:

```bash
mkdir -p /opt/frigate
cp /opt/local_proxmox/frigate/docker-compose.yml /opt/frigate/
cp /opt/local_proxmox/frigate/config.yml /opt/frigate/
```

---

### Step 12.11 — Edit docker-compose.yml

```bash
nano /opt/frigate/docker-compose.yml
```

Change the RTSP password placeholder:

```yaml
environment:
  FRIGATE_RTSP_PASSWORD: "changeme"   # ← set a real password here
```

The `{FRIGATE_RTSP_PASSWORD}` placeholder in `config.yml` will be substituted
with this value at runtime. You will reference it in camera RTSP URLs.

No other changes are needed unless:
- You have 8+ cameras → increase `shm_size` from `256mb` to `512mb`
- Your recordings path is different from `/mnt/frigate`

Save: **Ctrl+O**, Enter, **Ctrl+X**.

---

### Step 12.12 — Edit config.yml and add your cameras

```bash
nano /opt/frigate/config.yml
```

Find the `cameras:` section at the bottom and fill in your camera details:

```yaml
cameras:
  front_door:                          # ← rename to anything (no spaces)
    ffmpeg:
      inputs:
        - path: rtsp://admin:{FRIGATE_RTSP_PASSWORD}@192.168.1.XXX/stream1
          #                                           ^^^^^^^^^^^^^^^^^ your camera IP + RTSP path
          roles:
            - detect
            - record
```

Common RTSP path formats by brand:

| Brand | RTSP URL format |
|-------|----------------|
| Hikvision | `rtsp://user:{password}@IP/Streaming/Channels/101` |
| Dahua | `rtsp://user:{password}@IP/cam/realmonitor?channel=1&subtype=0` |
| Reolink | `rtsp://user:{password}@IP/h264Preview_01_main` |
| Amcrest | `rtsp://user:{password}@IP/cam/realmonitor?channel=1&subtype=0` |

For H.265 cameras, uncomment the per-camera hwaccel override:

```yaml
    ffmpeg:
      hwaccel_args: preset-nvidia-h265
```

To add more cameras, duplicate the entire `front_door:` block (including
indentation) and change the name and IP.

Save: **Ctrl+O**, Enter, **Ctrl+X**.

---

### Step 12.13 — Start Frigate

```bash
cd /opt/frigate
docker compose up -d
```

On the first run, Docker pulls the Frigate image (~1 GB). Progress bars show
the download.

Watch the startup logs:

```bash
docker compose logs -f
```

A successful start looks like:

```
frigate  | [INFO]    Starting Frigate...
frigate  | [INFO]    Connected to EdgeTPU device: usb
frigate  | [INFO]    Loading NVIDIA GPU: Quadro P2200
frigate  | [INFO]    Starting camera: front_door
frigate  | [INFO]    Frigate is running
```

Key lines:
- **Connected to EdgeTPU device: usb** — Coral detected, inference running
- **Loading NVIDIA GPU** — NVDEC hardware decode active
- **Starting camera: [name]** — stream connected

Press **Ctrl+C** to stop following logs. Frigate continues running in the
background.

> **Common first-start errors:**
>
> `Failed to connect to EdgeTPU` — run `lsusb` in the VM to confirm
> `1a6e:089a` or `18d1:9302` is present. Both USB passthrough entries must be
> in the VM's Hardware tab.
>
> `Failed to connect to [camera name]` — RTSP URL is wrong. Check the URL
> format for your camera model. The Frigate UI shows the stream as Offline.
>
> `no runtime "nvidia"` — re-run `nvidia-ctk runtime configure --runtime=docker
> && systemctl restart docker`.

---

### Step 12.14 — Access the Frigate web UI

In a browser on your workstation:

```
http://192.168.1.XXX:5000
```

The Frigate dashboard shows live camera feeds, detection events, and system
stats. Navigate to **System → Stats** to confirm:
- GPU utilization is shown (Quadro P2200)
- Coral inference is running
- CPU usage is low (NVDEC handling decode, Coral handling detection)

---

### Phase 12 complete — full system summary

| What is done | Status |
|---|---|
| NVIDIA driver 535 installed, verified with nvidia-smi | ✓ |
| Docker and NVIDIA Container Toolkit configured | ✓ |
| GPU accessible inside Docker containers | ✓ |
| ZFS RAIDZ2 pool created from 8 data drives | ✓ |
| Frigate running with NVDEC decode and Coral inference | ✓ |
| Cameras configured in config.yml | ✓ |
| Web UI accessible at http://vm100-ip:5000 | ✓ |

---

**Full system status:**

| Layer | Component | Running |
|-------|-----------|---------|
| Hardware | Dell R730xd, PERC H730, 12 drives, 2× Quadro P2200, Coral USB | ✓ |
| Proxmox host | IOMMU active, GPUs held by vfio-pci | ✓ |
| Services | fan-control (quiet fans), stagger-spinup (PSU protection) | ✓ |
| VM 100 | Ubuntu 24.04, GPU passthrough, 8 drives, Frigate NVR | ✓ |
| VM 101 | Ubuntu 24.04, GPU passthrough, 2 drives | ready |
| VM 102 | Ubuntu 24.04, 2 drives | ready |
