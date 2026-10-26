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
