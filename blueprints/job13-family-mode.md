# RABBIT BLUEPRINT — Job 13: Family Mode

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype. Each step prompt gives you the EXACT file
contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
"Family Mode — one switch makes this PC easy and safe." For an older person (or anyone).
1. **Big text** (Big = 1.4x or Bigger = 1.8x): every KDE font, a bigger mouse pointer (48 / 64)
   and a taller taskbar (56 / 68). Live, no logout. Always counted from the saved originals.
2. **Safety on**: the user's own guards are switched on (Privacy Report watch, GhostFinder
   watch); the PC-wide ones are checked and shown (virus list, Clean Sweep, Scam Shield,
   Will It Run? lists, Undo snapshots). Turning Family Mode off leaves the guards on.
3. **Call for help** (desktop icon + menu): opens RustDesk locked down — nobody gets in without
   clicking Accept, only the helper's RustDesk ID may even ask (when known), no permanent
   password, no file copying, no terminal, auto-disconnect after 30 idle minutes. It finds this PC's
   RustDesk ID, offers to text it to the helper through the phone paired in KDE Connect, warns
   "only click Accept while you are talking to <helper>", and closes RustDesk when done
   (or by itself after 2 hours).
4. **Desktop icons**: Call for help, Is this a scam?, Ask Your PC (only ours are ever removed).
Off = text, pointer, taskbar and RustDesk settings back exactly as they were. Everything changed
is written to ~/.local/state/forgeos/family/saved.json BEFORE the first change. No root.

## Key facts (checked by Claude on 2026-10-27)
- Fonts: kdeglobals [General] font, menuFont, toolBarFont, smallestReadableFont, [WM] activeFont
  (Plasma defaults Noto Sans 10 / 8, fontssettings.kcfg). `kwriteconfig6 --notify` + the D-Bus
  signal /KDEPlatformTheme org.kde.KDEPlatformTheme.refreshFonts (what the fonts page sends).
- Pointer: kcminputrc [Mouse] cursorSize + /KGlobalSettings notifyChange int32:5 int32:0
  (KWin reloads on CursorChanged = 5). plasma-apply-cursortheme is NOT used: its --size is ignored.
- Taskbar: org.kde.PlasmaShell.evaluateScript with panels() / panelById(id).height.
- RustDesk (Flathub 1.5.0): `--option` needs an installed copy + root, so the options are written
  into ~/.var/app/com.rustdesk.RustDesk/config/rustdesk/RustDesk2.toml [options] while RustDesk
  is NOT running. approve-mode=click, verification-method=use-temporary-password,
  id-whitelist=<helper ID>, enable-file-transfer/terminal/tunnel/remote-printer/camera=N,
  allow-remote-config-modification=N, enable-lan-discovery=N, direct-server=N,
  allow-auto-disconnect=Y, auto-disconnect-timeout=30. ID: `flatpak run --command=rustdesk
  com.rustdesk.RustDesk --get-id`.
- Text: `kdeconnect-cli -a --id-only`, then `kdeconnect-cli -d DEV --send-sms MSG --destination NUMBER`.
- 2-hour end: `systemd-run --user --on-active=2h --unit=forgeos-family-call-end --collect ... call-end`.
- No new packages: kf6-kconfig, plasma-workspace, kde-connect, libnotify, python3, RustDesk Flatpak
  are already in the image. Python standard library only (tomllib when present, simple reader else).

## Files
- files/system/usr/lib/forgeos-family/familylib/: __init__.py (paths, run, clean, saved.json),
  look.py (fonts, pointer, taskbar), rustdesk.py (lock / unlock, start, ID), helper.py
  (family.conf), guards.py (safety guards), call.py (Call for help, text, end), cli.py
  (on / off / status / size, desktop icons)
- files/system/usr/bin/forgeos-family — Python command: on [--size big|bigger], off, status,
  size big|bigger, guards, helper set --name N [--phone P] [--rustdesk-id ID] [--me NAME],
  helper show|clear, call, text ID, call-end. Exit 0 ok / 1 partly / 2 no helper / 3 wrong use / 4 offline.
- files/system/usr/bin/forgeos-family-gui — kdialog window (--helper = only the helper questions)
- files/system/usr/libexec/forgeos-family-call — the Call for help window
- files/system/usr/share/applications/forgeos-family.desktop, forgeos-callhelp.desktop
- files/scripts/forgeos-setup.sh — chmod the 3 programs
- tests/family-fakes.sh, test-family.sh (A-D), test-family-more.sh (E-G), test-family-rustdesk.sh
  (H-K), test-family-call.sh (L-N), test-family-gui.sh (O-Q), test-family-files.sh (R)
- .github/workflows/tests.yml — 1 new test step

## Steps (one Cline task each)
1. familylib/__init__.py, look.py, rustdesk.py, helper.py
2. familylib/guards.py, call.py, cli.py, bin/forgeos-family
3. bin/forgeos-family-gui, libexec/forgeos-family-call, 2 menu entries, forgeos-setup.sh chmod
4. tests/family-fakes.sh, test-family.sh, test-family-more.sh
5. tests/test-family-rustdesk.sh, test-family-call.sh, test-family-gui.sh, test-family-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.

## Honest limits
RustDesk's ID check trusts the ID the caller reports, so Accept is still the real lock (the window
says so). On Wayland the owner also has to allow screen sharing (a feature here). Apps that set
their own font size (some browsers) only grow with their own zoom. The PC-wide guards need a
password to switch back on, so Family Mode only shows them.
