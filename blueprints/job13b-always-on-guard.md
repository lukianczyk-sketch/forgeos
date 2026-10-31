# RABBIT BLUEPRINT — Job 13b: Always-On Guard

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype. Each step prompt gives you the EXACT file
contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
"No buttons to remember." Three guards that run by themselves, for every user:
1. **Download Guard** — every new file in Downloads and on the Desktop is virus-checked (ClamAV) the
   moment it finishes downloading (browser part files like .crdownload are skipped until renamed).
   A virus = the file is locked away (~/.local/share/forgeos/guard/quarantine, chmod 000, never deleted
   silently) + a big warning window. Windows programs, scripts, macro files and fake double endings
   (invoice.pdf.exe) get a "be careful, check it with Will It Run?" pop-up.
   Fast mode: the always-ready checker forgeos-clamd.service (only on PCs with about 6 GB of memory
   or more; files are streamed to it with `clamdscan --stream`). Low-memory mode: clamscan, one run per batch.
2. **Website Guard** — known scam and virus websites (Scam Shield's free daily lists) are blocked for the
   whole PC in a marked block in /etc/hosts (0.0.0.0 + ::). Lines outside the block are never touched.
   Rebuilt at boot and whenever the lists change (forgeos-guard-hosts.path). Unblocking a website needs
   the PC password (pkexec) and a warning first.
3. **Email Guard** — every NEW Thunderbird email (Flatpak or normal profile, mbox or Maildir, Junk/Sent/
   Trash/Drafts skipped) is checked by Scam Shield (rules first, the private AI only for "be careful"),
   and its attachments are virus-checked in memory. Warning pop-up with "Show why"; at most one a minute.
   Thunderbird's files are only read, never changed.
Window: forgeos-guard-gui (menu "Always-On Guard"). Family Mode's guard list now includes it.

## Key facts (checked by Claude on 2026-10-28)
- Fedora 44: package `clamd` (1.4.4) = /usr/bin/clamd; clamdscan + clamonacc are already in `clamav`.
- ClamAV signatures need about 1.2 GB of memory in clamd (docs.clamav.net) -> ConditionMemory=>=5500M,
  ConcurrentDatabaseReload no (no 2.4 GB spike during the daily reload).
- `clamdscan --stream` (and `-` for stdin) sends the file's bytes, so clamd never opens your files
  (no SELinux antivirus_can_scan_system needed). Tested with a real clamd + EICAR test signature.
- Flatpak apps see the host's /etc/hosts (flatpak-run.c); Firefox DoH skips names in /etc/hosts.
- inotify through Python ctypes (no new package). Python standard library only.

## Files
- files/system/usr/lib/forgeos-guard/guardlib/: __init__.py (paths, settings, warnings log, risky names),
  scan.py (ClamAV), quarantine.py, inotify.py, alerts.py (pop-ups), downloads.py, mail.py (one email),
  inbox.py (Thunderbird folders, only new mail), watch.py (the watcher), cli.py (commands)
- files/system/usr/bin/forgeos-guard — status | scan FILE... | quarantine list|restore ID|delete ID |
  events [N] | why ID | on|off downloads|email|all | check-mail FILE | watch [--for N]
- files/system/usr/bin/forgeos-guard-gui — kdialog window (--why ID)
- files/system/usr/libexec/forgeos-guard-hosts — apply | remove | allow D | unallow D | status (root)
- files/system/etc/clamd.d/forgeos.conf, files/system/etc/forgeos/guard-allow.list
- files/system/usr/lib/systemd/system/forgeos-clamd.service, forgeos-guard-hosts.service, forgeos-guard-hosts.path
- files/system/usr/lib/systemd/user/forgeos-guard.service
- files/system/usr/share/applications/forgeos-guard.desktop
- files/scripts/forgeos-setup.sh (chmod + enable), recipes/common-modules.yml (+ clamd),
  files/system/usr/lib/forgeos-family/familylib/guards.py (+ 2 guards)
- tests/guard-fakes.sh, guard-gui-fakes.sh, test-guard.sh (A-B), test-guard-more.sh (C-D),
  test-guard-watch.sh (E-H), test-guard-mail.sh (I), test-guard-inbox.sh (J-L), test-guard-hosts.sh (M-N),
  test-guard-gui.sh (O-P), test-guard-files.sh (Q) + 1 CI step

## Steps (one Cline task each)
1. guardlib __init__.py, scan.py, quarantine.py, inotify.py, alerts.py
2. guardlib downloads.py, mail.py, inbox.py, watch.py
3. guardlib cli.py, bin/forgeos-guard, bin/forgeos-guard-gui, libexec/forgeos-guard-hosts
4. clamd settings, allow list, 4 services, menu entry, forgeos-setup.sh, common-modules.yml, Family Mode guards.py
5. tests/guard-fakes.sh, guard-gui-fakes.sh, test-guard.sh, test-guard-more.sh
6. tests/test-guard-watch.sh, test-guard-mail.sh, test-guard-inbox.sh
7. tests/test-guard-hosts.sh, test-guard-gui.sh, test-guard-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.

## Honest limits
Email Guard warns; it cannot pull an email out of Thunderbird (changing its files while it runs could
break them), and webmail in a browser is covered by Download Guard + Website Guard instead. A blocked
website shows the browser's "can't reach this site" page, not a ForgeOS page. Files over 400 MB are not
virus-checked (noted in the warnings list). PCs under about 6 GB of memory check with clamscan (20-40 s
per batch instead of under a second).
