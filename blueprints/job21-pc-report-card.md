# RABBIT BLUEPRINT — Job 21: PC Report Card

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (tests A-M pass, plus every other ForgeOS test; an
independent review found 12 issues, all fixed and tested). Each step prompt gives you the EXACT file contents.
Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
One button - "PC Report Card" - gives the whole PC a school-style grade, A to F, for each part, an overall
grade, one plain sentence each, and a "Raise this grade" button that opens the ForgeOS tool for that part.
It only reads. It never fixes anything. Nothing leaves the PC. Approved by Robert 2026-11-09.
1. **The subjects** (`forgeos-reportcard check`, runs as the person, a few seconds, all at once): Safety
   guards (Always-On Guard, Ransomware Tripwire, Fake Tech Support Guard, virus + scam list age, someone
   sharing the screen), Updates (Drivers & BIOS status + rpm-ostree image age, broken after an update), Drive
   health and Backups (one Drive Health answer; unreadable drives are not graded), Speed (Why Is It Slow?'s
   7-day history; a busy processor alone is left out because games use it on purpose), Room to work (free
   space), Undo safety net, Privacy (Privacy Report on + apps it noted this week), Hidden devices
   (GhostFinder's last sweep), Ready for trouble (Digital Will envelope + Find My PC), Battery (laptops only).
   Passwords is shown "not graded" until Job 28. A tool that does not answer = "Not checked yet" (no points lost).
2. **Grades**: points 0-100 (A 90+, B 80+, C 70+, D 60+, F); overall = average with Safety and Drive health
   counted double; one F holds the overall grade to C (79) or lower. Worst subject first.
3. **The monthly card**: user timer forgeos-reportcard-monthly (10 min after login, daily 10:00) saves one card
   a month (~/.local/state/forgeos/reportcard/cards.jsonl, 12 kept). If the overall grade went down or a new F
   appeared, Forge Helper's note says so once with the one thing that helps most (never during a game).
   `change` = "what changed since last month".
4. **The window** (`forgeos-reportcard-gui`, kdialog): overall grade big, each subject (letter + color + words),
   one button per subject (only ForgeOS's own windows), "Save a copy for my family helper (PDF)" (Documents,
   hand-written one-page PDF), "Past report cards", "Grade again".
5. **Ties in**: Forge Helper tool `report_card` (rule right before Why Is It Slow?; emergencies still win; look in
   looks2.py; window "reportcard"); will_it_run moved from tools.py to looks2.py (tools.py was full); KRunner
   text, help card, test questions.

## Files
- files/system/usr/bin/forgeos-reportcard (check | report | json | history | monthly | save [FILE]),
  files/system/usr/bin/forgeos-reportcard-gui
- files/system/usr/lib/forgeos-reportcard/cardlib/: __init__ safety drives more ready grade keep pdf cli (.py)
- user units forgeos-reportcard-monthly.service + .timer; applications/forgeos-reportcard.desktop;
  help/pc-report-card.md
- edits: forgeos-setup.sh (a NEW chmod line + 1 enable line), forgeos-helper-krunner, helperlib rules/tools/
  looks2/actions, tools-2/seniors .jsonl, tests/test-helper-ai.sh (G3), .github/workflows/tests.yml
- tests/card-fakes.sh, test-reportcard.sh (A-C), test-reportcard-drives.sh (D-E), test-reportcard-more.sh (F-I),
  test-reportcard-keep.sh (J-K), test-reportcard-gui.sh (L), test-reportcard-files.sh (M)

## Steps (one Cline task each, every prompt under ~8,000 characters)
1. bin/forgeos-reportcard, cardlib __init__.py
2. cardlib safety.py
3. cardlib drives.py, ready.py
4. cardlib more.py + the units, the menu entry, the help card
5. cardlib grade.py, cli.py
6. cardlib keep.py
7. cardlib pdf.py
8. bin/forgeos-reportcard-gui
9. edits: forgeos-setup.sh, forgeos-helper-krunner, helperlib rules/tools/looks2/actions, 2 test-question files,
   test-helper-ai.sh
10. tests/card-fakes.sh
11. tests/test-reportcard.sh
12. tests/test-reportcard-drives.sh
13. tests/test-reportcard-more.sh
14. tests/test-reportcard-keep.sh
15. tests/test-reportcard-gui.sh
16. tests/test-reportcard-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.
- Run bits (Claude sets them in git): bin/forgeos-reportcard, bin/forgeos-reportcard-gui = 755.

## Honest limits
It grades only what the ForgeOS tools already know (no new scans), so a tool never run = "Not checked yet".
Privacy is graded on the Privacy Report being on, not on which apps are "OK" (only the person can judge that).
ForgeOS side only. Checked on the real PC at the end of the full build: every tool's status as the normal
user (tripwire / techguard state files readable), upower on a laptop, xdg-user-dir, the PDF in Okular,
notify-send actions from a user timer (KillMode=process keeps the window open).
