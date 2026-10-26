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
