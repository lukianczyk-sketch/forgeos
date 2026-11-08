# Job 19 Find My PC (private) — progress log

- 2026-11-07: Design approved by Robert. Claude wrote and tested the prototype (tests A-K pass, plus every other ForgeOS test).
- STATUS: STEP 0 DONE — next: Step 1 (Cline)
- Step 1 (Cline): bin/forgeos-locate, locatelib __init__.py, seal.py, relay.py written. Claude reviewed: seal.py + relay.py were made up and __init__.py had 3 extra blank lines - all put back from the prototype.
- Step 2 (Cline): locatelib where.py, commands.py written. Waiting for Claude's review.
- Step 3 (Cline): locatelib watch.py, setup.py, alert.py written. Waiting for Claude's review.
- Step 4 (Cline): locatelib report.py, cli.py, libexec forgeos-locate-root, polkit, 2 units, desktop file, help card, settings.json written. Waiting for Claude's review.
- Step 5 (Cline): bin/forgeos-locate-gui, libexec forgeos-locate-setup written. Claude reviewed: doubled backslashes in both files - put back from the prototype.
- Step 6 (Cline): docs/.nojekyll, docs/find index.html, find.css, fmp-crypto.js written. Claude reviewed: .nojekyll lost its last period - put back from the prototype.
- Step 7 (Cline): docs/find find-show.js, find.js written. Waiting for Claude's review.
- Step 8 (Cline): forgeos-setup.sh, common-modules.yml, tools-2.jsonl, test-helper-ai.sh edited. Waiting for Claude's review.
- Step 9 (Cline): Forge Helper rules.py, tools.py, actions.py, looks.py edited. Claude reviewed: rules.py LOC lines lost 2 spaces of indent - put back from the prototype.
- Step 10 (Cline): tests/locate-fakes.sh, locate-fake-relay.py written. Waiting for Claude's review.
- Step 11 (Cline): tests/test-locate.sh (A-C), test-locate-watch.sh (D-E) written. Waiting for Claude's review.
- Step 12 (Cline): tests/test-locate-commands.sh (E8-F), test-locate-alert.sh (G) written. Waiting for Claude's review.
- Step 13 (Cline): tests/test-locate-gui.sh (H-I), test-locate-page.sh (J) written. Claude reviewed: test-locate-gui.sh H line 28 lost 4 answers - put back from the prototype.
- Step 14 (Cline): tests/test-locate-files.sh (K) + CI step written. Waiting for Claude's review.
- Step 10-12 (Cline): reviewed, exact. Step 13: test-locate-gui.sh H line lost 4 answers - put back from the prototype. Step 14: test-locate-files.sh K3 quoting broken - put back from the prototype.
- 2026-11-08: Claude ran every test in tests.yml (Job 19 A-K all pass; sandbox-only failures same as v0.23.0: 7z missing for Digital Will, sudo/guard tests). Code commit e59f440. DONE — tag v0.24.0.
