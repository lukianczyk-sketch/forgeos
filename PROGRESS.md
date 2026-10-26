# PROGRESS — Job 9: Ask Your PC

## Step 0 — Claude: prototype + blueprint
- Prototype written and tested by Claude on Linux (mawk and gawk) and on Robert's PC: 44/44 test checks pass (cases A-N), shellcheck clean, 16 mutation checks all caught. Real-tool smoke test (status + health) on Robert's PC works and degrades cleanly when a tool is missing. Bazzite re-checked: Alpaca can chat offline but cannot see or fix the system; nothing in the way.
- STATUS: STEP 0 DONE — next: Step 1 (Cline)

## Step 1 — Ask Your PC health snapshot + fix list + blueprint
- Files changed: RABBIT-BLUEPRINT.md (new), PROGRESS.md (new), files/system/usr/libexec/forgeos-askpc-lib (new), files/system/usr/libexec/forgeos-askpc-fixes (new)
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-26): APPROVED, no fixes. RABBIT-BLUEPRINT.md, forgeos-askpc-lib and forgeos-askpc-fixes byte-identical to the tested prototype after CRLF -> LF fix (Cline wrote CRLF). Next: Step 2.
- STATUS: STEP 1 DONE — next: Step 2 (Cline)

## Step 2 — Ask Your PC command + setup
- Files changed: files/system/usr/bin/forgeos-askpc (new), files/scripts/forgeos-setup.sh
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-26): APPROVED after one fix. forgeos-setup.sh (chmod line) exactly as asked. forgeos-askpc: Cline moved a quote at the end of the AI request (`}]}'") || body=""` instead of `}]}')" || body=""`, would break the script) and added a blank last line — replaced with the prototype. On Robert's PC: Ask Your PC tests A-L + N1 pass (the window, menu entry and CI checks come in Steps 3-4). Next: Step 3.
- STATUS: STEP 2 DONE — next: Step 3 (Cline)

## Step 3 — Ask Your PC window + menu entry
- Files changed: files/system/usr/bin/forgeos-askpc-gui (new), files/system/usr/share/applications/forgeos-askpc.desktop (new)
- Notes: none
- STATUS: WAITING FOR CLAUDE REVIEW
- CLAUDE REVIEW (2026-10-26): APPROVED, no fixes. forgeos-askpc-gui and forgeos-askpc.desktop byte-identical to the tested prototype after CRLF -> LF fix. On Robert's PC: all Ask Your PC tests pass except N3 (the CI step comes in Step 4). Next: Step 4.
- STATUS: STEP 3 DONE — next: Step 4 (Cline)
