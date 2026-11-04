# RABBIT BLUEPRINT — Job 15: Drive Death Warning

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (tests A-K pass). Each step prompt gives you the EXACT
file contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
Drive Health warns in plain English BEFORE a drive dies, while there is still time to save photos and papers,
with one button to back up. Approved by Robert 2026-11-03.
1. **Daily check (root)**: forgeos-drivehealth.timer (10 min after start-up, then daily, idle priority) runs
   `forgeos-drivehealth system-check --timer`: every internal drive (NVMe, SATA SSD, hard drive) + a USB drive of
   100 GB or more (`smartctl -d sat`). Read-only: `smartctl -j -a` (+ `-l devstat` for ATA), `btrfs device stats`
   and `btrfs scrub status -R` on /var/home (LUKS layers followed down to the drive with `lsblk -s`).
2. **Levels**: Good / Watch (bad spots, getting worse, 90%+ worn, NVMe spare low, too hot, past problem, a read
   error this week) / Danger (drive says failing, NVMe critical warning, failed self-test, 10+ new bad spots in a
   week, 100+ bad spots, damaged files btrfs could not repair). Unreadable USB box = "can't read this drive's health".
3. **Saved**: /var/lib/forgeos-drivehealth/report.json (0644, no serial numbers; Job 21 PC Report Card reads it)
   + history.json (0600, 120 rows per drive) so it can say "getting worse".
4. **Danger warning** (user timer forgeos-drivehealth-notify.timer, 12 min after login then every 2 h): big kdialog
   warning, or a critical note during games/videos (shows over full-screen). "Back up now" opens the window's
   backup steps. Again every day until a Pika Backup newer than the warning exists, then a weekly "replace it".
   No backup set up at all: one quiet note a month.
5. **Watch**: a quiet Forge Helper note (new check_drive in checks.py/watch.py, same 3-a-day + snooze rules).
6. **Window "Drive Health"** (kdialog): one card per drive (Good/Watch/Danger, % worn, years of use, temperature,
   reasons), Check now (pkexec /usr/libexec/forgeos-drivehealth-check, polkit org.forgeos.drivehealth.check = no
   password for the person at the PC), Back up now (Pika Backup; first-backup steps when none is set up), What does this mean?
7. **Monthly self-test**: `smartctl -t short` per internal drive every 30 days, only when idle (load < 1) and on
   wall power; the next daily check reads the result.
8. **Ties in**: Forge Helper tool `drive_health` + help card drive-health.md; Ask Your PC health check + status.

## Files
- files/system/usr/bin/forgeos-drivehealth (status | report | check | tick | system-check [--timer]),
  files/system/usr/bin/forgeos-drivehealth-gui (--backup | --explain)
- files/system/usr/lib/forgeos-drivehealth/drivelib/: __init__ disks smart btrfs judge check selftest backup report tick cli (.py)
- files/system/usr/libexec/forgeos-drivehealth-check; polkit org.forgeos.drivehealth.policy
- systemd: system forgeos-drivehealth.service + .timer, user forgeos-drivehealth-notify.service + .timer
- files/system/usr/share/applications/forgeos-drivehealth.desktop; files/system/usr/share/forgeos/helper/help/drive-health.md
- edits: forgeos-setup.sh (chmod + 2 enable lines), common-modules.yml (smartmontools, already in the base image),
  helperlib tools/looks/actions/rulelist/checks/watch, tools-2.jsonl, tests/test-helper-ai.sh (G3), forgeos-askpc-lib,
  .github/workflows/tests.yml
- tests/drivehealth-make.py, drivehealth-fakes.sh, test-drivehealth.sh (A-B), test-drivehealth-danger.sh (C),
  test-drivehealth-more.sh (D-F), test-drivehealth-tick.sh (G-I), test-drivehealth-gui.sh (J), test-drivehealth-files.sh (K)

## Steps (one Cline task each)
1. bin/forgeos-drivehealth, drivelib __init__.py, disks.py, smart.py
2. drivelib btrfs.py, judge.py, check.py, selftest.py
3. drivelib backup.py, report.py, tick.py, cli.py
4. libexec checker, window, polkit, desktop file, help card, 4 systemd units
5. edits: setup, recipe, Forge Helper (6 files + tools-2.jsonl + test-helper-ai.sh), Ask Your PC
6. tests/drivehealth-make.py, drivehealth-fakes.sh, test-drivehealth.sh
7. tests/test-drivehealth-danger.sh, test-drivehealth-more.sh, test-drivehealth-tick.sh
8. tests/test-drivehealth-gui.sh, test-drivehealth-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.
- Run bits (Claude sets them in git): bin/forgeos-drivehealth, bin/forgeos-drivehealth-gui, libexec/forgeos-drivehealth-check = 755.

## Honest limits
Some drives die with no warning at all, so the backup reminders stay on even when every drive is Good. Some USB
boxes hide the drive's health ("can't read"). It does not recover data or copy the whole drive (Instant Clone,
Job 38). Checked on the real PC at the end of the full build: smartctl on the Predator-class NVMe + a USB SATA
box, SELinux lets the timer run smartctl, the warning over a full-screen game, self-test only on wall power.
