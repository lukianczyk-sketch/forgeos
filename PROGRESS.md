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

## Step 2 — Scam Shield command + list downloader + service + timer + setup + package
- Files changed: files/system/usr/bin/forgeos-scamshield (new), files/system/usr/libexec/forgeos-scamshield-update (new), files/system/usr/lib/systemd/system/forgeos-scamshield-update.service (new), files/system/usr/lib/systemd/system/forgeos-scamshield-update.timer (new), files/scripts/forgeos-setup.sh, recipes/recipe.yml
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-25): APPROVED after one fix. forgeos-scamshield-update, the service and the timer byte-identical to the tested prototype after CRLF -> LF fix. forgeos-setup.sh (chmod + timer) and recipe.yml (wl-clipboard) exactly as asked. forgeos-scamshield: Cline doubled the backslashes in the AI prompt text (`\\n`, `\\\"`), which would have sent broken text to the AI — replaced with the prototype. Smoke test on Robert's PC: a gift-card + fake USPS message = "Looks like a scam" (exit 2). Next: Step 3.
- STATUS: STEP 2 DONE — next: Step 3 (Cline)
