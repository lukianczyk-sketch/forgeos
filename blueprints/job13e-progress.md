# Job 13e Install & Switch — progress log

- 2026-11-03: Design approved by Robert (installer USB + one-click Windows <-> ForgeOS switch; ForgeOS goes on another PC, not the Predator). Claude wrote and tested the prototype (tests A-H pass).
- STATUS: STEP 0 DONE — next: Step 1 (Cline)
- Step 1 (Cline): bin/forgeos-switch, libexec/forgeos-switch-boot, libexec/forgeos-switch-winsetup written. Waiting for Claude's review.
- Step 1 review (Claude): forgeos-switch, forgeos-switch-boot, forgeos-switch-winsetup md5-match the prototype. OK.
- STATUS: STEP 1 DONE — next: Step 2 (Cline)
- Step 2 (Cline): bin/forgeos-switch-gui, share/forgeos/switch (ps1 + cmd), polkit org.forgeos.switch.policy, 3 desktop files, help windows-forgeos.md, .github/workflows/iso.yml written. Waiting for Claude's review.
- Step 2 review (Claude): 9 files md5-match the prototype after one fix (Cline doubled the backslashes in "Restart into ForgeOS.cmd" line 4; Claude corrected it). OK.
- STATUS: STEP 2 DONE — next: Step 3 (Cline)
- Step 3 (Cline): forgeos-setup.sh, common-modules.yml (efibootmgr), Forge Helper tools/looks/actions/rulelist + tools-2.jsonl + test-helper-ai.sh, test-autopilot-files.sh Q1 written. Waiting for Claude's review.
- Step 3 review (Claude): 8 files md5-match the prototype after one fix (Cline mistyped the regex end "\( \|$\)" in test-autopilot-files.sh Q1; Claude corrected it). OK.
- STATUS: STEP 3 DONE — next: Step 4 (Cline)
- Step 4 (Cline): tests/switch-fakes.sh, switch-pwsh.sh, test-switch.sh (A-C) written. Waiting for Claude's review.
- Step 4 review (Claude): tests/switch-fakes.sh, switch-pwsh.sh, test-switch.sh md5-match the prototype. OK.
- STATUS: STEP 4 DONE — next: Step 5 (Cline)
- Step 5 (Cline): tests/test-switch-win.sh (D-F), test-switch-gui.sh (G), test-switch-files.sh (H) + CI step written. Waiting for Claude's review.
- Step 5 review (Claude): test-switch-win.sh, test-switch-gui.sh, tests.yml md5-match; test-switch-files.sh matches after one fix (Cline doubled a backslash in H1; Claude corrected it). OK.
- STATUS: STEP 5 DONE — next: Claude runs tests, commit, push, tag v0.18.0
