# RABBIT BLUEPRINT — Job 24: Ask Before Connecting

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (tests A-I pass, plus every other ForgeOS test; two
independent review rounds found 14 + 8 issues, all fixed and tested). Each step prompt gives you the EXACT file
contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
The first time a program tries to use the internet, the PC asks you in plain English: "Bottles wants to use the
internet (to reach ...). Allow / Block / Other choices (Just this once, What is this?)". Your answer is remembered.
Nothing leaves the PC. Approved by Robert 2026-11-11.
1. **Engine: OpenSnitch 1.8.0** (free, GPL-3.0), from its GitHub RPM with a fixed SHA-256 (install-opensnitch.sh).
   Set up with DefaultAction deny, checksums on, its UI socket at /run/forgeos-netask/osui.sock (root only).
2. **Our root service** (forgeos-netask.service) is the "UI" OpenSnitch talks to (gRPC, ui.proto turned into Python
   at image build by python3-grpcio-tools). It decides, asks, and keeps answers as OpenSnitch rules
   (/etc/opensnitchd/rules/500-forgeos-netask-u<uid>-allow|block-<name>-<tag>.json: real file + MD5 + person).
3. **Who is asked**: ForgeOS's own /usr programs (the real file, not a copy), ForgeOS's default Flatpaks
   (trusted-apps.txt, the real installed app) and Steam games = never. A saved answer = that answer (your Block
   wins). Downloads / temp / hidden folders = red question every time. Remote-control apps = Fake Tech Support
   Guard question (RustDesk free in Family Mode). Known scam sites = blocked + one note. Scripts are known by the
   script, Windows programs by their .exe and Wine folder, typed commands are never allowed for good.
4. **The question** is started by root as you, straight into your desktop (setpriv + env -i), and the answer is the
   window's exit code: no program can answer for you. No answer in 30 s = blocked for now. In a game or away =
   one quiet list later. At most 3 questions a minute. ptrace_scope=1 (sysctl).
5. **Who Uses the Internet** window: every app Allowed / Blocked / Asks each time, Today (counts only), Something
   stopped working? (last hour), Lock down, Advanced view, on/off. Anything that lets MORE through is confirmed by
   a question the service shows (request socket, peer uid checked).
6. **Forge Helper** (helperlib/netask.py): "is something using the internet?", "why can't X connect?", "unblock X".
   **PC Report Card**: Safety notes when it is off or not running.

## Files
- files/scripts/install-opensnitch.sh (new; runs before forgeos-setup.sh), recipes/common-modules.yml (3 packages)
- files/system/usr/bin/forgeos-netask, forgeos-netask-gui; usr/libexec/forgeos-netask-service
- files/system/usr/lib/forgeos-netask/netlib/: __init__ askui cli decide dialog explain flatpak history later names
  proc requests server service store trust who
- usr/share/forgeos/netask/: ui.proto, trusted-apps.txt, rules/001-forgeos-system.json
- systemd/system/forgeos-netask.service, opensnitch.service.d/forgeos.conf, sysctl.d/60-forgeos-netask.conf,
  applications/forgeos-netask.desktop, help/ask-before-connecting.md, helperlib/netask.py
- edits: forgeos-setup.sh, common-modules.yml, helperlib rules/tools/looks2/actions, forgeos-helper-krunner,
  helper tests more.jsonl, tests/test-helper-ai.sh (G3), reportcard safety.py + forgeos-reportcard-gui, tests.yml
- tests: netask-fake-daemon.py (speaks the real protocol), netask-proc.sh, netask-fakes.sh, test-netask.sh (A),
  -kinds (B), -more (C), -answers (D), -gui (E), -safety (H), -tricks (I), -files (F), -hooks (G)

## Steps (one Cline task each, every prompt under ~7,300 characters)
1. the forgeos-netask command and library file __init__
2. library files proc and trust
3. library files flatpak and history
4. library file names
5. library file who
6. library file store
7. library file later
8. library file decide
9. library file dialog
10. library file askui
11. library file server
12. library file requests
13. the service: library files service and explain, its launcher and its systemd unit
14. library file cli
15. the window
16. OpenSnitch's protocol file
17. the app list, the system rule, the menu entry, the help card and two system settings
18. the build script
19. Forge Helper's netask file
20. the pretend OpenSnitch daemon and pretend programs for the tests
21. the pretend PC for the tests
22-29. tests A, B, C, D, E, H, I, F
30. edits in setup, the recipe, rules, tools, looks2 and actions
31. edits in KRunner, more.jsonl, test-helper-ai.sh, the Report Card and the CI step
32. tests G

## Rules
- Spaces only, no tabs. Every file ends with exactly one newline. Copy every backslash exactly once.
- Run bits (755): bin/forgeos-netask, bin/forgeos-netask-gui, libexec/forgeos-netask-service (Claude sets them).
- Version when done: v0.29.0.
