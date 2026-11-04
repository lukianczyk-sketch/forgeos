# RABBIT BLUEPRINT — Job 14: Moving Day

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (tests A-L pass). Each step prompt gives you the EXACT
file contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
Moving Day brings your things over from Windows into ForgeOS: Documents, Pictures, Music, Videos, Desktop,
Downloads, bookmarks (Chrome, Edge, Brave, Firefox -> a "From Windows" folder in Brave), saved passwords
(exported in Windows, imported into Brave, then erased) and a list of the programs you used with the free
ForgeOS way for each one (from Will It Run?'s lists). Approved TRIMMED by Robert 2026-11-03: no Wi-Fi keys, no Steam copy.
1. **Where from**: the Windows drive on this PC, an old PC's drive by USB, or a "Moving Box" USB stick made with
   "Pack my old PC" (a .cmd + PowerShell script that only reads the old PC and writes only to the stick).
2. **Read-only**: root helper forgeos-movingday-mount (PC password, polkit org.forgeos.movingday.mount) mounts the
   drive read-only (ntfs3, then ntfs-3g; exfat/vfat). BitLocker: `cryptsetup open --type bitlk --readonly` with the
   48-digit recovery key from stdin. The start-up (EFI) partition is refused.
3. **Never overwrites**: a taken name gets " (from Windows)". Windows junk (desktop.ini, Thumbs.db, .lnk, ~$ files),
   links and real password exports are left behind. A log lets a second run go on where the first stopped.
   Room check first (1 GB always kept free); a full drive stops cleanly. Undo Button snapshot first;
   Always-On Guard virus-checks every copied file.
4. **Passwords**: copied into ~/Moving Day passwords (0700, files 0600), Brave's page address on the clipboard,
   erased (zeros, then deleted) when you click Done, or after 24 hours (systemd-run timer).
5. Window "Moving Day" (kdialog), first-login offer (once, only when Windows is found), Forge Helper tool
   `moving_day` + help card "Moving Day: bring your things over from Windows".

## Files
- files/system/usr/bin/forgeos-movingday (find | open DEV [--key-stdin] | close DEV | scan | move | programs |
  passwords | passwords-done | pack-stick | report | free), files/system/usr/bin/forgeos-movingday-gui (--first-run)
- files/system/usr/lib/forgeos-movingday/movelib/: __init__ sources files scan passwords programs bookmarks brave move cli stick (.py)
- files/system/usr/libexec/forgeos-movingday-mount (open DEV [--key-stdin] | close DEV), forgeos-movingday-screens
- files/system/usr/share/forgeos/movingday/pack.ps1, "Pack my old PC.cmd"
- files/system/usr/share/polkit-1/actions/org.forgeos.movingday.policy
- files/system/usr/share/applications/forgeos-movingday.desktop; files/system/etc/xdg/autostart/forgeos-movingday-firstrun.desktop
- files/system/usr/share/forgeos/helper/help/moving-day.md
- edits: forgeos-setup.sh (chmod), helperlib tools/looks/actions/rulelist, tools-2.jsonl, tests/test-helper-ai.sh (G3), .github/workflows/tests.yml
- tests/movingday-fakes.sh, movingday-tree.sh, test-movingday.sh (A-C), test-movingday-move.sh (D-F),
  test-movingday-more.sh (G-I), test-movingday-win.sh (J), test-movingday-gui.sh (K), test-movingday-files.sh (L)
- No new packages (cryptsetup, ntfs3, wl-clipboard are already in the image).

## Steps (one Cline task each)
1. bin/forgeos-movingday, movelib __init__.py, sources.py, files.py
2. movelib scan.py, passwords.py, programs.py
3. movelib bookmarks.py, brave.py, move.py
4. movelib cli.py, stick.py, libexec/forgeos-movingday-mount
5. bin/forgeos-movingday-gui, libexec/forgeos-movingday-screens
6. Windows files, polkit, 2 desktop files, help card + edits (setup, Forge Helper, test-helper-ai.sh)
7. tests/movingday-fakes.sh, movingday-tree.sh, test-movingday.sh
8. tests/test-movingday-move.sh, test-movingday-more.sh
9. tests/test-movingday-win.sh, test-movingday-gui.sh, test-movingday-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.
- Run bits (Claude sets them in git): bin/forgeos-movingday, bin/forgeos-movingday-gui, libexec/forgeos-movingday-mount = 755.

## Honest limits
Saved passwords can't be read from Windows directly (Windows locks them to the account): they are exported in
Windows. Outlook/Windows Mail email does not come over (Thunderbird + sign in again). Files that are only in
OneDrive's cloud can't be read from the drive. BitLocker drives need the recovery key (TPM-only unlock is not
possible from Linux); real BitLocker and the Brave password import are checked on the real PC at the end of the full build.
