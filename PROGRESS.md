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
