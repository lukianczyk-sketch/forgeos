# RABBIT BLUEPRINT — Job 17: Fake Tech Support Guard

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (tests A-M pass, plus every other ForgeOS test).
Each step prompt gives you the EXACT file contents. Copy them exactly.
Do not research, do not "improve", do not run commands.

## What it does
Stops the #1 scam aimed at older people: "Your computer has a virus, call Microsoft" -> a stranger on the
phone gets you to install a remote-control app -> takes over the PC -> opens your bank. Approved by Robert
2026-11-06.
1. **Watcher in your session** forgeos-techguard.service (`forgeos-techguard watch`, every 2 seconds, no root):
   - **Remote App Alarm**: a remote-control app starts (26 apps in /usr/share/forgeos/techguard/remote-apps.txt:
     AnyDesk, TeamViewer, UltraViewer, ScreenConnect, LogMeIn/GoTo, Quick Assist, RustDesk... found by program
     name, program file, Flatpak id, or the Windows program name in Wine/Bottles) -> PAUSED at once (cgroup.freeze
     of its app scope; started from a terminal = SIGSTOP of that program only), critical note, Always-On Guard
     warning (kind techsupport), big red window `forgeos-techguard-gui --alarm ID`:
     Kick them out (recommended) / <helper> asked me to (only while Family Mode's Call for help runs) /
     I set this up myself (PC password; root saves the program's fingerprint in /var/lib/forgeos-techguard/
     trusted.json; for Wine only that exact command line) / Decide later (stays paused).
   - Family Mode on: the app is closed at once (only Call for help may connect). Call for help's RustDesk
     (while forgeos-family-call-end.timer waits) and trusted apps run on.
   - **Money lock**: anyone receiving a picture of the screen (pw-dump: a kwin-screencast stream; covers every
     remote app, video call or website screen share) -> bank, payment, gift-card and crypto websites locked for
     the whole PC (a marked block in /etc/hosts, 76 sites x 16 sign-in names, root helper through pkexec, no
     password) + one red note + Easy Passwords (KeePassXC) locked (`keepassxc --lock`, only when it is open);
     money sites opened again 10 seconds after the sharing stops. One try per sharing (never a
     password window every 2 seconds). "I'm sharing my screen on purpose" = PC password.
   - **Downloads**: a remote-control app file lands in Downloads or on the Desktop -> warning window with
     "Lock it away" (Always-On Guard's locked folder).
2. **Kick them out** (menu entry + Ctrl+Alt+K + a Family Mode desktop icon, `forgeos-techguard-gui --kick`):
   ends every remote app (paused, trusted or the helper's) and every program showing the screen, cuts the
   internet (`nmcli networking off`), closes the web browsers (a stuck fake virus page), then a checklist of
   what a stranger may have left (remote apps installed, remote app files, NEW autostart / background / program
   entries of the last day; remove one at a time), the last steps (call your bank with the number on your card,
   never gift cards) and Clean Sweep. The internet comes back only on "Turn the internet back on".
3. **Test the guard**: a harmless pretend remote app (the sleep program named AnyDesk) is caught and ended.
4. **Ties in**: Forge Helper tool `tech_support` (rule before Scam Shield) + help card; Family Mode guard list +
   "Kick them out" desktop icon; Scam Shield's remote-control warning points to Ctrl+Alt+K.

## Files
- files/system/usr/bin/forgeos-techguard (status | report | watch [--once] | kick | escape | net-on | end ID |
  allow ID | helper ID | share-ok | checklist | remove flatpak|file VALUE | lock-file PATH | test |
  root-money lock|unlock | root-trust add PID|share), files/system/usr/bin/forgeos-techguard-gui
- files/system/usr/lib/forgeos-techguard/techguardlib/: __init__ apps procs screen notes alarm money watch kick
  actions cli (.py)
- files/system/usr/libexec/forgeos-techguard-money, forgeos-techguard-trust, forgeos-techguard-screens (sourced
  by the window); polkit org.forgeos.techguard.policy; user unit forgeos-techguard.service
- files/system/usr/share/forgeos/techguard/remote-apps.txt, money-sites.txt; applications/forgeos-techguard.desktop,
  forgeos-kickout.desktop; helper/help/tech-support-guard.md
- edits: forgeos-setup.sh (a NEW chmod line + 1 enable line), helperlib tools/looks/actions/rules,
  tools-2.jsonl, tests/test-helper-ai.sh (G3), familylib/guards.py + cli.py, scamshield-words.txt,
  .github/workflows/tests.yml
- tests/techguard-fakes.sh, test-techguard.sh (A-C), test-techguard-more.sh (D-F), test-techguard-money.sh (G-H),
  test-techguard-kick.sh (I-J), test-techguard-gui.sh (K-L), test-techguard-files.sh (M)

## Steps (one Cline task each)
1. bin/forgeos-techguard, techguardlib __init__.py, apps.py, remote-apps.txt
2. techguardlib procs.py, screen.py, notes.py
3. techguardlib alarm.py, money.py, money-sites.txt
4. techguardlib watch.py, kick.py
5. techguardlib actions.py, cli.py
6. 2 root helpers, polkit, user unit, 2 menu entries, help card
7. the window (bin/forgeos-techguard-gui) and its screens (libexec/forgeos-techguard-screens)
8. edits: setup, Forge Helper (4 files + tools-2.jsonl + test-helper-ai.sh), Family Mode (guards.py, cli.py),
   Scam Shield words
9. tests/techguard-fakes.sh, test-techguard.sh
10. tests/test-techguard-more.sh, test-techguard-money.sh
11. tests/test-techguard-kick.sh, test-techguard-gui.sh
12. tests/test-techguard-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.
- Run bits (Claude sets them in git): bin/forgeos-techguard, bin/forgeos-techguard-gui,
  libexec/forgeos-techguard-money, libexec/forgeos-techguard-trust = 755.

## Honest limits
It can't hear the phone call: it reacts to what happens on the PC. A stranger who already has the PC password
could fight it (that is why "I set this up myself" asks for it). It protects ForgeOS only, not the Windows side.
Money sites are locked by name (the big US banks, payments, gift cards, crypto + their usual sign-in names);
a small bank or credit union can be added to money-sites.txt. Checked on the real PC at the end of the full
build: KWin screen sharing shows up in pw-dump (Zoom, a browser, AnyDesk/RustDesk), a Wine copy of
AnyDesk/UltraViewer is caught, pkexec from the user service locks the money sites without a password window,
Brave honors /etc/hosts, `keepassxc --lock` locks the open KeePassXC Flatpak, the red window shows over a
full-screen browser, Ctrl+Alt+K is free in KDE and closes a
stuck full-screen page.
