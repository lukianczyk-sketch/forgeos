# RABBIT BLUEPRINT — Job 13d: Driver & BIOS Autopilot

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (all 8 test files pass). Each step prompt gives you
the EXACT file contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
"You never update a driver by hand again."
1. **Drivers** come inside ForgeOS's own system updates (Bazzite's uupd installs them every night). Autopilot
   reads rpm-ostree and says in plain words what changed ("Graphics driver (NVIDIA) 580.95 to 590.12,
   3 security fixes") with "Restart now / Later". It never restarts by itself (Restart now = KDE's normal
   logoutAndReboot, so programs can save). If the nightly updater is off or failing: "Fix it".
2. **After every restart** it compares every important part (graphics, network, Wi-Fi, sound, USB, drives,
   camera, Bluetooth) with the last version where everything worked. A part that lost its driver (or an
   NVIDIA driver that did not start) = "Something stopped working - Go back / Keep this version".
   Go back = Undo Button's rpm-ostree rollback (files are not touched).
3. **BIOS + device firmware** through fwupd and the free LVFS (signed updates only, lvfs-testing ignored).
   Device firmware (receivers, docks, drives...) installs by itself with a note (setting: auto or ask;
   2 failures = stop trying that version). BIOS = one tap "Get it ready", only with the charger in and
   battery >= 50 %, not in a VM, with a TPM-unlock warning; it is written at the next restart and the
   result is shown after it. 2 failures = stop.
4. **BIOS Watch**: makers that don't use the LVFS (probably Acer Predator) -> BIOS date, a reminder twice a
   year when it is over a year old, the maker's download page (makers.txt), never runs a maker's .exe.
5. **Device Check**: parts with no driver (like Device Manager's yellow "!") with plain advice; the right
   ForgeOS version for the graphics card (switch = rpm-ostree rebase to forgeos / forgeos-nvidia);
   NVIDIA blocked by Secure Boot -> opens `ujust enroll-secure-boot-key`.
The timer (2 min after login, then every 6 h) shows at most ONE note per run, none during a game.
Window: forgeos-autopilot-gui (menu "Drivers & BIOS"). Forge Helper gets a `drivers` tool + help card.

## Key facts (checked by Claude on 2026-11-01)
- uupd.timer is enabled in Bazzite desktop images, daily 04:00 (ublue-os/uupd); firmware is not part of it.
- fwupd polkit: update-internal-trusted + update-hotplug-trusted = yes for the active local user (no password).
- fwupdmgr options used: get-devices/get-updates/get-results --json, update ID --assume-yes --no-reboot-check.
  JSON keys: Devices, Name, DeviceId, Flags, Version, Protocols, Plugin, Problems, Releases (Version, Summary,
  Urgency, RemoteId, Flags trusted-payload/trusted-metadata, InstallDuration), UpdateState, UpdateError.
- Fedora 44: fwupd 2.1.1 ships fwupd-refresh.timer; fwupd-efi 1.8 holds the signed EFI program.
- rpm-ostree db diff --format=json: pkgdiff = [[name, type, {PreviousPackage: [n, evr, arch], NewPackage: [...]}]].
- Plasma 6 restart: org.kde.Shutdown /Shutdown logoutAndReboot (session bus).

## Files
- files/system/usr/lib/forgeos-autopilot/autopilotlib/: __init__.py (paths, run, state, settings, log, busy),
  drivers.py, devices.py, gpu.py, firmware.py, safety.py, afterboot.py, notes.py, tick.py, notices.py,
  report.py, commands.py, cli.py
- files/system/usr/bin/forgeos-autopilot (engine), files/system/usr/bin/forgeos-autopilot-gui (window),
  files/system/usr/libexec/forgeos-autopilot-screens (window screens, sourced)
- files/system/usr/share/forgeos/autopilot/makers.txt, known-devices.txt
- files/system/usr/lib/systemd/user/forgeos-autopilot.service + .timer
- files/system/usr/share/applications/forgeos-autopilot.desktop
- files/system/usr/share/forgeos/helper/help/drivers-bios.md
- edits: files/scripts/forgeos-setup.sh, recipes/common-modules.yml (fwupd, fwupd-efi),
  familylib/guards.py, helperlib/tools.py, looks.py, actions.py, rulelist.py, helper tests/tools-2.jsonl,
  tests/test-helper-ai.sh (G3), .github/workflows/tests.yml
- tests/autopilot-fakes.sh, autopilot-tools.sh, test-autopilot.sh (A-B), test-autopilot-devices.sh (C-E),
  test-autopilot-boot.sh (F-G), test-autopilot-fw.sh (H-I), test-autopilot-bios.sh (J),
  test-autopilot-notes.sh (K-N), test-autopilot-gui.sh (O-P), test-autopilot-files.sh (Q)

## Steps (one Cline task each)
1. autopilotlib __init__.py, drivers.py, devices.py
2. autopilotlib gpu.py, firmware.py, safety.py, afterboot.py, notes.py
3. autopilotlib tick.py, notices.py, report.py
4. autopilotlib commands.py, cli.py, bin/forgeos-autopilot, bin/forgeos-autopilot-gui, libexec/forgeos-autopilot-screens
5. makers.txt, known-devices.txt, 2 user units, menu entry, help card + edits (setup, recipe, Family Mode, Forge Helper)
6. tests/autopilot-fakes.sh, autopilot-tools.sh, test-autopilot.sh, test-autopilot-devices.sh
7. tests/test-autopilot-boot.sh, test-autopilot-fw.sh, test-autopilot-bios.sh
8. tests/test-autopilot-notes.sh, test-autopilot-gui.sh, test-autopilot-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.

## Honest limits
Drivers can only be as new as ForgeOS's own updates (no downloading drivers from websites - that is what
keeps it safe). BIOS updates come only from makers that use the LVFS; others get BIOS Watch (help + the
maker's page), and ForgeOS never runs a maker's Windows flasher. Going back to an older BIOS is not
offered (most BIOSes block it). Very old NVIDIA cards (before GTX 16xx) are not supported by the NVIDIA
version; they stay on the AMD/Intel version. The after-restart check sees parts that lost their driver;
it can't see every kind of problem (Job 26 Never Bricks adds the boot-level safety net).
