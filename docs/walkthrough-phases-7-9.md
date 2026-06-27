# Phases 7–9: Drive Non-RAID, Bay Mapping, GPU Passthrough
### Dell R730xd — Button-by-button walkthrough

---

## Phase 7 — Convert 3.5" Drives to Non-RAID Mode

**What this does:** Right now the H730 sees your 3.5" drives as "Unconfigured
Good" — they exist but the controller is not doing anything with them. We need
to put them into **Non-RAID mode**, which tells the H730 to present each drive
directly to Linux as an individual block device, with SMART health data intact.

Without this step, Linux cannot see the drives at all — the H730 hides them.

**The 2.5" OS drives are not affected** — they are a RAID1 virtual disk and the
script only targets unconfigured physical drives.

---

### Step 7.1 — Download and install perccli

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

### Step 7.2 — Run the non-RAID conversion script

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

### Step 7.3 — Reboot

```bash
reboot
```

Wait about 60 seconds, then SSH back in:

```bash
ssh root@192.168.1.10
```

### Step 7.4 — Verify drives are visible

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

## Phase 8 — Map Physical Bays to Drives

**The problem:** Linux names drives `sdb`, `sdc`, `sdd` etc. based on the order
it finds them at boot — that order can change. What you need is the **stable
hardware ID** (`/dev/disk/by-id/...`) for each drive, tied to its physical bay
number, so you can reliably assign "bay 3" to a specific VM forever.

This phase generates that map.

---

### Step 8.1 — Run the bay mapping script

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

### Step 8.2 — Walk the bays with LED blink

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

### Step 8.3 — Fill in the hardware layout document

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

### Step 8.4 — Fill in the VM config placeholders

Now open each VM config example and replace the `PLACEHOLDER_BAYx` entries with
the real by-id paths:

```bash
nano /opt/local_proxmox/vm-configs/100-frigate.conf.example
```

Change lines like:

```
scsi1: /dev/disk/by-id/PLACEHOLDER_BAY1,size=0
```

To the real path:

```
scsi1: /dev/disk/by-id/scsi-35000cca23b7d4eb8,size=0
```

Do this for all 8 drives in VM 100, drives 9–10 in VM 101, and drives 11–12 in
VM 102. Save each file.

> **The full path starts with `/dev/disk/by-id/`** — but in the Proxmox VM
> config you write the full path. Double-check by running:
> ```bash
> ls -la /dev/disk/by-id/ | grep -v part
> ```
> You will see the symlinks and the drives they point to.

---

## Phase 9 — GPU Passthrough Setup

**What this does:** Tells the Linux kernel to stop trying to use the two Quadro
P2200s itself and instead hand them over to the VFIO driver, which holds them
ready to be claimed by a virtual machine.

Three things happen:
1. IOMMU is turned on in the kernel (the hardware feature VT-d enables)
2. The host's NVIDIA/nouveau GPU drivers are blocked from loading
3. The VFIO driver claims both GPUs at boot, before any other driver can

---

### Step 9.1 — Check your IOMMU groups first

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

### Step 9.2 — Run the GPU passthrough script

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

### Step 9.3 — Update the VM configs with the GPU addresses

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

### Step 9.4 — Reboot

```bash
reboot
```

Wait about 60 seconds, then SSH back in:

```bash
ssh root@192.168.1.10
```

---

### Step 9.5 — Verify passthrough is working

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
cat /etc/kernel/cmdline
# Should contain: intel_iommu=on iommu=pt
```

---

### Phase 9 complete — where you are now

| What is done | Status |
|---|---|
| 3.5" drives in non-RAID mode, visible to Linux | ✓ |
| Physical bay → by-id map documented | ✓ |
| VM configs updated with real drive paths and GPU addresses | ✓ |
| IOMMU active, both GPUs claimed by vfio-pci | ✓ |

**Next:** Phase 10 — Install the fan control service (stops iDRAC from running
fans at 100% because of the non-Dell GPUs) and the stagger spin-up service.
That walkthrough is in `docs/walkthrough-phases-10-12.md`.
