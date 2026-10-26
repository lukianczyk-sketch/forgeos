# PROGRESS — Job 7: Privacy Report

## Step 0 — Claude: prototype + blueprint
- Prototype written and tested by Claude on Linux: 42/42 test checks pass (cases A-O), shellcheck clean, 20 mutation checks all caught. Also run against a real PipeWire + WirePlumber + pipewire-pulse (mic seen, speaker-sound recorder skipped, blocked app muted within half a second) and a real Flatpak 1.14 test app (camera / files block + undo, report lists).
- STATUS: STEP 0 DONE — next: Step 1 (Cline)

## Step 1 — Privacy Report note-taker + report + service + setup + package
- Files changed: RABBIT-BLUEPRINT.md (new), PROGRESS.md (new), files/system/usr/libexec/forgeos-privacy-lib (new), files/system/usr/bin/forgeos-privacy (new), files/system/usr/lib/systemd/user/forgeos-privacy-watch.service (new), files/scripts/forgeos-setup.sh, recipes/recipe.yml
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-25): APPROVED. Blueprint, forgeos-privacy-lib and the user service byte-identical to the tested prototype after CRLF -> LF fix (Cline wrote CRLF). forgeos-privacy: the part 2 join added one extra blank line before the case block — replaced with the prototype. forgeos-setup.sh (chmod + global enable) and recipe.yml (pipewire-utils) exactly as asked. Next: Step 2.
- STATUS: STEP 1 DONE — next: Step 2 (Cline)

## Step 2 — Privacy Report block button + window + menu entry
- Files changed: files/system/usr/bin/forgeos-privacy-block (new), files/system/usr/bin/forgeos-privacy-gui (new), files/system/usr/share/applications/forgeos-privacy.desktop (new), files/scripts/forgeos-setup.sh
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-25): APPROVED. forgeos-privacy-block, forgeos-privacy-gui and the menu entry byte-identical to the tested prototype after CRLF -> LF fix. forgeos-setup.sh chmod line exactly as asked. Next: Step 3 (tests).
- STATUS: STEP 2 DONE — next: Step 3 (Cline)

## Step 3 — Privacy Report tests
- Files changed: tests/test-privacy.sh (new), .github/workflows/tests.yml
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-25): APPROVED after one fix. tests.yml step exactly as asked. test-privacy.sh: Cline turned the real tab characters in checks B1/B2 into the text "\t" (grep would then never match) — replaced with the tested prototype. On Robert's PC: `bash tests/test-privacy.sh .` = ALL PASS (41, O6 skipped: no desktop-file-validate there); panic, clean-sweep, undo tests still pass. Next: GitHub Actions green, then tag v0.8.0.
- STATUS: STEP 3 DONE — next: Actions run green, then tag v0.8.0
