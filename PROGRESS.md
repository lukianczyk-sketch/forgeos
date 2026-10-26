# PROGRESS — Job 10: Will It Run?

## Step 0 — Claude: prototype + blueprint
- Prototype written and tested by Claude on Linux (mawk and gawk) and on Robert's PC: 76/76 test checks pass (cases A-P), shellcheck clean, 13 mutation checks all caught, 30 repeat runs with no random failures. Real anti-cheat list (1167 games) downloaded and checked: Fortnite / Apex / Destiny 2 = No, Counter-Strike 2 / Genshin Impact = Yes. Bazzite re-checked: Bazzite 44 removed QEMU from the image (VMs only suggested via GNOME Boxes); Bottles 67.4 CLI, Waydroid and Gear Lever file opening checked in their source code.
- STATUS: STEP 0 DONE — next: Step 1 (Cline)

## Step 1 — Will It Run? file reader + anti-cheat check + known-programs lists + blueprint
- Files changed: RABBIT-BLUEPRINT.md (new), PROGRESS.md (new), files/system/usr/libexec/forgeos-willitrun-lib (new), files/system/usr/libexec/forgeos-willitrun-match (new), files/system/usr/share/forgeos/willitrun/1-games.txt (new), files/system/usr/share/forgeos/willitrun/2-office-media.txt (new), files/system/usr/share/forgeos/willitrun/3-internet-tools.txt (new)
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-26): APPROVED, no fixes. All 7 files byte-identical to the tested prototype after CRLF -> LF fix (Cline wrote CRLF; it also wrote the Step 1 entry straight into the new PROGRESS.md, which is fine). Robert asked for more safety: Claude added a safety check (virus scan with ClamAV, fake double endings like invoice.pdf.exe, the download website checked against the Scam Shield lists, cracked-program warning) to the prototype; it comes in Steps 2 and 4-5 (new file forgeos-willitrun-safety + tests/test-willitrun-safety.sh, case Q). Next: Step 2.
- STATUS: STEP 1 DONE — next: Step 2 (Cline)

## Step 2 — Will It Run? command + answers + open + safety check
- Files changed: files/system/usr/bin/forgeos-willitrun (new), files/system/usr/libexec/forgeos-willitrun-answers (new), files/system/usr/libexec/forgeos-willitrun-check (new), files/system/usr/libexec/forgeos-willitrun-windows (new), files/system/usr/libexec/forgeos-willitrun-open (new), files/system/usr/libexec/forgeos-willitrun-safety (new), RABBIT-BLUEPRINT.md, files/scripts/forgeos-setup.sh
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-26): APPROVED after two fixes. forgeos-willitrun, -check, -windows, -open, -safety and the forgeos-setup.sh chmod line byte-identical to the tested prototype after CRLF -> LF fix. forgeos-willitrun-answers: Cline moved a quote at the end of the AI request (`)]}'") || return 1` instead of `)}]}')" || return 1`, would break the script; same slip as Job 9 Step 2) — replaced with the prototype. RABBIT-BLUEPRINT.md: Cline only changed part of it (the safety-check section was missing) — replaced with the prototype. On Robert's PC: Will It Run? tests A-L and Q pass (M-P need Step 3). Next: Step 3.
- STATUS: STEP 2 DONE — next: Step 3 (Cline)

## Step 3 — Will It Run? list download + window + menu entries
- Files changed: files/system/usr/libexec/forgeos-willitrun-update (new), files/system/usr/lib/systemd/system/forgeos-willitrun-update.service (new), files/system/usr/lib/systemd/system/forgeos-willitrun-update.timer (new), files/system/usr/bin/forgeos-willitrun-gui (new), files/system/usr/share/applications/forgeos-willitrun.desktop (new), files/system/usr/share/kio/servicemenus/forgeos-willitrun.desktop (new), files/scripts/forgeos-setup.sh
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-26): APPROVED, no fixes. All 6 new files and both forgeos-setup.sh edits byte-identical to the tested prototype after CRLF -> LF fix. On Robert's PC: Will It Run? tests A-Q all pass except P5 (the CI step comes in Step 5). Next: Step 4.
- STATUS: STEP 3 DONE — next: Step 4 (Cline)
