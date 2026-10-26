# PROGRESS — Job 6: Panic Button

## Step 0 — Claude: prototype + blueprint
- Prototype written and tested by Claude on Linux: 13/13 test cases pass (as root and as a normal user), shellcheck -S warning clean, 7 mutation checks all caught, polkit policy loaded by a real polkitd (`pkaction` shows implicit active: yes + exec.path), desktop-file-validate + xmllint clean.
- STATUS: STEP 0 DONE — next: Step 1 (Cline)

## Step 1 — Panic Button root helper + polkit rule + setup + packages
- Files changed: files/system/usr/libexec/forgeos-panic-helper (new), files/system/usr/share/polkit-1/actions/org.forgeos.panic.policy (new), files/scripts/forgeos-setup.sh, recipes/recipe.yml
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-25): APPROVED. Helper + policy byte-identical to the tested prototype after CRLF -> LF fix (Cline wrote CRLF). forgeos-setup.sh chmod line and recipe.yml packages exactly as asked. Next: Step 2.
- STATUS: STEP 1 DONE — next: Step 2 (Cline)

## Step 2 — Panic Button command + menu entries + shortcut
- Files changed: files/system/usr/bin/forgeos-panic (new), files/system/usr/share/applications/forgeos-panic.desktop (new), files/system/usr/share/applications/forgeos-all-clear.desktop (new)
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-25): APPROVED. All 3 files byte-identical to the tested prototype after CRLF -> LF fix. Next: Step 3 (tests).
- STATUS: STEP 2 DONE — next: Step 3 (Cline)
