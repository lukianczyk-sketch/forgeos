# RABBIT BLUEPRINT — Job 16: Ransomware Tripwire

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (tests A-N pass, including the REAL kernel watcher test M,
plus Forge Helper and Family Mode tests). Each step prompt gives you the EXACT file contents. Copy them exactly.
Do not research, do not "improve", do not run commands.

## What it does
If any program starts scrambling (encrypting) your files, ForgeOS stops it within seconds, cuts the internet
and puts your files back - in plain English. Approved by Robert 2026-11-05.
1. **Root watcher** forgeos-tripwire.service (`forgeos-tripwire watch`): the kernel's fanotify (Python ctypes,
   no new package) tells it WHICH program finished writing WHICH file on the home drive and USB drives. Only
   Documents, Pictures, Desktop, Downloads, Music, Videos count; hidden folders, caches and game folders don't.
2. **Bait files**: "000 Bank statements.pdf" + "zzz Tax return 2026.docx" in each of those folders (sort first and
   last, hidden by the folder's .hidden file). Written to -> trigger at once. Deleted/renamed (inotify) right after
   a program scrambled files -> that program; nobody scrambling (you, by hand) -> only a quiet note, put back.
3. **Behavior**: a file "looks scrambled" when its first 64 KB are pure noise (randomness >= 7.5 bits/byte) and it
   lacks its type's signature bytes (photos, zips, Office files keep theirs). Trigger: 20 in 10 s, 150 in 10 min,
   or a ransom note (HOW_TO_DECRYPT.txt...) + 5. Trusted: /etc/forgeos/tripwire-trusted.list (borg, restic, git,
   rpm-ostree, flatpak, snapper, Pika Backup) + "It's mine" programs (exe + sha256; for Wine/python only that exact
   command line).
4. **Trigger (about 1 second)**: freeze the whole app (cgroup.freeze of its app-*.scope; otherwise SIGSTOP of the
   program and its children), cut the internet (`nmcli networking off`, state in /run/forgeos-tripwire/net-cut),
   keep the last pre-attack snapshot (`snapper modify -c ""`) and take a new one, save
   /var/lib/forgeos-tripwire/incidents/ID.json (root-owned 0640, the person's group) and tell their session
   (/run/forgeos-tripwire/alert-UID).
5. **Your session** forgeos-tripwire-alert.service (`alert-watch`): critical notification (shows over full-screen
   games), Always-On Guard warnings list (kind "ransomware"), big red window `forgeos-tripwire-gui --incident ID`:
   Put my files back (recommended) / Remove the program / It's mine, let it go (PC password) / Decide later.
6. **Put my files back** runs as YOU: every touched file from the newest Undo Button snapshot taken BEFORE the attack
   (not a scrambled copy), deleted originals in those folders too; scrambled copies -> Always-On Guard's locked
   folder. Reports files that can't come back (made after that snapshot, or on USB drives).
7. **Remove the program**: pkexec /usr/libexec/forgeos-tripwire-helper remove ID (no password for the person at the
   PC): cgroup.kill / SIGKILL; its program file (if in your home) is locked away. **It's mine**: pkexec
   /usr/libexec/forgeos-tripwire-release release ID (asks for the PC password). Internet: only on "Turn the internet
   back on" (helper net-on). Root only acts on the caller's own incidents (PKEXEC_UID).
8. **Test the tripwire**: a harmless pretend attacker scrambles 30 test letters in Documents/ForgeOS tripwire test
   (own app scope); caught, ended, internet left on, folder removed: "Caught ... 1.0 seconds after it started."
9. **Ties in**: Forge Helper tool `ransomware` + help card; Family Mode guard list; Always-On Guard warnings.

## Files
- files/system/usr/bin/forgeos-tripwire (status | report | restore ID | remove ID | release ID | net-on | test |
  watch [--feed F | --for S] | alert-watch [--once] | root-do ...), files/system/usr/bin/forgeos-tripwire-gui
- files/system/usr/lib/forgeos-tripwire/tripwirelib/: __init__ kernel scramble bait procs detect incident restore
  watch alert actions cli (.py)
- files/system/usr/libexec/forgeos-tripwire-helper, forgeos-tripwire-release; polkit org.forgeos.tripwire.policy
- systemd: system forgeos-tripwire.service, user forgeos-tripwire-alert.service
- files/system/etc/forgeos/tripwire-trusted.list, applications/forgeos-tripwire.desktop,
  helper/help/ransomware-tripwire.md
- edits: forgeos-setup.sh (chmod + 2 enable lines), helperlib tools/looks/actions/rules, tools-2.jsonl,
  tests/test-helper-ai.sh (G3), familylib/guards.py, .github/workflows/tests.yml
- tests/tripwire-fakes.sh, test-tripwire.sh (A-C), test-tripwire-more.sh (D-E4), test-tripwire-bait.sh (E5-E8),
  test-tripwire-restore.sh (F-G), test-tripwire-actions.sh (H-J), test-tripwire-gui.sh (K-L),
  test-tripwire-kernel.sh (M, real kernel, needs sudo), test-tripwire-files.sh (N)

## Steps (one Cline task each)
1. bin/forgeos-tripwire, tripwirelib __init__.py, kernel.py, scramble.py
2. tripwirelib bait.py, procs.py, detect.py
3. tripwirelib incident.py, restore.py
4. tripwirelib watch.py, alert.py, cli.py
5. tripwirelib actions.py, 2 root helpers, polkit, trusted list, 2 systemd units
6. window, menu entry, help card + edits: setup, Forge Helper (4 files + tools-2.jsonl + test-helper-ai.sh),
   Family Mode guards
7. tests/tripwire-fakes.sh, test-tripwire.sh
8. tests/test-tripwire-more.sh, test-tripwire-bait.sh, test-tripwire-restore.sh
9. tests/test-tripwire-actions.sh, test-tripwire-gui.sh
10. tests/test-tripwire-kernel.sh, test-tripwire-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.
- Run bits (Claude sets them in git): bin/forgeos-tripwire, bin/forgeos-tripwire-gui,
  libexec/forgeos-tripwire-helper, libexec/forgeos-tripwire-release = 755.

## Honest limits
Work done between the last hourly snapshot and the attack may not all come back (the bait files keep that to a few
files). Files on USB drives or the Windows drive are protected (the program is frozen) but can't be put back. A
program that has the PC password (root) could fight it. Checked on the real PC at the end of the full build:
fanotify on Bazzite's btrfs /var/home under SELinux, freezing a Bottles/Wine program, the red window over a
full-screen game, restore speed for a few thousand files, kdialog showing the red rich text.
