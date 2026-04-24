# Phases 1–3: Firmware, iDRAC, and BIOS
### Dell R730xd — Button-by-button walkthrough

---

## Before You Touch Anything — Read This First

### What is iDRAC and do I need to pay for it?

iDRAC stands for **Integrated Dell Remote Access Controller**. Ignore the name.
Here is what it actually is:

There is a **second tiny computer built into your server's motherboard**. It has
its own processor, its own RAM, its own network port, and it runs 24 hours a day
as long as the server has power — even when the server is "off". Dell calls this
second computer iDRAC.

What it lets you do:
- See a virtual screen of the server from your web browser (like sitting in front
  of it with a monitor plugged in, but over the network)
- Power the server on and off remotely
- Mount a virtual USB drive so you can install an OS without physically being there
- Read temperatures, fan speeds, and hardware health
- See hardware logs when something fails
- Send IPMI commands — which is how our fan control script talks to the fans

**Do you need to pay for it?** No. The R730xd shipped with **iDRAC8 Enterprise**
already built in and fully licensed. You will not be asked to pay for anything.
The features are already there.

The confusion people sometimes have: there is a separate **Proxmox subscription**
(about €100/year) which gives you access to their enterprise update servers and
commercial support. You do not need this either. We will configure the free
community repositories in Phase 6. iDRAC and the Proxmox subscription are
completely unrelated things.

**Summary: pay nothing, skip nothing.**

---

### What you need on the table before starting

- The server plugged into power and a network switch/router
- A **separate network cable** for the iDRAC port (the small RJ45 on the back
  labeled "iDRAC" — it is separate from the four main NIC ports)
- A monitor and USB keyboard plugged into the server for the initial setup
  (after Phase 2 you can do everything from your regular computer over the network)
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

There are two ways to do this — through the server's BIOS-like setup (F2),
or through the iDRAC web UI once you find its current IP. We will use F2 first
to set a static IP, then use the web UI for the rest.

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

Click **Back** to return to System BIOS Settings.

---

### Step 3.2 — System BIOS → Integrated Devices

From the System BIOS Settings menu, arrow to **Integrated Devices** and press Enter.

Find:

**SR-IOV Global Enable**

SR-IOV is a PCIe feature that allows a single physical device to appear as
multiple devices. Even though the Quadro P2200 does not use SR-IOV, enabling
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

### Step 3.4 — System BIOS → Power Management

From System BIOS Settings, arrow to **Power Management** and press Enter.

Find:

**Hard Disk Drive Sequencing** — this is the built-in stagger that fires at
power-on before the OS loads. It staggers when each drive spins up so they do
not all surge at the same time and overload the PSU.

```
Hard Disk Drive Sequencing:  [ Disabled ]
                              ↓ change to
Hard Disk Drive Sequencing:  [ Enabled  ]
```

Also check:

**C States** — these are CPU power-saving sleep states. They can add latency
to VM workloads. Optional but worth setting for a server:

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

**Next:** Phase 4 — Configure the H730 RAID controller to mirror the two
2.5" OS drives, then leave the 3.5" drives alone for Proxmox to manage.
That walkthrough is in `docs/walkthrough-phases-4-6.md` (coming next).
