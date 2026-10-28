# PROGRESS — Job 12: GhostFinder

## Step 0 — Claude: research, prototype + blueprint
- Prototype written and tested by Claude in the cloud (Python 3.13, BlueZ protocol via python3-dbus on a private D-Bus bus) and on Robert's PC (Python 3.10): tests A-V all pass (fake tools, real sockets on 127.0.0.x for the camera ports + ONVIF, real D-Bus with a fake BlueZ), shellcheck clean, pyflakes clean, 32 mutation checks: 28 caught, 4 do not change behavior (double safety checks). All older tests still pass. Fedora 44 packages checked: python3-dbus, avahi-tools, hwdata.
- STATUS: STEP 0 DONE — next: Step 1 (Cline)
- Step 1 (Cline): ghostlib __init__.py, trackers.py, ble.py, net.py written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-27): APPROVED, no fixes. __init__.py, trackers.py, ble.py, net.py byte-identical to the tested prototype after CRLF -> LF fix. Next: Step 2.
- STATUS: STEP 1 DONE — next: Step 2 (Cline)
- Step 2 (Cline): ghostlib names.py, wifi.py, store.py, sweep.py written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-27): APPROVED, no fixes. names.py, wifi.py, store.py, sweep.py byte-identical to the tested prototype after CRLF -> LF fix. Next: Step 3.
- STATUS: STEP 2 DONE — next: Step 3 (Cline)
- Step 3 (Cline): ghostlib advice.py, cli.py, watch.py and bin/forgeos-ghost written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-27): APPROVED, no fixes. advice.py, cli.py, watch.py and bin/forgeos-ghost byte-identical to the tested prototype after CRLF -> LF fix. Cline tried one dir command (rejected). The engine runs on Robert's PC. Next: Step 4.
- STATUS: STEP 3 DONE — next: Step 4 (Cline)
- Step 4 (Cline): GhostFinder window, meter, menu entry, user service + timer, forgeos-setup.sh, common-modules.yml packages, test-find-extras.sh T1. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-27): APPROVED after 1 fix. Window, meter, menu entry, service, timer, forgeos-setup.sh and common-modules.yml byte-identical to the prototype (CRLF -> LF fixed). test-find-extras.sh T1: Cline dropped the backslash before the closing ) (would break the grep) — replaced with the prototype line. On Robert's PC: Find Anything, recipes, cool stuff and panic tests pass. Next: Step 5.
- STATUS: STEP 4 DONE — next: Step 5 (Cline)
- Step 5 (Cline): tests/ghost-fakes.sh, ghost-gui-fakes.sh, ghost-ble-world.py, ghost-fake-net.py, test-ghost.sh (A-C) written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-27): APPROVED after 2 fixes. ghost-gui-fakes.sh, ghost-ble-world.py, ghost-fake-net.py and test-ghost.sh byte-identical to the prototype (CRLF -> LF fixed). ghost-fakes.sh had 2 Cline mistakes (an extra ] after the neighbor list, and the escaped colon in "Neighbor\: Bob" dropped) — replaced with the prototype. On Robert's PC: tests A-C all pass. Next: Step 6.
- STATUS: STEP 5 DONE — next: Step 6 (Cline)
- Step 6 (Cline): tests/test-ghost-safe.sh (D-H), test-ghost-watch.sh (I-P), test-ghost-gui.sh (Q-S) written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-27): APPROVED, no fixes. test-ghost-safe.sh, test-ghost-watch.sh and test-ghost-gui.sh byte-identical to the tested prototype after CRLF -> LF fix. On Robert's PC: GhostFinder tests A-S all pass. Next: Step 7.
- STATUS: STEP 6 DONE — next: Step 7 (Cline)
- Step 7 (Cline): tests/ghost-fake-bluez.py, test-ghost-real.sh (U-V), test-ghost-files.sh (T) + 2 CI steps written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-27): APPROVED after 1 fix. ghost-fake-bluez.py, test-ghost-real.sh and the tests.yml CI steps byte-identical to the prototype (CRLF -> LF fixed). test-ghost-files.sh had 2 garbled lines (T1 dropped the backslash before ), T4 mangled the quotes around the CR check) — replaced with the prototype. On Robert's PC: all GhostFinder tests A-V pass (U-V with real D-Bus + fake BlueZ), plus Find Anything and recipe tests. All 7 steps done.
- STATUS: STEP 7 DONE — Job 12 complete (tag v0.13.0 after CI is green)
