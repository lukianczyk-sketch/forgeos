# PROGRESS — Job 8: Scam Shield

## Step 0 — Claude: prototype + blueprint
- Prototype written and tested by Claude on Linux (mawk and gawk): 32/32 test checks pass (cases A-T), shellcheck clean, 13 mutation checks all caught. Bazzite re-checked (stable on Fedora 44, KDE Plasma 6.7): nothing in the way. wl-clipboard is in Fedora 44.
- STATUS: STEP 0 DONE — next: Step 1 (Cline)

## Step 1 — Scam Shield rule check + blueprint
- Files changed: RABBIT-BLUEPRINT.md (new), PROGRESS.md (new), files/system/usr/libexec/forgeos-scamshield-lib (new), files/system/usr/share/forgeos/scamshield-words.txt (new), files/system/usr/share/forgeos/scamshield-brands.txt (new)
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-25): APPROVED after one fix. Blueprint, scamshield-words.txt and scamshield-brands.txt byte-identical to the tested prototype after CRLF -> LF fix (Cline wrote CRLF). forgeos-scamshield-lib: one quote moved in line 98 (`"${host%."}` instead of `"${host%.}"`, would break the script) — replaced with the prototype. Next: Step 2.
- STATUS: STEP 1 DONE — next: Step 2 (Cline)
