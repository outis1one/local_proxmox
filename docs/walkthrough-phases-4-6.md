# Phases 4–6: RAID Config, Proxmox Install, Post-Install
### Dell R730xd — Button-by-button walkthrough

---

## Phase 4 — H730 RAID Configuration

**Goal:** Mirror the two 2.5" rear drives together so a single drive failure
cannot take down Proxmox. Leave every 3.5" drive untouched — the `perc-nonraid.sh`
script handles those later from inside Proxmox.

**Why mirror the OS drives here instead of using ZFS?** The H730 presents the
RAID1 mirror as a single virtual disk to the OS. Proxmox installs onto it and
never needs to think about the fact that two physical drives are underneath.
This is the simplest and most reliable approach for an OS volume.

---

### Step 4.1 — Enter Lifecycle Controller

Power on (or reboot) the server and press **F10** at the Dell splash screen.

Wait for Lifecycle Controller to load. You will see the main menu on the left:

```
Home
Firmware Update
OS Deployment
RAID Configuration     ← go here
Hardware Configuration
Settings
```

Arrow to **RAID Configuration** and press **Enter**.

---

### Step 4.2 — Open the RAID configuration wizard

You will see:

```
RAID Configuration

  View Current Configuration
  Create New VD
  ...
```

First, click **View Current Configuration** to see what is already there.

You are looking at the physical drives the H730 can see. Drives are listed under
their controller — it will say something like:

```
PERC H730 Mini (Slot 0)

  Physical Disks:
    Port 0: SEAGATE  ST4000NM0023  4.0 TB  State: Unconfigured Good
    Port 1: SEAGATE  ST4000NM0023  4.0 TB  State: Unconfigured Good
    ...
    Port 8: TOSHIBA  MK1401GRRB   146 GB  State: Unconfigured Good   ← 2.5"
    Port 9: TOSHIBA  MK1401GRRB   146 GB  State: Unconfigured Good   ← 2.5"
```

> **Identifying the 2.5" OS drives:** They will be noticeably smaller than the
> 3.5" drives — likely 146 GB, 300 GB, 600 GB (SAS) or 120–480 GB (SSD).
> The 3.5" drives will be 1 TB, 2 TB, 4 TB, or larger. Size is the giveaway.

> **If drives show "Foreign Configuration":** They were previously part of a
> RAID array. See Step 4.3a before continuing.

> **If the 2.5" drives appear under a different controller** (e.g., "PERC H330
> Mini"): The R730xd sometimes puts the rear bays on a separate mini controller.
> That is fine — just create the RAID1 on whichever controller owns those drives.

Press **Back** to return to the RAID Configuration menu.

---

### Step 4.3a — Clear foreign configurations (only if needed)

If any drives showed "Foreign Configuration" in Step 4.2, you need to clear
them before you can create a new virtual disk.

In the RAID Configuration menu, look for:

```
Clear Foreign Configuration
```

Select it, choose **All Foreign Configurations**, click **Apply**.

A warning will appear saying all data on those drives will be lost — click **Yes**.
(We are building a new system so there is nothing to keep.)

After clearing, go back to **View Current Configuration** and confirm the drives
now show **Unconfigured Good**.

---

### Step 4.4 — Create the RAID 1 virtual disk

In the RAID Configuration menu, select **Create New VD** and press **Enter**.

The wizard walks you through four screens:

---

**Screen 1 — Select RAID Level**

```
Select RAID Level:

  RAID 0  (no redundancy, faster)
  RAID 1  (mirror, one drive can fail)    ← select this
  RAID 5  (requires 3+ drives)
  RAID 6  (requires 4+ drives)
  RAID 10 (requires 4+ drives)
```

Select **RAID 1** and click **Next**.

---

**Screen 2 — Select Physical Disks**

A list of all available physical disks appears. You need to select **only the
two 2.5" drives**. Do not select any 3.5" drives.

Click the checkbox next to each of the two 2.5" drives (identified by their
smaller size). Leave all 3.5" drives unchecked.

Click **Next**.

---

**Screen 3 — Virtual Disk Attributes**

```
Virtual Disk Name:    OS-Mirror
Virtual Disk Size:    (auto-filled — leave it)
Strip Element Size:   64KB   (leave default)
Read Policy:          Adaptive Read Ahead  (leave default)
Write Policy:         Write Back           (leave default)
Disk Cache Policy:    Enabled              (leave default)
```

The only thing you need to change is the name — type `OS-Mirror` so it is easy
to identify. Everything else can stay at defaults.

Click **Next**.

---

**Screen 4 — Confirm**

Review the summary. It should show:
- RAID Level: 1
- Physical Disks: 2 (your 2.5" drives)
- Virtual Disk Size: whatever the smaller of the two drives is

Click **Finish**.

---

### Step 4.5 — Initialize the virtual disk

After creating the VD, Lifecycle Controller will ask about initialization:

```
Initialize virtual disk?
  Fast Initialize    ← select this
  Full Initialize    (writes zeros to every sector — takes hours, not needed)
  Skip
```

Select **Fast Initialize** and click **OK**.

Fast initialization takes 30–60 seconds. A progress bar will appear. Wait for it.

---

### Step 4.6 — Verify and exit

When initialization finishes, go back to **View Current Configuration**.

You should now see:

```
PERC H730 Mini

  Virtual Disks:
    VD 0: OS-Mirror  RAID 1  ~146 GB  State: Optimal

  Physical Disks:
    Port 0–7:  3.5" drives  State: Unconfigured Good
    Port 8–9:  2.5" drives  State: Online (member of VD 0)
```

The 3.5" drives should all show **Unconfigured Good**. That is exactly what you
want. Leave them that way.

Click **Back** repeatedly until you reach the Lifecycle Controller home screen,
then click **Exit**. The server will reboot.

---

## Phase 5 — Install Proxmox VE 9.1

### Step 5.1 — Download the Proxmox ISO

On your other computer, open a browser and go to:

```
https://www.proxmox.com/en/downloads
```

Click **Proxmox Virtual Environment** → find the latest **Proxmox VE 9.x ISO
Installer** and click **Download**.

The file will be named something like `proxmox-ve_9.1-1.iso` and is about 1 GB.

---

### Step 5.2 — Write the ISO to a USB drive

You need to write the ISO as a disk image (not copy the file). Use one of these
tools depending on your computer:

#### Windows — Rufus (free, no install needed)

1. Download Rufus from: **https://rufus.ie** (click the first .exe link)
2. Plug in your USB drive (8 GB or larger — all data on it will be erased)
3. Open Rufus
4. **Device:** select your USB drive from the dropdown
5. **Boot selection:** click **SELECT** and choose the Proxmox ISO file
6. **Partition scheme:** select **GPT**
7. **Target system:** select **UEFI (non CSM)**
8. Click **START**
9. A dialog appears asking about ISO mode vs DD mode — select **Write in DD Image
   mode** and click **OK**
10. Click **OK** again when warned that the USB will be wiped
11. Wait for it to finish (1–3 minutes), then click **CLOSE**

#### Mac — Balena Etcher (free)

1. Download from: **https://etcher.balena.io** — click **Download for macOS**
2. Open Etcher
3. Click **Flash from file** → select the Proxmox ISO
4. Click **Select target** → select your USB drive
5. Click **Flash** — enter your Mac password if prompted
6. Wait for it to finish

#### Linux — terminal

```bash
# Find your USB drive device name (look for your drive size)
lsblk

# Write the ISO (replace sdX with your actual USB device, e.g. sdb — NOT sdb1)
dd if=proxmox-ve_9.1-1.iso of=/dev/sdX bs=1M status=progress conv=fsync
sync
```

---

### Step 5.3 — Boot the server from USB

1. Plug the USB drive into one of the USB ports on the front or back of the server
2. Power on (or reboot) the server
3. At the Dell splash screen, press **F11**

The **Boot Manager** screen appears:

```
Boot Manager

  BIOS Boot Menu
  UEFI Boot Menu      ← go here
  One-shot BIOS Boot Menu
  ...
```

Arrow to **UEFI Boot Menu** and press **Enter**.

You will see a list of bootable devices. Look for your USB drive — it will be
listed as something like:

```
UEFI: SanDisk Ultra USB 3.0, Partition 1
```

Arrow to it and press **Enter**.

> **If the USB does not appear in the UEFI Boot Menu:** Make sure Rufus wrote in
> DD mode and GPT was selected (Step 5.2). Legacy/MBR USB drives will not appear
> in the UEFI menu.

---

### Step 5.4 — Proxmox installer boot menu

The server boots from the USB and shows the Proxmox boot menu — white text on
a blue/dark background:

```
Proxmox VE Installer

  Install Proxmox VE (Graphical)     ← select this
  Install Proxmox VE (Terminal UI)
  Advanced Options
  ...
```

Arrow to **Install Proxmox VE (Graphical)** and press **Enter**.

The graphical installer loads. This takes about 30–60 seconds.

---

### Step 5.5 — End User License Agreement

The EULA screen appears. Read it or don't — click **I agree** at the bottom right.

---

### Step 5.6 — Target disk selection

This is the most important screen. You are choosing where Proxmox installs.

You will see a dropdown labeled **Target Harddisk**. Click it.

The list shows all visible storage. You are looking for the RAID1 virtual disk
you created in Phase 4. It will appear as a single disk — something like:

```
/dev/sda  (146.00 GB)   ← this is the OS-Mirror RAID1 VD
/dev/sdb  (4.00 TB)
/dev/sdc  (4.00 TB)
...
```

Select the small one — your OS-Mirror virtual disk (146 GB or whatever size your
2.5" drives are).

> **Do not select a 3.5" drive.** Those are your VM data drives.

**Filesystem:** Click the **Options** button next to the disk selector.

```
Filesystem:   ext4    ← leave this as ext4
```

Leave it as `ext4`. The H730 RAID1 already gives you drive redundancy. Adding
ZFS here would be redundant overhead with no benefit.

Click **Next**.

---

### Step 5.7 — Location and timezone

```
Country:   [type your country, e.g. United States]
Time Zone: [auto-filled based on country, e.g. America/New_York]
Keyboard:  [your keyboard layout, e.g. U.S. English]
```

Adjust if needed. Click **Next**.

---

### Step 5.8 — Password and email

```
Password:         [choose a strong root password — write it down]
Confirm:          [same password again]
Email:            [any email address — used for system alerts]
```

> The root password is how you log into Proxmox. If you forget it, recovery is
> painful. Write it on a piece of paper and put it somewhere safe.

Click **Next**.

---

### Step 5.9 — Network configuration

```
Management Interface:  [auto-selected — usually em1 or eno1, the first NIC]
Hostname (FQDN):       pve.local
IP Address:            192.168.1.10    ← change to an IP on your network
Netmask:               255.255.255.0
Gateway:               192.168.1.1     ← your router's IP
DNS Server:            192.168.1.1     ← your router's IP (or 8.8.8.8)
```

**Choosing a static IP for Proxmox:**
- Log into your router and find its DHCP range
- Pick an IP outside that range (same subnet)
- Example: if DHCP is 192.168.1.100–200, use 192.168.1.10
- This IP is how you will reach the Proxmox web UI and SSH from now on

Click **Next**.

---

### Step 5.10 — Summary and install

The installer shows a summary of everything you chose. Confirm:
- Target disk: your small RAID1 virtual disk
- Filesystem: ext4
- Hostname and IP look correct

Click **Install**.

The installation takes 5–10 minutes. A progress bar shows the steps:
- Formatting disk
- Copying files
- Setting up bootloader
- Configuring system

When it finishes you will see:

```
Installation successful!
Remove the installation medium and press Enter to reboot.
```

**Pull the USB drive out**, then press **Enter**.

---

### Step 5.11 — First login to the Proxmox web UI

The server reboots. After about 60 seconds it shows a text console with
Proxmox's login prompt and this message:

```
Welcome to the Proxmox Virtual Environment.

Please use your web browser to configure this server -
connect to: https://192.168.1.10:8006/
```

On your other computer, open a browser and go to:

```
https://192.168.1.10:8006
```

(Use the IP you set in Step 5.9.)

**Certificate warning:** Your browser will show a security warning because
Proxmox uses a self-signed SSL certificate. This is expected and safe on
your local network.

- Chrome/Edge: click **Advanced** → **Proceed to 192.168.1.10 (unsafe)**
- Firefox: click **Advanced** → **Accept the Risk and Continue**

The Proxmox login page appears — a dark interface with two fields:

```
User name:  root
Password:   [the password you set in Step 5.8]
Realm:      Linux PAM standard authentication   ← leave this as-is
```

Click **Login**.

**Subscription nag:** A popup immediately appears saying "No valid subscription".
Click **OK** to dismiss it. This appears every login until you fix the repos in
Phase 6. It does not affect anything.

You are now looking at the Proxmox web interface — the main dashboard.

---

## Phase 6 — Proxmox Post-Install

From this point you will use **SSH** instead of the web console for most tasks.
SSH is faster and lets you paste commands directly.

---

### Step 6.1 — Connect via SSH

On your other computer, open a terminal (Mac/Linux) or PuTTY/Windows Terminal
(Windows) and run:

```bash
ssh root@192.168.1.10
```

Type `yes` when asked to confirm the host fingerprint. Enter your root password.

You will see the Proxmox shell prompt:

```
root@pve:~#
```

All the commands in the rest of this guide are typed here.

---

### Step 6.2 — Fix the package repositories

Proxmox installs with "enterprise" apt repositories configured. These require
a paid subscription and will fail with an authentication error when you try to
update. We switch them to the free community repositories.

Run these commands one at a time:

```bash
# Disable the enterprise repo (comment it out)
echo "# disabled - no subscription" > /etc/apt/sources.list.d/pve-enterprise.list

# Disable the enterprise Ceph repo
echo "# disabled - no subscription" > /etc/apt/sources.list.d/ceph.list

# Add the no-subscription community repo
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list
```

Now update and upgrade all packages:

```bash
apt update && apt dist-upgrade -y
```

This will download and install updates. It may take 5–15 minutes depending on
your internet speed. Answer **Y** if prompted about any config file changes
(just press Enter to accept the default).

When it finishes, reboot:

```bash
reboot
```

Wait about 60 seconds, then SSH back in:

```bash
ssh root@192.168.1.10
```

---

### Step 6.3 — Install the tools the scripts need

```bash
apt install -y ipmitool lsscsi ledmon hdparm git curl
```

What each tool does:

| Tool | Used for |
|------|---------|
| ipmitool | Fan control — sends IPMI commands to iDRAC |
| lsscsi | build-bay-map.sh — lists SCSI drives with details |
| ledmon | build-bay-map.sh — blinks drive bay LEDs for identification |
| hdparm | stagger-spinup.sh — checks drive power state, wakes drives |
| git | Cloning this repo onto the host |
| curl | Downloading packages and health checks |

---

### Step 6.4 — Clone this repo onto the Proxmox host

```bash
git clone https://github.com/outis1one/local_proxmox.git /opt/local_proxmox
chmod +x /opt/local_proxmox/scripts/*.sh
cd /opt/local_proxmox
```

All scripts and configs are now at `/opt/local_proxmox/`.

---

### Step 6.5 — Dismiss the subscription warning permanently (optional)

If the "No valid subscription" popup annoys you every time you log into the
web UI, you can remove it with one command. This does not affect functionality:

```bash
sed -i.bak "s/data.status !== 'Active'/false/g" \
  /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
systemctl restart pveproxy
```

After running this, refresh the Proxmox web UI — the popup will be gone.

---

### Phase 6 complete — where you are now

| What is done | Status |
|---|---|
| Proxmox VE 9.1 installed on RAID1 OS mirror | ✓ |
| Free community repos configured | ✓ |
| All packages up to date | ✓ |
| Tools installed | ✓ |
| Repo cloned to /opt/local_proxmox | ✓ |

**Next:** Phase 7 — Run `perc-nonraid.sh` to convert the 3.5" drives to
non-RAID/per-disk mode, then map the physical bays. That walkthrough is in
`docs/walkthrough-phases-7-9.md`.
