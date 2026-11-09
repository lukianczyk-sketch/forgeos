# RABBIT BLUEPRINT — Job 20: Why Is It Slow?

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (tests A-N pass, plus every other ForgeOS test).
Each step prompt gives you the EXACT file contents. Copy them exactly.
Do not research, do not "improve", do not run commands.

## What it does
One button - "Why Is It Slow?" - finds out in plain English why the PC is slow, worst problem first, each
with a one-click fix that asks first. Approved by Robert 2026-11-08.
1. **The checks** (`forgeos-slow check`, runs as the person, no password, about 15 seconds):
   hidden program (temp / hidden folder = virus trick -> Clean Sweep), busy program (processor use over the
   last second; Close for your own program; games and system parts are "normal"), memory (the kernel's
   pressure meter + free memory; the biggest app by fair share (Pss); upgrade tip under 12 GB), drive full
   (Free up space), drive failing or the PC waiting for the drive (Drive Health), heat (AMD's Tctl skipped;
   90+ yellow, 95+ red), power saver (Switch to Balanced), background jobs (update, app updates, virus scan,
   Find Anything = Pause, Clean Sweep, Steam), start-up (the userspace time only; programs that start with
   the PC), internet vs. PC (no route, weak Wi-Fi, poor router, the internet company, slow name lookups),
   restart due (14+ days on, an update waiting).
2. **Programs** are grouped by app (Flatpak cgroup / app id; bwrap wrappers never decide); desktop parts are
   never blamed or closed (name, file name, or the KDE session group). Every text is cleaned to one line.
3. **The fixes** (`forgeos-slow fix ...`, only after Yes): close PID APP (only the same app, ours, not a
   desktop part), power MODE / undo, pause find, startup-off / startup-on (the person's own Hidden=true copy
   in ~/.config/autostart), empty-trash, thumbs, unused-apps, trash FILE (only inside ~/Downloads), internet
   (Ask Your PC's restart-internet), restart (KDE asks programs to save), cleansweep, drivehealth. Logged.
4. **The slow history**: `forgeos-slow-sample.timer` (user, every 5 minutes) writes one short line to
   ~/.local/state/forgeos/slow/history.jsonl, kept 7 days. `forgeos-slow earlier [MIN]` says what was slow;
   `forgeos-slow quick` = slow for 15 minutes for the same reason (never during a game).
5. **The window** (`forgeos-slow-gui`, kdialog): red / yellow list, a Fix button per problem, Fix the safe
   ones (power mode, pause), Check again, It was slow a few minutes ago, Free up space, Choose what starts,
   a report for a family helper (Documents/Why-Is-It-Slow-report.txt).
6. **Ties in**: Forge Helper tool `why_slow` (rule before the other PC problems, look in looks2.py, window
   "slow"), the "still slow" note in the helper's watch, KRunner text, help card, test questions.

## Files
- files/system/usr/bin/forgeos-slow (check | report | earlier | quick | sample | space | startup | fix),
  files/system/usr/bin/forgeos-slow-gui, files/system/usr/libexec/forgeos-slow-screens (sourced)
- files/system/usr/lib/forgeos-slow/slowlib/: __init__ rules procs checks hot net more startup space judge
  history fixes cli (.py)
- user units forgeos-slow-sample.service + .timer; applications/forgeos-slow.desktop; help/why-is-it-slow.md
- helperlib/looks2.py (new) + edits: forgeos-setup.sh (a NEW chmod line + 1 enable line), forgeos-helper-krunner,
  helperlib rules/tools/looks/actions/checks/watch, tools-1/tools-2/seniors .jsonl, tests/test-helper-ai.sh
  (G3), .github/workflows/tests.yml
- tests/slow-fakes.sh, slow-make.py, test-slow.sh (A-E), test-slow-more.sh (F-I), test-slow-fix.sh (J1-J10),
  test-slow-space.sh (J11-J17), test-slow-history.sh (K), test-slow-gui.sh (L), test-slow-safe.sh (N),
  test-slow-files.sh (M)

## Steps (one Cline task each)
1. bin/forgeos-slow, slowlib __init__.py, rules.py
2. slowlib procs.py, checks.py
3. slowlib hot.py, net.py, more.py
4. slowlib startup.py, space.py, judge.py
5. slowlib history.py, fixes.py, cli.py
6. the window + files: bin/forgeos-slow-gui, libexec/forgeos-slow-screens, 2 units, menu entry, help card
7. edits: forgeos-setup.sh, forgeos-helper-krunner, 3 test-question files, test-helper-ai.sh
8. Forge Helper: new looks2.py + edits rules.py, tools.py, looks.py, actions.py, checks.py, watch.py
9. tests/slow-fakes.sh, slow-make.py
10. tests/test-slow.sh, test-slow-more.sh
11. tests/test-slow-fix.sh, test-slow-space.sh
12. tests/test-slow-history.sh, test-slow-gui.sh
13. tests/test-slow-safe.sh, test-slow-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.
- Run bits (Claude sets them in git): bin/forgeos-slow, bin/forgeos-slow-gui = 755.

## Honest limits
It can't make old hardware new (it says what upgrade helps). Slow internet from the provider can't be fixed
from the PC (it says so). Temperatures need the PC's sensors. The window can't schedule "restart tonight"
(Restart now or Later). ForgeOS side only. Checked on the real PC at the end of the full build:
powerprofilesctl with tuned-ppd, busctl org.kde.Shutdown logoutAndReboot, KDE app scope names, k10temp /
coretemp labels, nmcli and ping output, real start-up entries, Flatpak cgroups, kdialog checklists.
