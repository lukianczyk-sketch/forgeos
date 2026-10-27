# PROGRESS — Job 12: GhostFinder

## Step 0 — Claude: research, prototype + blueprint
- Prototype written and tested by Claude in the cloud (Python 3.13, BlueZ protocol via python3-dbus on a private D-Bus bus) and on Robert's PC (Python 3.10): tests A-V all pass (fake tools, real sockets on 127.0.0.x for the camera ports + ONVIF, real D-Bus with a fake BlueZ), shellcheck clean, pyflakes clean, 32 mutation checks: 28 caught, 4 do not change behavior (double safety checks). All older tests still pass. Fedora 44 packages checked: python3-dbus, avahi-tools, hwdata.
- STATUS: STEP 0 DONE — next: Step 1 (Cline)
- Step 1 (Cline): ghostlib __init__.py, trackers.py, ble.py, net.py written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-27): APPROVED, no fixes. __init__.py, trackers.py, ble.py, net.py byte-identical to the tested prototype after CRLF -> LF fix. Next: Step 2.
- STATUS: STEP 1 DONE — next: Step 2 (Cline)
