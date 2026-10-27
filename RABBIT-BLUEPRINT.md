# RABBIT BLUEPRINT — Job 12: GhostFinder

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype. Each step prompt gives you the EXACT file
contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
"GhostFinder — see who's watching." One button ("Sweep now") checks, in about 30 seconds:
1. **Devices on your network**: every device on the Wi-Fi/LAN in plain words (maker from the free
   IEEE list in hwdata, names from mDNS/avahi). Found without root: one tiny UDP packet to every
   address of our /24 makes the PC ask "who has this address?" (ARP), which every device answers.
2. **Cameras on the network** (RED): camera maker (Hikvision, Dahua, Wyze, Reolink...), a camera
   port open (554/8554 RTSP video, 8000 Hikvision, 37777 Dahua, 34567 XMEye), an answer to the
   ONVIF "are you a network camera?" call, or an mDNS _rtsp._tcp video stream.
3. **Spy-camera Wi-Fi** nearby: cheap hidden cameras make a setup network (IPC-..., V380...,
   HDWiFiCam..., "mini cam", "spy cam"...). RED at signal 40% or more, else YELLOW.
4. **Bluetooth trackers away from their owner** (YELLOW; RED when following you): AirTag, other Find
   My trackers, AirPods, lost iPhones/Macs, Samsung SmartTag, lost Galaxy phones, Google Find My
   Device tags, any IETF DULT tag, Tile, Chipolo, Pebblebee. A tracker NEAR its owner is ignored.
Then: **What is it / what do I do now** (plain English, who to call), **Hunt it** (hot / cold meter:
the bar fills and the beeps speed up as you walk closer), **It's mine** (never warn again),
**These are all mine** (every new device on the home network; never cameras or trackers),
**Watch this trip** (checks every minute; a tracker in most checks for 10+ minutes = RED),
**Background watch** (every 10 minutes, 15 seconds, only if Bluetooth is already on: a tracker
heard 3+ times over 60+ minutes in 2+ places in a day = desktop alert, at most every 4 hours),
**Room-by-room camera check** (phone-flashlight lens check), **Saved report**
(~/Documents/GhostFinder/GhostFinder report.txt). Nothing ever leaves the PC. No root.

## Key facts (checked by Claude on 2026-10-27)
- Tracker signals from AirGuard (SEEMOO, TU Darmstadt, Apache-2.0) and the IETF DULT draft:
  Apple manufacturer data 0x004C, byte0 0x12; byte1 0x19 = away from owner; status byte bits 4-5 =
  type (1 AirTag, 2 Find My accessory, 3 AirPods, 0 Apple device), bits 6-7 = battery.
  Samsung 0xFD5A (state bits), 0xFD69 lost Galaxy; Google 0xFEAA frame 0x41 = away 4 h+;
  DULT 0xFCB2 near-owner bit; Tile 0xFEED, Chipolo 0xFE33, Pebblebee 0xFA25 (no away flag).
  Separated trackers keep one address for 24 h, so the address is the ID.
- BlueZ through python3-dbus (Fedora 44 python3-dbus 1.4.0): SetDiscoveryFilter {Transport: le,
  DuplicateData: true}, StartDiscovery, read GetManagedObjects once a second, StopDiscovery.
  BlueZ gives RSSI only for devices heard during discovery. `busctl --json` can NOT be used: it
  fails silently on ManufacturerData (number keys) - tested.
- Fedora 44 packages (all free): python3-dbus, avahi-tools (avahi-browse), hwdata (oui.txt).
  bluez, NetworkManager (nmcli) and pipewire-utils (pw-play) are already in the image.
- Python standard library + python3-dbus only. No pip. No internet. sys.dont_write_bytecode.

## Files
- files/system/usr/lib/forgeos-ghost/ghostlib/: __init__.py (paths, run), trackers.py (which
  signals are trackers), ble.py (Bluetooth), net.py (network + camera checks), names.py (makers,
  mDNS, plain words), wifi.py (nearby Wi-Fi), store.py (it's-mine list, sightings, follow rule,
  report), sweep.py (one full sweep), advice.py (texts), cli.py (hunt, output), watch.py
  (background watch + trip)
- files/system/usr/bin/forgeos-ghost — Python command: sweep [--secs N] [--no-bt] [--json], info ID,
  hunt ID [--secs N], safe add|remove|list, known-all, trip start|tick|stop, watch-tick,
  bt on|off|status, checklist, beep-file. Exit 0 / 1 not found / 3 wrong use / 4 Bluetooth off.
  Lines for the window: VERDICT<tab>level, NOTE<tab>text, ITEM<tab>level<tab>id<tab>hunt<tab>what.
- files/system/usr/bin/forgeos-ghost-gui — kdialog window
- files/system/usr/libexec/forgeos-ghost-meter — hunt meter + trip window (kdialog progress bar)
- files/system/usr/lib/systemd/user/forgeos-ghost-watch.service + .timer
- files/system/usr/share/applications/forgeos-ghostfinder.desktop
- files/scripts/forgeos-setup.sh — chmod the 3 programs, `systemctl --global enable forgeos-ghost-watch.timer`
- recipes/common-modules.yml — dnf: python3-dbus, avahi-tools, hwdata
- tests/ghost-fakes.sh, ghost-gui-fakes.sh, ghost-ble-world.py, ghost-fake-net.py, ghost-fake-bluez.py,
  test-ghost.sh (A-C), test-ghost-safe.sh (D-H), test-ghost-watch.sh (I-P), test-ghost-gui.sh (Q-S),
  test-ghost-files.sh (T), test-ghost-real.sh (U-V: real D-Bus + fake BlueZ)
- tests/test-find-extras.sh — T1 now allows more programs after forgeos-find-gui on the chmod line
- .github/workflows/tests.yml — 2 new test steps

## Steps (one Cline task each)
1. ghostlib/__init__.py, trackers.py, ble.py, net.py
2. ghostlib/names.py, wifi.py, store.py, sweep.py
3. ghostlib/advice.py, cli.py, watch.py, bin/forgeos-ghost
4. Window, meter, menu entry, user service + timer, forgeos-setup.sh, common-modules.yml, test-find-extras.sh T1
5. tests/ghost-fakes.sh, ghost-gui-fakes.sh, ghost-ble-world.py, ghost-fake-net.py, test-ghost.sh
6. tests/test-ghost-safe.sh, test-ghost-watch.sh, test-ghost-gui.sh
7. tests/ghost-fake-bluez.py, test-ghost-real.sh, test-ghost-files.sh + 2 CI steps

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.

## Honest limits
A PC can't do the phone-camera lens-glint scan (the room checklist explains the flashlight way) and
no app can find a truly silent bug. A camera on its own hidden network (not your Wi-Fi, no setup
hotspot) can't be seen. Tile, Chipolo and Pebblebee don't say if their owner is near, so they show
as "nearby", not "away". On a desktop that never moves, "following you" can't happen (needs 2 places).
