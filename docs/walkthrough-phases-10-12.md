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

*(Not written yet — coming next.)*

---

## Phase 12 — Deploy Frigate in VM 100

*(Not written yet — coming next.)*
