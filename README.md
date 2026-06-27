# Dell R730xd — Complete Setup Walkthrough
### Proxmox VE 9.1 · GPU Passthrough · Frigate NVR

Full button-by-button guide from bare metal to running VMs. All 12 phases in
one document.

---

## Table of Contents

- [Before You Start](#before-you-start)
- [Phase 1 — Firmware Updates](#phase-1--firmware-updates)
- [Phase 2 — iDRAC Setup](#phase-2--idrac-setup)
- [Phase 3 — BIOS Settings](#phase-3--bios-settings)
- [Phase 4 — H730 RAID Configuration](#phase-4--h730-raid-configuration)
- [Phase 5 — Install Proxmox VE 9.1](#phase-5--install-proxmox-ve-91)
- [Phase 6 — Proxmox Post-Install](#phase-6--proxmox-post-install)
- [Phase 7 — Fan Control + Staggered Spin-Up](#phase-7--fan-control--staggered-spin-up)
- [Phase 8 — Convert 3.5" Drives to Non-RAID Mode](#phase-8--convert-35-drives-to-non-raid-mode)
- [Phase 9 — Map Physical Bays to Drives](#phase-9--map-physical-bays-to-drives)
- [Phase 10 — GPU Passthrough Setup](#phase-10--gpu-passthrough-setup)
- [Phase 11 — Create the VMs](#phase-11--create-the-vms)
- [Phase 12 — Deploy Frigate in VM 100](#phase-12--deploy-frigate-in-vm-100)

---

## Before You Start

### What is iDRAC and do I need to pay for it?

iDRAC stands for **Integrated Dell Remote Access Controller**. Ignore the name.
Here is what it actually is:

There is a **second tiny computer built into your server's motherboard**. It has
its own processor, its own RAM, its own network port, and it runs 24 hours a day
as long as the server has power — even when the server is "off". Dell calls this
second computer iDRAC.

This server has **iDRAC8 Express**, which is the version built into the board
at no cost. There is a paid upgrade called iDRAC8 Enterprise but you do not
need it. Here is exactly what Express gives you and what it does not:

**Express includes (everything this guide uses):**
- iDRAC web UI — hardware health dashboard, temperatures, fan speeds, event logs
- Power the server on and off remotely from the web UI
- IPMI over LAN — lets `ipmitool` send fan control commands from Proxmox
- racadm — command-line control used by the stagger spin-up script
- SSH directly into iDRAC for management

**Express does NOT include:**
- Virtual Console — you cannot see the server's screen in a browser window.
  A **physical monitor and keyboard are required** for all setup steps until
  Proxmox is installed and SSH is working. After that you will never need the
  monitor again.
- Virtual Media — you cannot mount an ISO file over the network. A **physical
  USB drive** is required for the Proxmox installer.

Nothing in this guide requires Enterprise. The fan control script and stagger
spin-up both use IPMI over LAN and racadm, which are both available on Express.

**Do you need to pay for anything?** No. iDRAC Express is already there and
covers everything we need. The only other "subscription" people sometimes ask
about is the **Proxmox subscription** (about €100/year for enterprise update
servers and commercial support). You do not need that either — we configure the
free community repositories in Phase 6. The two are completely unrelated.

**Summary: pay nothing, skip nothing. Keep a monitor plugged in through Phase 6.**

---

### What you need on the table before starting

- The server plugged into power and a network switch/router
- A **separate network cable** for the iDRAC port (the small RJ45 on the back
  labeled "iDRAC" — it is separate from the four main NIC ports)
- A **monitor and USB keyboard** plugged into the server — required through
  Phase 5 (the Proxmox installer). iDRAC Express does not include a remote
  KVM, so you cannot see the server's screen from another computer. After
  Proxmox is installed and SSH is working (end of Phase 6) the monitor
  can be unplugged permanently.
- A USB drive (8 GB or larger) — needed later for the Proxmox installer
- Another computer or phone to read this guide

---

## Phase 1 — Firmware Updates

**Why first?** Old firmware has bugs. BIOS from 2016 may not correctly expose
the VT-d settings that GPU passthrough requires. The H730 firmware has had fixes
for JBOD/non-RAID mode. Updating now prevents chasing ghosts later.

**Time required:** 30–90 minutes. The server will reboot several times on its own.

---

### Step 1.1 — Power on and watch the screen

Press the power button on the front of the server.

The screen will show a **Dell splash screen** with the PowerEdge logo. At the
bottom of the screen you will see a line of options, something like:

```
F2 = System Setup    F10 = Lifecycle Controller    F11 = Boot Manager    F12 = PXE Boot
```

These options are only available for about **5–8 seconds** before the server
continues booting. If you miss the window the server will try to boot an OS
(and fail if nothing is installed yet). Just power it off and back on and try again.

---

### Step 1.2 — Enter Lifecycle Controller

Press **F10** when you see the splash screen.

The screen will go blank for 10–30 seconds, then show the **Lifecycle Controller**
loading screen. This is a mini operating system built into the server's firmware.
It has nothing to do with your server's main OS. Wait for it to finish loading —
it can take up to 90 seconds the first time.

When it finishes you will see the **Lifecycle Controller Home** screen with a menu
on the left side:

```
Home
Firmware Update
OS Deployment
RAID Configuration
Hardware Configuration
Settings
```

If it asks you to complete initial setup (language, network), do that first —
use Tab and arrow keys to navigate, Enter to confirm.

---

### Step 1.3 — Go to Firmware Update

Click or arrow-key to **Firmware Update** on the left menu, then press Enter.

You will see:

```
Launch Firmware Update
```

Press Enter on that.

---

### Step 1.4 — Choose your update method

You will be asked how you want to get the firmware. You have two options:

#### Option A — Server has internet access (easiest)

If your network cable is plugged in and the server can reach the internet:

1. Select **HTTPS** (it will say something like "downloads.dell.com")
2. Press **Next**
3. Lifecycle Controller will connect to Dell's servers and **automatically scan
   your server** to find what firmware versions are installed vs. what is available
4. This takes 2–5 minutes — the screen will show a progress bar
5. Skip to Step 1.5

#### Option B — No internet on the server

You need to download the firmware files on another computer first.

1. On your other computer, open a browser and go to:
   **https://www.dell.com/support/home**

2. You need your server's **Service Tag** — it is a 7-character code. Find it:
   - On the **front of the server**: there is a small pull-out plastic tab (like a
     credit card slot) on the left side of the front panel. Pull it out — the
     Service Tag is printed on it.
   - Or: on a sticker on the **top** of the server chassis.
   - Or: it was displayed briefly during POST on the splash screen.

3. On the Dell support page, click **"View products"** or type the Service Tag
   into the search bar at the top. Select your server from the results.

4. Click **"Drivers & Downloads"**

5. You will see a filter panel. Under **"Category"**, select each of these one
   at a time and download the latest version:
   - **iDRAC** — look for "iDRAC8 firmware" — file will end in `.exe` or `.d9`
   - **BIOS** — look for "BIOS" — file ends in `.exe`
   - **RAID** — look for "PERC H730" — file ends in `.exe`

6. Copy all downloaded files onto a **FAT32-formatted USB drive**

7. Plug the USB drive into the server

8. In Lifecycle Controller: select **Local Drive (USB)** and press Next

9. Navigate to the USB drive and select the firmware files

---

### Step 1.5 — Review and apply updates

Lifecycle Controller shows a table of all components with columns like:

```
Component          Current Version    Available Version    Select
---------          ---------------    -----------------    ------
iDRAC8             2.40.40.40        2.85.85.85           [ ]
BIOS               1.2.10            2.14.0               [ ]
PERC H730 Mini     25.4.0.0018       25.5.9.0001          [ ]
```

1. Check the box next to **every component** that shows a newer Available Version
   (you can usually click "Select All")
2. Click **Install and Reboot** (or **Apply**)
3. A warning will say the server will reboot — click **Yes**

The server will now:
- Apply each firmware update
- Reboot automatically between some updates
- Return to the Lifecycle Controller when finished

**Do not power off the server during this process.** Just wait. It can take
30–60 minutes if there are many updates. The screen will show progress.

---

### Step 1.6 — Confirm completion

When all updates are done, Lifecycle Controller returns to its home screen.
You may see a success summary screen first — click **OK** or **Finish**.

To verify everything worked:
1. In Lifecycle Controller, go to **Firmware Update** → **Launch Firmware Update**
   again
2. Run the check one more time
3. The Available Version column should now match Current Version for everything
   you updated (or show no newer version)

Press **Exit** (or **Finish**) to leave Lifecycle Controller. The server will
reboot normally.

---

## Phase 2 — iDRAC Setup

You need to do two things with iDRAC:
1. Give it a **static IP address** so it is always reachable at the same address
2. Enable **IPMI over LAN** so the fan control script can send commands to it

---

### Step 2.1 — Enter System Setup (F2)

Power on (or reboot) the server.

When the Dell splash screen appears, press **F2**.

The screen will go blank briefly, then show the **System Setup Main Menu**:

```
System Setup Main Menu

  System BIOS
  iDRAC Settings
  Device Settings
  Service Tag Settings
```

Use the **arrow keys** to highlight **iDRAC Settings** and press **Enter**.

---

### Step 2.2 — Set a static IP for iDRAC

Inside iDRAC Settings you will see another menu:

```
iDRAC Settings

  Network
  User Configuration
  Smart Card
  Update and Rollback
  ...
```

Arrow down to **Network** and press **Enter**.

The Network screen has several sections. You are looking for the **IPv4 Settings**
section. Use Tab or arrow keys to navigate to these fields:

| Field | What to set |
|-------|-------------|
| Enable NIC | **Enabled** |
| NIC Selection | **Dedicated** (this uses the dedicated iDRAC port on the back) |
| Enable IPv4 | **Enabled** |
| Enable DHCP | **Disabled** ← change this |
| Static IP Address | e.g. `192.168.1.5` (pick an IP outside your router's DHCP range) |
| Static Gateway | your router's IP, e.g. `192.168.1.1` |
| Static Subnet Mask | `255.255.255.0` |
| DNS Server 1 | your router's IP, e.g. `192.168.1.1` |

> **What IP to use?** Log into your router and find its DHCP range — for example
> if DHCP hands out `192.168.1.100` to `192.168.1.200`, pick something outside
> that range like `192.168.1.5`. Write this IP down — you will use it often.

When done, press **Back** or navigate to the bottom and click **Apply**, then **OK**.

---

### Step 2.3 — Enable IPMI over LAN

Still inside iDRAC Settings → Network.

Scroll down past the IPv4 section until you see **IPMI Settings**.

Find:

```
Enable IPMI over LAN:  [ Disabled ]
```

Change this to **Enabled**.

This is the setting that allows `ipmitool` commands (used by the fan control
script) to reach iDRAC over the network.

Click **Apply** at the bottom, then **OK** when asked to confirm.

---

### Step 2.4 — Change the default password

Go back to the iDRAC Settings main menu (press **Back**).

Arrow down to **User Configuration** and press **Enter**.

You will see a list of user slots. **User 1** is the built-in `root` account.
Select it (press Enter).

> **Why change it?** The factory default password is `calvin`. This is printed
> in Dell's public documentation and is widely known. Any device on your network
> could log into your iDRAC if you leave it as-is.

Change:
- **User Name:** leave as `root`
- **Change Password:** set to **Enabled**
- **Password:** enter a strong password
- **Confirm Password:** enter it again

Click **Apply**, then **OK**.

Press **Finish** to exit iDRAC Settings and return to the System Setup Main Menu.

**Do not reboot yet** — you still have BIOS settings to configure in Phase 3.

---

### Step 2.5 — Verify iDRAC from your browser (do after Phase 3)

After you finish Phase 3 and let the server reboot, test iDRAC from your other
computer:

1. Make sure the **dedicated iDRAC network port** (small RJ45 labeled "iDRAC" on
   the server's back panel) is plugged into your switch or router
2. Open a browser on your other computer
3. Go to: `https://192.168.1.5` (whatever static IP you set in Step 2.2)
4. You will see a **certificate warning** — this is normal, iDRAC uses a
   self-signed certificate. Click **Advanced** → **Proceed anyway** (wording
   varies by browser)
5. The iDRAC8 login page appears — a dark Dell-branded page
6. Log in: Username `root`, Password (the one you set in Step 2.4)

You should see the iDRAC dashboard showing system health, temperatures, and fans.
This is your remote window into the server — you can now manage it from your desk.

---

## Phase 3 — BIOS Settings

These settings enable the CPU features that allow devices (GPUs, USB controllers)
to be handed directly to virtual machines. **Every setting below is required.**
Skipping VT-d is the single most common reason GPU passthrough silently fails.

You are still in System Setup from Phase 2 (or press F2 again on reboot).

---

### Step 3.1 — System BIOS → Processor Settings

From the System Setup Main Menu, arrow to **System BIOS** and press Enter.

You will see the System BIOS Settings menu:

```
System BIOS Settings

  System Information
  Memory Settings
  Processor Settings       ← go here
  SATA Settings
  Boot Settings
  Integrated Devices
  Serial Communication
  System Profile Settings
  Power Management
  Security
  Miscellaneous Settings
```

Arrow to **Processor Settings** and press **Enter**.

Find and set these two options:

---

**Virtualization Technology**

This enables the CPU to run virtual machines efficiently. Without it Proxmox
still works but performance is worse.

```
Virtualization Technology:  [ Disabled ]
                            ↓ change to
Virtualization Technology:  [ Enabled  ]
```

Use the arrow keys or spacebar to toggle the value.

---

**VT for Direct I/O** (also shown as "Virtualization Technology for Directed I/O")

This is the critical one. It enables **IOMMU** — the hardware feature that lets
the CPU safely hand a real PCIe device (like your GPU) directly to a virtual
machine. Without this, passthrough is impossible.

```
VT for Direct I/O:  [ Disabled ]
                    ↓ change to
VT for Direct I/O:  [ Enabled  ]
```

> **R730xd BIOS 2.19+ note:** The "VT for Direct I/O" toggle was removed in
> BIOS version 2.19 and later — it does not appear in Processor Settings at all.
> VT-d (IOMMU) is enabled by default on these BIOS versions. If you do not see
> the toggle, that is expected; skip this sub-step and continue.

Click **Back** to return to System BIOS Settings.

---

### Step 3.2 — System BIOS → Integrated Devices

From the System BIOS Settings menu, arrow to **Integrated Devices** and press Enter.

Find:

**SR-IOV Global Enable**

SR-IOV is a PCIe feature that allows a single physical device to appear as
multiple devices. Even though the GPU does not use SR-IOV, enabling
this globally avoids a class of IOMMU grouping problems.

```
SR-IOV Global Enable:  [ Disabled ]
                       ↓ change to
SR-IOV Global Enable:  [ Enabled  ]
```

Click **Back**.

---

### Step 3.3 — System BIOS → Boot Settings

From System BIOS Settings, arrow to **Boot Settings** and press Enter.

You will see:

```
Boot Settings

  Boot Mode:  [ BIOS ]   ← must change this
  Boot Sequence
  ...
```

**Boot Mode** — change from BIOS to UEFI:

```
Boot Mode:  [ BIOS ]
            ↓ change to
Boot Mode:  [ UEFI ]
```

> **Why UEFI?** Proxmox uses a tool called `proxmox-boot-tool` to manage the
> kernel boot parameters (including the IOMMU settings the GPU passthrough script
> writes). This tool only works with UEFI boot. If the server is in Legacy/BIOS
> mode the passthrough script will fail and you will have to reinstall.

A warning may appear saying the boot sequence will be cleared — click **Yes** or
**OK**. That is fine since we haven't installed anything yet.

Click **Back**.

---

### Step 3.4 — System BIOS → System Profile Settings (Power Management)

From System BIOS Settings, arrow to **System Profile Settings** and press Enter.

> **R730xd BIOS 2.19+ note:** "Power Management" was renamed to **"System
> Profile Settings"** in BIOS 2.19 and later. If you see "System Profile
> Settings" in the menu, that is the same section — go there.

Find:

**Hard Disk Drive Sequencing** — this is the built-in stagger that fires at
power-on before the OS loads. It staggers when each drive spins up so they do
not all surge at the same time and overload the PSU.

```
Hard Disk Drive Sequencing:  [ Disabled ]
                              ↓ change to
Hard Disk Drive Sequencing:  [ Enabled  ]
```

> **R730xd BIOS 2.19+ note:** The "Hard Disk Drive Sequencing" attribute
> (`BIOS.StorageSettings.HddSeq`) was also removed in BIOS 2.19+. If you do
> not see it here, skip it — the Linux stagger-spinup service (Phase 7, Step
> 7.5) handles spin-up sequencing entirely from the OS side.

Also check:

**C States** — these are CPU power-saving sleep states. They can add latency
to VM workloads. Disable them for a server running VMs:

```
C States:  [ Enabled  ]
           ↓ change to
C States:  [ Disabled ]
```

Click **Back**.

---

### Step 3.5 — Apply and exit

From System BIOS Settings, click **Finish** (at the bottom of the menu, you may
need to scroll).

A dialog will appear:

```
Confirm changes and exit?
[ Yes ]  [ No ]
```

Click **Yes**.

The server will reboot.

---

### Step 3.6 — Confirm the settings took

After the reboot, press **F2** again to re-enter System Setup and spot-check:

- **Processor Settings:** VT and VT for Direct I/O should both show **Enabled**
- **Boot Settings:** Boot Mode should show **UEFI**

If either shows Disabled, set it again and apply. Some BIOS versions have a bug
where the first Apply does not persist — applying a second time fixes it.

---

### Phase 3 complete — what you have now

| Setting | Why it matters |
|---------|---------------|
| VT-x (Virtualization Technology) | Lets the CPU run VMs at near-native speed |
| VT-d (Direct I/O) | Enables IOMMU — the foundation of all device passthrough |
| SR-IOV | Prevents IOMMU group problems with PCIe devices |
| UEFI boot mode | Required for Proxmox's boot management and EFI GPU passthrough |
| HDD sequencing | Staggers drive spin-up at power-on to protect the PSU |

---

## Phase 4 — H730 RAID Configuration

**Goal:** Mirror the two 2.5" rear drives together so a single drive failure
cannot take down Proxmox. Leave every 3.5" drive untouched — the `perc-nonraid.sh`
script handles those later from inside Proxmox.

**Why mirror the OS drives here instead of using ZFS?** The H730 presents the
RAID1 mirror as a single virtual disk to the OS. Proxmox installs onto it and
never needs to think about the fact that two physical drives are underneath.
This is the simplest and most reliable approach for an OS volume.

> **If the 2.5" rear drives appear under a different controller (e.g., PERC H330
> Mini):** The R730xd sometimes puts the rear bays on a separate mini controller
> rather than the main H730. That is fine — just create the RAID1 on whichever
> controller owns those drives. The rest of this phase is identical regardless
> of which controller is used.

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

---

## Phase 7 — Fan Control + Staggered Spin-Up

**What this phase does:** Fixes two hardware quirks that bite R730xd owners
running non-Dell gear:

1. **Fan control.** iDRAC detects the non-Dell GPUs as "non-Dell PCIe
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

### Step 7.1 — Test fan control manually before enabling the service

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
is iDRAC reacting to the non-Dell GPU again. This confirms the script was in fact
holding them down. Get the service installed quickly so the noise stops.

---

### Step 7.2 — Install the fan control script and service

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

### Step 7.3 — Verify fans actually slow down over time

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

### Step 7.4 — iDRAC BIOS staggered spin-up (skip on BIOS 2.19+)

> **This step does not apply to R730xd BIOS 2.19 and later.** The BIOS
> attribute `BIOS.StorageSettings.HddSeq` and the corresponding
> `racadm set BIOS.StorageSettings.HddSeq Enabled` command were removed in
> that firmware version. Running the command will return an error. Skip this
> step entirely and proceed to Step 10.5 — the Linux stagger-spinup service
> provides equivalent protection from the OS side.
>
> If you are running an older BIOS (pre-2.19) and want to enable the BIOS
> layer as well, SSH to iDRAC and run:
> ```
> racadm set BIOS.StorageSettings.HddSeq Enabled
> racadm jobqueue create BIOS.Setup.1-1
> ```
> Then reboot to apply. The Linux service (Step 10.5) is still recommended
> as a second layer regardless.

---

### Step 7.5 — Install the Linux stagger spin-up service

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

### Step 7.6 — Reboot to apply both the BIOS setting and the Linux service

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

### Step 7.7 — Verify everything came back correctly

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

---

### Phase 7 complete — where you are now

| What is done | Status |
|---|---|
| Fan control daemon active, fans quiet | ✓ |
| iDRAC BIOS hard disk drive sequencing enabled | ✓ |
| Linux stagger spin-up service enabled for future boots | ✓ |
| Verified both survive a reboot cleanly | ✓ |

---

## Phase 8 — Convert 3.5" Drives to Non-RAID Mode

**What this does:** Right now the H730 sees your 3.5" drives as "Unconfigured
Good" — they exist but the controller is not doing anything with them. We need
to put them into **Non-RAID mode**, which tells the H730 to present each drive
directly to Linux as an individual block device, with SMART health data intact.

Without this step, Linux cannot see the drives at all — the H730 hides them.

**The 2.5" OS drives are not affected** — they are a RAID1 virtual disk and the
script only targets unconfigured physical drives.

---

### Step 8.1 — Download and install perccli

`perccli` is Dell's command-line tool for managing the H730. The `perc-nonraid.sh`
script uses it to talk to the controller.

SSH into the Proxmox host if you are not already connected:

```bash
ssh root@192.168.1.10
```

Download and install perccli on the Proxmox host. Dell only distributes an
RPM, so we convert it with `alien`:

```bash
# Download (referer header required — Dell blocks plain curl)
curl -L \
  --referer "https://www.dell.com/" \
  --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
  "https://dl.dell.com/FOLDER03559396M/1/perccli-1.17.10-1.noarch.rpm" \
  -o /tmp/perccli.rpm

# Convert RPM → deb and install
apt install -y alien
alien --to-deb /tmp/perccli.rpm
dpkg -i /tmp/perccli_*.deb

# Binary lands in /opt/MegaRAID/perccli/ — symlink it into PATH
ln -s /opt/MegaRAID/perccli/perccli64 /usr/local/bin/perccli
```

Verify it installed:

```bash
perccli show
```

You should see output starting with something like:

```
CLI Version = 007.1907.0000.0000
Operating system = Linux5.x
Controller = 0
Status = Success
...
```

If you see `command not found`, try `perccli64` instead — some versions install
under that name.

---

### Step 8.2 — Run the non-RAID conversion script

```bash
bash /opt/local_proxmox/scripts/perc-nonraid.sh
```

The script first prints a summary of your controller and all drives:

```
=== Controller overview ===
...

=== Drives on controller 0 ===
-------------------------------------------------------------
EID:Slt DID State DG      Size Intf Med SED PI SeSz Model   Sp
-------------------------------------------------------------
8:0      7   UGood -  3.637 TB SATA HDD N   N  512B WD...   U
8:1      8   UGood -  3.637 TB SATA HDD N   N  512B WD...   U
...
8:9      16  Onln  0  136.73 GB SATA SSD N   N  512B TOSHIBA U   ← OS drive (in VD)
8:10     17  Onln  0  136.73 GB SATA SSD N   N  512B TOSHIBA U   ← OS drive (in VD)
```

The columns that matter:
- **EID:Slt** — Enclosure ID and slot number (physical location in the backplane)
- **State** — `UGood` means unconfigured and ready. `Onln` means it is part of
  a virtual disk (your OS mirror). The script only touches `UGood` drives.
- **Size** — confirms which are 3.5" data drives vs the small OS drives

The script then asks:

```
Proceed with converting all non-OS drives to Non-RAID mode? [y/N]
```

Type `y` and press Enter.

The script works through each drive. For each one you will see:

```
  Slot 0: setting to Good...   Status = Success
  Slot 0: setting to Non-RAID... Status = Success
  Slot 1: setting to Good...   Status = Success
  Slot 1: setting to Non-RAID... Status = Success
  ...
```

When all drives are done the script prints the final state — drives that were
`UGood` should now show `JBOD` (which is Dell's term for non-RAID/per-disk mode):

```
=== Final drive state ===
EID:Slt  State
8:0      JBOD    ←
8:1      JBOD    ←
8:2      JBOD    ←
...
8:9      Onln    ← OS drive, untouched
8:10     Onln    ← OS drive, untouched
```

---

### Step 8.3 — Reboot

```bash
reboot
```

Wait about 60 seconds, then SSH back in:

```bash
ssh root@192.168.1.10
```

### Step 8.4 — Verify drives are visible

```bash
lsblk -d -o NAME,SIZE,TYPE,ROTA
```

You should see your drives listed. Something like:

```
NAME    SIZE TYPE ROTA
sda   136.7G disk    0   ← OS-Mirror RAID1 virtual disk (the 2.5" drives)
sdb     3.6T disk    1   ← 3.5" data drive
sdc     3.6T disk    1
sdd     3.6T disk    1
...
```

If you see only `sda` and nothing else, the non-RAID conversion did not take
effect — reboot again and re-run `lsblk`. If still missing, re-run
`perc-nonraid.sh` and check the output for any lines that say `Failed`.

---

## Phase 9 — Map Physical Bays to Drives

**The problem:** Linux names drives `sdb`, `sdc`, `sdd` etc. based on the order
it finds them at boot — that order can change. What you need is the **stable
hardware ID** (`/dev/disk/by-id/...`) for each drive, tied to its physical bay
number, so you can reliably assign "bay 3" to a specific VM forever.

This phase generates that map.

---

### Step 9.1 — Run the bay mapping script

```bash
bash /opt/local_proxmox/scripts/build-bay-map.sh
```

Output looks like this (truncated example):

```
=== Drive inventory ===

DEVICE       SIZE       MODEL                          SERIAL               BY-ID PATH
------       ----       -----                          ------               ---------
/dev/sdb     3.6T       WDC_WD4000FYYZ                WD-XXXXXXXXXXXX      /dev/disk/by-id/scsi-35000cca23b7d4eb8
/dev/sdc     3.6T       WDC_WD4000FYYZ                WD-XXXXXXXXXXXX      /dev/disk/by-id/scsi-35000cca23b5e1234
/dev/sdd     3.6T       ST4000NM0023                  Z1Z2XXXXXX           /dev/disk/by-id/scsi-35000c500a0000001
...

=== Bay identification via LED blink ===

To confirm which physical bay a device is in, blink its LED:
  ledctl locate=/dev/sdX      # LED on
  ledctl locate_off=/dev/sdX  # LED off
```

The script gives you the by-id path for each device. Now you need to figure out
**which physical bay each device is in**.

---

### Step 9.2 — Walk the bays with LED blink

This is the physical part. You need to be at the server (or have someone there).

For each drive, run the blink command, walk to the server, see which bay's amber
LED is lit, note the bay number, then turn it off:

```bash
# Blink sdb
ledctl locate=/dev/sdb
# Walk to the server, find the lit bay — write down: sdb = bay X
ledctl locate_off=/dev/sdb

# Blink sdc
ledctl locate=/dev/sdc
# Walk to server, find the lit bay — write down: sdc = bay X
ledctl locate_off=/dev/sdc

# Repeat for each drive
```

> **Bay numbering on the R730xd:** Bays are numbered left to right, top to
> bottom when facing the front of the server. Bay 1 is top-left. The exact
> labeling depends on your bezel — some models label them 0–11, others 1–12.
> Use whatever number is printed or silk-screened on the chassis next to the bay.

> **If the LED does not blink:** The `ledmon` daemon must be running. Start it:
> ```bash
> systemctl start ledmon
> ledctl locate=/dev/sdb
> ```

---

### Step 9.3 — Fill in the hardware layout document

Open the layout document:

```bash
nano /opt/local_proxmox/docs/hardware-layout.md
```

Fill in the table using what you noted in Step 8.2. It looks like this — fill
in the `by-id` column from the script output and the bay number from the LED walk:

```
| Bay | Assigned VM | Size | /dev/disk/by-id (fill in)                  |
|-----|-------------|------|---------------------------------------------|
| 1   | 100         | 4TB  | scsi-35000cca23b7d4eb8                      |
| 2   | 100         | 4TB  | scsi-35000cca23b5e1234                      |
...
```

Save with **Ctrl+O**, Enter, then **Ctrl+X** to exit nano.

---

### Step 9.4 — Record your by-id paths for later

You'll assign drives to VMs in Phase 11. For now, just save the mapping somewhere handy (the `hardware-layout.md` doc is a good place):

```bash
ls -la /dev/disk/by-id/ | grep -v part
```

You'll paste these paths into `qm set` commands in Phase 11, Step 11.6.

---

## Phase 10 — GPU Passthrough Setup

**What this does:** Tells the Linux kernel to stop trying to use the GPUs
itself and instead hand them over to the VFIO driver, which holds them
ready to be claimed by a virtual machine.

Three things happen:
1. IOMMU is turned on in the kernel (the hardware feature VT-d enables)
2. The host's NVIDIA/nouveau GPU drivers are blocked from loading
3. The VFIO driver claims both GPUs at boot, before any other driver can

---

### Step 10.1 — Check your IOMMU groups first

Before running the script, verify that VT-d is actually active:

```bash
dmesg | grep -i iommu | head -10
```

You should see lines like:

```
DMAR: IOMMU enabled
Intel-IOMMU: enabled
```

If you see nothing or see "disabled", IOMMU is not active. Go back to Phase 3
and re-check that VT-d is set to **Enabled** in BIOS, then reboot and try again.

Also check that each GPU is in its own IOMMU group:

```bash
for d in /sys/kernel/iommu_groups/*/devices/*; do
  n=${d#*/iommu_groups/*}; n=${n%%/*}
  printf 'IOMMU Group %s ' "$n"
  lspci -nns "${d##*/}"
done | sort -V | grep -i nvidia
```

Example good output — each GPU is in a different group:

```
IOMMU Group 24  03:00.0 VGA compatible controller [0300]: NVIDIA GP106GL [Quadro P2200] [10de:1c35]
IOMMU Group 24  03:00.1 Audio device [0403]: NVIDIA GP106 High Definition Audio [10de:10f1]
IOMMU Group 31  04:00.0 VGA compatible controller [0300]: NVIDIA GP106GL [Quadro P2200] [10de:1c35]
IOMMU Group 31  04:00.1 Audio device [0403]: NVIDIA GP106 High Definition Audio [10de:10f1]
```

Each GPU (`03:00.0` and `04:00.0`) and its audio sibling (`03:00.1` and
`04:00.1`) are together in their own group — that is exactly what you want.

> **If both GPUs are in the same IOMMU group as other devices** (chipset, NICs,
> etc.), you may need to enable **ACS** (Access Control Services). This is rare
> on server hardware like the R730xd which has good IOMMU separation. If you
> hit this, ask before proceeding.

---

### Step 10.2 — Run the GPU passthrough script

```bash
bash /opt/local_proxmox/scripts/gpu-passthrough-setup.sh
```

The script first prints your NVIDIA devices:

```
=== Detected NVIDIA devices ===
03:00.0 VGA compatible controller [10de:1c35]: NVIDIA GP106GL [Quadro P2200]
03:00.1 Audio device [10de:10f1]: NVIDIA GP106 High Definition Audio
04:00.0 VGA compatible controller [10de:1c35]: NVIDIA GP106GL [Quadro P2200]
04:00.1 Audio device [10de:10f1]: NVIDIA GP106 High Definition Audio

GPU PCI IDs to bind to vfio-pci: 10de:1c35,10de:10f1
```

Then asks:

```
Proceed with configuring VFIO passthrough? [y/N]
```

Type `y` and press Enter.

The script runs through these steps — you will see each one printed:

```
--- Configuring kernel cmdline for IOMMU ---
Written: /etc/kernel/cmdline
Boot tool refreshed.

--- Blacklisting nouveau and nvidia on host ---
Written: /etc/modprobe.d/blacklist-gpu.conf

--- Binding GPU IDs to vfio-pci ---
Written: /etc/modprobe.d/vfio.conf
  IDs: 10de:1c35,10de:10f1

--- Adding vfio modules to initramfs ---
Updated: /etc/initramfs-tools/modules
Initramfs updated.
```

At the end it prints the PCI addresses you need:

```
=== GPU PCI addresses for VM assignment ===

  hostpci0: 0000:03:00,pcie=1   # VGA: NVIDIA GP106GL [Quadro P2200]
  hostpci0: 0000:04:00,pcie=1   # VGA: NVIDIA GP106GL [Quadro P2200]

IMPORTANT: Pass each GPU + its HDMI audio sibling to the same VM.
```

**Write down or copy these addresses** — you need them in Phase 11 when
creating the VMs. In this example:
- GPU 1 is at `03:00` → goes in VM 100 (Frigate)
- GPU 2 is at `04:00` → goes in VM 101

---

### Step 10.3 — Update the VM configs with the GPU addresses

While you have the addresses, add them to the VM configs now:

```bash
nano /opt/local_proxmox/vm-configs/100-frigate.conf.example
```

Find the line:

```
hostpci0: 0000:XX:00,pcie=1,x-vga=1
```

Replace `XX:00` with your GPU 1 address, e.g.:

```
hostpci0: 0000:03:00,pcie=1,x-vga=1
```

Save, then do the same for VM 101:

```bash
nano /opt/local_proxmox/vm-configs/101.conf.example
# Change XX:00 to 04:00 (GPU 2)
```

---

### Step 10.4 — Reboot

```bash
reboot
```

Wait about 60 seconds, then SSH back in:

```bash
ssh root@192.168.1.10
```

---

### Step 10.5 — Verify passthrough is working

```bash
lspci -nnk | grep -A3 -i nvidia
```

For each GPU, look for the driver line. It **must** say `vfio-pci`:

```
03:00.0 VGA compatible controller [10de:1c35]: NVIDIA GP106GL [Quadro P2200]
        Subsystem: ...
        Kernel driver in use: vfio-pci     ← correct
        Kernel modules: nouveau

04:00.0 VGA compatible controller [10de:1c35]: NVIDIA GP106GL [Quadro P2200]
        Subsystem: ...
        Kernel driver in use: vfio-pci     ← correct
        Kernel modules: nouveau
```

**If it shows `nouveau` or `nvidia` instead of `vfio-pci`:** The blacklist did
not take effect. Run:

```bash
update-initramfs -u -k all
reboot
```

Then check again. If still wrong, verify the blacklist file exists:

```bash
cat /etc/modprobe.d/blacklist-gpu.conf
# Should show: blacklist nouveau, blacklist nvidia, etc.

cat /etc/modprobe.d/vfio.conf
# Should show: options vfio-pci ids=10de:1c35,10de:10f1
```

Also confirm IOMMU is in the kernel command line:

```bash
# Proxmox EFI boot tool (if this file exists):
cat /etc/kernel/cmdline

# GRUB (if the above file doesn't exist — use this instead):
grep CMDLINE /etc/default/grub
# Should contain: intel_iommu=on iommu=pt
```

---

### Phase 10 complete — where you are now

| What is done | Status |
|---|---|
| 3.5" drives in non-RAID mode, visible to Linux | ✓ |
| Physical bay → by-id map documented | ✓ |
| VM configs updated with real drive paths and GPU addresses | ✓ |
| IOMMU active, both GPUs claimed by vfio-pci | ✓ |

---

## Phase 11 — Create the VMs

**What this phase does:** Creates three VMs in the Proxmox web interface, attaches
their hardware (GPUs, Coral USB, raw data drives), installs Ubuntu Server inside
each one, and verifies SSH access.

**Prerequisites from earlier phases:**
- GPU passthrough working: both GPUs show `vfio-pci` in `lspci` (Phase 10)
- Bay map filled in: `/dev/disk/by-id/...` paths known for all 12 drives (Phase 9)
- VM config examples updated with real paths and PCI addresses (Phases 9–10)
- Fan control and stagger services installed and verified (Phase 7)

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
| Raw Device | select GPU #1 from the dropdown (shows PCI address + model name) |
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
your GPU model`). Check **All Functions**, **Primary GPU**,
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

---

## Phase 12 — Deploy Frigate in VM 100

**What this phase does:** Installs the NVIDIA driver and Docker inside VM 100,
creates a ZFS storage pool from the 8 data drives, then deploys Frigate NVR
with GPU-accelerated video decode and Coral object detection.

**Prerequisites:**
- VM 100 running Ubuntu Server 24.04 with SSH access (Phase 11)
- NVIDIA GPU passed through (PCIe device visible in guest)
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
`/etc/pve/qemu-server/100.conf` on the Proxmox host, and that Phase 10
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
- GPU model matches your installed card
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
the GPU for hardware video decode.

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
frigate  | [INFO]    Loading NVIDIA GPU: &lt;your GPU model&gt;
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
- GPU utilization is shown (your GPU model)
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
| Hardware | Dell R730xd, PERC H730, 12 drives, NVIDIA GPU(s), Coral USB | ✓ |
| Proxmox host | IOMMU active, GPUs held by vfio-pci | ✓ |
| Services | fan-control (quiet fans), stagger-spinup (PSU protection) | ✓ |
| VM 100 | Ubuntu 24.04, GPU passthrough, 8 drives, Frigate NVR | ✓ |
| VM 101 | Ubuntu 24.04, GPU passthrough, 2 drives | ready |
| VM 102 | Ubuntu 24.04, 2 drives | ready |

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
# If not: re-check Phase 10 cmdline (intel_iommu=on); VT-d is on by default in newer BIOS
grep CMDLINE /etc/default/grub   # must contain intel_iommu=on iommu=pt
# (or: cat /etc/kernel/cmdline if using Proxmox EFI boot tool)
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

### nvidia-smi: No devices were found (in guest VM)

```bash
# Check dmesg in the guest:
dmesg | grep -i nvidia | tail -20
# Check GPU is bound to vfio-pci on HOST (not in guest):
ssh root@192.168.1.10 "lspci -nnk | grep -A2 nvidia"
# Must show: Kernel driver in use: vfio-pci
```

### Frigate recordings disk full

```bash
# In VM 100, check ZFS pool health and usage:
zpool status frigate-data
zfs list
# Frigate retains recordings per the config.yml settings:
# record.retain.days and record.events.retain.default
# Edit /opt/frigate/config.yml and reduce retention days, then:
docker compose restart
```
