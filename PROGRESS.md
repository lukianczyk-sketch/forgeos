# PROGRESS — Job 13b: Always-On Guard

## Step 0 — Claude: research, prototype + blueprint
- Prototype written and tested by Claude in the cloud (Ubuntu 24.04, Python 3.12) and on Robert's PC (Ubuntu 22.04, Python 3.10) with a REAL ClamAV 1.5.4 (clamscan + clamd + clamdscan, test-only EICAR signature), real inotify, real mbox + Maildir mail files: tests A-Q all pass (20 repeat runs of the timing tests, no flakes), shellcheck clean, pyflakes clean, 31 mutation checks: 28 caught, 3 do not change behavior (a default never used, a double safety check, a >5 MB-only path). All older tests still pass. Facts checked: Fedora 44 clamd/clamav file lists, ClamAV source + docs, flatpak-run.c (/etc/hosts), Firefox DoH prefs.
- STATUS: STEP 0 DONE — next: Step 1 (Cline)
- Step 1 (Cline): guardlib __init__.py, scan.py, quarantine.py, inotify.py, alerts.py written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-28): APPROVED, no fixes. __init__.py, scan.py, quarantine.py, inotify.py and alerts.py byte-identical to the tested prototype (only Windows line endings, turned back to Linux ones). On Robert's PC: Always-On Guard tests A-D pass with these files (real ClamAV). Next: Step 2.
- STATUS: STEP 1 DONE — next: Step 2 (Cline)
- Step 2 (Cline): guardlib downloads.py, mail.py, inbox.py, watch.py written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-28): APPROVED, no fixes. downloads.py, mail.py, inbox.py and watch.py byte-identical to the tested prototype (only Windows line endings, turned back to Linux ones). On Robert's PC: Always-On Guard tests E-L pass with these files (real ClamAV, real inotify, real mail files). Next: Step 3.
- STATUS: STEP 2 DONE — next: Step 3 (Cline)
- Step 3 (Cline): guardlib cli.py, bin/forgeos-guard, bin/forgeos-guard-gui, libexec/forgeos-guard-hosts written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-28): APPROVED, no fixes. cli.py, bin/forgeos-guard, bin/forgeos-guard-gui and libexec/forgeos-guard-hosts byte-identical to the tested prototype (only Windows line endings, turned back to Linux ones). On Robert's PC: Always-On Guard tests C-D, M-N and O-P pass with these files. Next: Step 4.
- STATUS: STEP 3 DONE — next: Step 4 (Cline)
- Step 4 (Cline): clamd forgeos.conf, guard-allow.list, forgeos-clamd/forgeos-guard-hosts services + path, user forgeos-guard.service, forgeos-guard.desktop, forgeos-setup.sh, common-modules.yml (clamd), Family Mode guards.py written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-31): APPROVED with 1 fix. Cline left out edit J2 (the "Website Guard" line in Family Mode guards.py) - replaced guards.py with the tested prototype. The 7 new files, forgeos-setup.sh and common-modules.yml are byte-identical to the tested prototype (only Windows line endings, turned back to Linux ones). On Robert's PC: Family Mode tests (all 6), recipe tests and Always-On Guard tests C-D, M-N, O-P and Q pass. Next: Step 5.
- STATUS: STEP 4 DONE — next: Step 5 (Cline)
- Step 5 (Cline): tests/guard-fakes.sh, guard-gui-fakes.sh, test-guard.sh (A-B), test-guard-more.sh (C-D) written. Waiting for Claude's review.
- CLAUDE REVIEW (2026-10-31): APPROVED with 1 fix. Cline dropped the empty last line of tests/guard-gui-fakes.sh - replaced it with the tested prototype. guard-fakes.sh, test-guard.sh and test-guard-more.sh are byte-identical to the tested prototype (only Windows line endings, turned back to Linux ones). On Robert's PC: Always-On Guard tests A-D pass in the repo (real ClamAV clamscan + clamd, no skips). Next: Step 6.
- STATUS: STEP 5 DONE — next: Step 6 (Cline)
