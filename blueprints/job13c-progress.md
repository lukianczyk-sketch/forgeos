# PROGRESS — Job 13c: Forge Helper

Rabbit Team: after each step add ONE line at the end, exactly as the step prompt says. Claude adds review notes.

- Step 0 (Claude, 2026-10-31): design approved by Robert; working prototype + 8 test files (A-Z) pass in the cloud and on the PC VM (Python 3.10); blueprint + 10 step prompts written.
- STATUS: STEP 0 DONE — next: Step 1 (Cline)
- Step 1 (Cline): helperlib __init__.py, ai.py, rulelist.py, rules.py, actions.py written. Waiting for Claude's review.
- Step 1 review (Claude): all 5 files byte-identical to the prototype. OK.
- STATUS: STEP 1 DONE — next: Step 2 (Cline)
- Step 2 (Cline): helperlib tools.py, looks.py, helpdocs.py, talk.py, router.py written. Waiting for Claude's review.
- Step 2 review (Claude): all 5 files byte-identical to the prototype. OK.
- STATUS: STEP 2 DONE — next: Step 3 (Cline)
- Step 3 (Cline): helperlib memory.py, checks.py, watch.py, selftest.py, cli.py and bin/forgeos-helper written. Waiting for Claude's review.
- Step 3 review (Claude): 5 of 6 files byte-identical. selftest.py: Cline moved a "}" in the docstring (line 4) - replaced with the prototype. OK.
- STATUS: STEP 3 DONE — next: Step 4 (Cline)
- Step 4 (Cline): forgeos-helper-gui, forgeos-helper-krunner, menu entry, KRunner + D-Bus files, 5 user units, candidates.txt, forgeos-setup.sh, common-modules.yml written. Waiting for Claude's review.
- Step 4 review (Claude): all 11 new files + forgeos-setup.sh + common-modules.yml byte-identical to the prototype. OK.
- STATUS: STEP 4 DONE — next: Step 5 (Cline)
- Step 5 (Cline): 33 help cards written (add-printer.md to office.md). Waiting for Claude's review.
- Step 5 review (Claude): 32 of 33 cards byte-identical. lock-screen.md: Cline dropped a space ("screenaway") - replaced with the prototype. OK.
- STATUS: STEP 5 DONE — next: Step 6 (Cline)
- Step 6 (Cline): 34 help cards written (other-game-stores.md to zip.md). Waiting for Claude's review.
- Step 6 review (Claude): all 34 cards byte-identical to the prototype; 67 cards total. OK.
- STATUS: STEP 6 DONE — next: Step 7 (Cline)
- Step 7 (Cline): 7 test question files written (howto-1.jsonl, howto-2.jsonl, more.jsonl, safety.jsonl, seniors.jsonl, tools-1.jsonl, tools-2.jsonl). Waiting for Claude's review.
- Step 7 review (Claude): all 7 test files byte-identical to the prototype (302 questions). OK.
- STATUS: STEP 7 DONE — next: Step 8 (Cline)
- Step 8 (Cline): tests/helper-fakes.sh, helper-fake-ollama.py, helper-last.py, helper-watch-run.py, helper-check-tests.py, helper-ai-map.json, test-helper.sh (A-F) written. Waiting for Claude's review.
- Step 8 review (Claude): 6 of 7 files byte-identical. helper-fakes.sh: Cline turned two \n into \t in the fake 'fixes' list - replaced with the prototype. test-helper.sh A-F: ALL PASS on the PC VM. OK.
- STATUS: STEP 8 DONE — next: Step 9 (Cline)
- Step 9 (Cline): tests/test-helper-ai.sh (G-K), test-helper-brains.sh (L), test-helper-do.sh (M-P), test-helper-watch.sh (Q-T) written. Waiting for Claude's review.
- Step 9 review (Claude): all 4 files byte-identical to the prototype. G-K, L1-L7, M-P, Q-T: ALL PASS on the PC VM. OK.
- STATUS: STEP 9 DONE — next: Step 10 (Cline)
- Step 10 (Cline): tests/test-helper-gui.sh (U-W), test-helper-krunner.sh (X), test-helper-files.sh (Y-Z) + CI step written. Waiting for Claude's review.
- Step 10 review (Claude): gui + tests.yml byte-identical. test-helper-krunner.sh (doubled backslashes in X4) and test-helper-files.sh (Y7 regex changed, Y8 pointed at the wrong unit) replaced with the prototype. All 118 Job 13c files now byte-identical. U-W, X1-X6, Y-Z + all 8 helper suites PASS on the PC VM; all other suites pass except the ClamAV Guard tests (VM was reset, no ClamAV here; files untouched by 13c - CI runs them). OK.
- STATUS: STEP 10 DONE — Job 13c code complete; next: commit + CI + docs + tag v0.16.0 (Claude)
