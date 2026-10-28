# PROGRESS — Job 13: Family Mode

## Step 0 — Claude: research, prototype + blueprint
- Prototype written and tested by Claude in the cloud (Python 3.13 with tomllib) and on Robert's PC (Python 3.10, simple TOML reader): tests A-R all pass (fake KDE settings, Plasma, RustDesk Flatpak, KDE Connect, systemctl, kdialog), shellcheck clean, pyflakes clean, desktop-file-validate clean, 30 mutation checks: 29 caught, 1 does not change behavior (a double safety check). All older tests still pass. Facts checked in the RustDesk 1.5.0 source, KDE kconfig, kwin, plasma-workspace and kdeconnect-kde sources.
- STATUS: STEP 0 DONE — next: Step 1 (Cline)
- Step 1 (Cline): familylib __init__.py, look.py, rustdesk.py, helper.py written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-27): APPROVED after 1 fix. __init__.py, look.py and helper.py byte-identical to the tested prototype. rustdesk.py line 83 dropped the brackets around the "quoted key" part of the regex (it would then miss "key" = ... lines) — replaced with the prototype. Next: Step 2.
- STATUS: STEP 1 DONE — next: Step 2 (Cline)
- Step 2 (Cline): familylib guards.py, call.py, cli.py and bin/forgeos-family written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-27): APPROVED, no fixes. guards.py, cli.py and bin/forgeos-family byte-identical to the tested prototype. call.py left out an extra empty line at the very end of the prototype — Cline's version is the cleaner one, so the prototype now matches it. On Robert's PC: Family Mode tests A-R all pass with these files. Next: Step 3.
- STATUS: STEP 2 DONE — next: Step 3 (Cline)
- Step 3 (Cline): forgeos-family-gui, libexec/forgeos-family-call, forgeos-family.desktop, forgeos-callhelp.desktop, forgeos-setup.sh chmod written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-28): APPROVED, no fixes. forgeos-family-gui, libexec/forgeos-family-call, forgeos-family.desktop, forgeos-callhelp.desktop and the forgeos-setup.sh chmod line byte-identical to the tested prototype. Older build-file tests (GhostFinder T, Find Anything T, Cool Stuff, recipes) still pass. Next: Step 4.
- STATUS: STEP 3 DONE — next: Step 4 (Cline)
- Step 4 (Cline): tests/family-fakes.sh, test-family.sh (A-D), test-family-more.sh (E-G) written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-28): APPROVED after 1 fix. test-family.sh and test-family-more.sh byte-identical to the tested prototype. family-fakes.sh line 24 (fake kreadconfig6) dropped the `k=""` start value — replaced with the prototype. On Robert's PC: Family Mode tests A-G all pass. Next: Step 5.
- STATUS: STEP 4 DONE — next: Step 5 (Cline)
