# RABBIT BLUEPRINT — Job 23: Plain-English Errors

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (tests A-G pass, plus every other ForgeOS test; an
independent review found 24 issues, all fixed and tested). Each step prompt gives you the EXACT file contents.
Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
When something goes wrong, the PC says what happened in plain English. Every card answers: What happened?
Is it serious? (not serious / needs a look / serious - words, never color alone) What do I do? - with one
Fix it button. Nothing leaves the PC. Approved by Robert 2026-11-10.
1. **Pop-ups**: the watcher (forgeos-errors-watch.service, your own session) listens with `busctl --user
   monitor --json=short` to the desktop's Notify calls. Only errors the library or the scam check knows get a
   "What does this mean?" pop-up; other pop-ups are never written down, and only the matched words are kept.
   ForgeOS's own tools' pop-ups are skipped.
2. **Crashes**: every 3 minutes `coredumpctl list --json=short --since=@T` (yours only) -> "Brave closed by
   itself" + Open it again; 3 times in a week = needs a look. **System log**: `journalctl -b -p warning -o json`,
   only library entries marked `log: yes`.
3. **Meta+Shift+E** (Explain This Error): an error you just copied (known ones only, never a password copied
   from a password manager), else the screen (Show Me How's quiet screenshot + Tesseract).
4. **Library**: /usr/share/forgeos/errors/library/01..16-*.txt = 141 errors (id match log general level title say
   do fix show example); longest match wins, catch-alls only when nothing else fits; `forgeos-errors check`
   proves every example finds its own entry.
5. **Scam check first**: a fake "virus / call this number / pay with gift cards" message = red "This is a scam,
   not a real error". Every card says: real errors never show a phone number and never ask for money.
6. **Fixes only from a checked list** (fixes.py): Ask Your PC fixes, open a ForgeOS window or a System Settings
   page, Show Me How, open the crashed program again, clear your own stuck print jobs, close the browsers on a
   scary page, call my helper. Nothing deletes files. Each needs your click. Launches go through
   `systemd-run --user --scope`.
7. **The private AI** explains unknown errors only (fixed answer shape, fix picked from the list or none,
   commands / links / phone numbers cut out, not sure = says so).
8. **What Went Wrong**: 30 days of history on this PC (one line per error with a count, file lock, "fixed"
   marks); at most one pop-up every 10 minutes, none in a game (GameMode, gamescope, Steam), serious ones always.
9. **Forge Helper**: "what does this error mean", codes like 0x80070005, ERR_..., missing .dll -> explain_error.

## Files
- files/system/usr/bin/forgeos-errors (explain TEXT|- | this | screen | copied | card KEY | recent [DAYS] |
  fix FIX --yes | fixed KEY | check | watch | tick | pop KEY | notice APP TITLE TEXT), forgeos-errors-gui
- files/system/usr/lib/forgeos-errors/errlib/: __init__ ai cli explain fixes history library scam system watch
- files/system/usr/share/forgeos/errors/library/01..16-*.txt (16 files)
- systemd/user/forgeos-errors-watch.service; applications/forgeos-errors.desktop (Meta+Shift+E) +
  forgeos-errors-history.desktop (What Went Wrong); help/plain-english-errors.md
- edits: forgeos-setup.sh (a NEW chmod line + enable the watcher for everyone), helperlib rules/tools/looks2/
  actions, forgeos-helper-krunner, helper tests more.jsonl, tests/test-helper-ai.sh (G3), .github/workflows/tests.yml
- tests/errors-fakes.sh, errors-monitor-sample.txt, test-errors.sh (A), -ai (B), -watch (C), -fix (D), -gui (E),
  -dbus (F), -files (G)

## Steps (one Cline task each, every prompt under ~7,000 characters)
1. the forgeos-errors command and library file __init__
2. library file library
3. library file fixes
4. library files scam and explain
5. library file history, the watcher service and the two menu entries
6. library file system and the help card
7. library file ai
8. library file cli
9. library file watch
10. the window
11. error library files 01
12. error library files 02
13. error library files 03
14. error library files 04, 08
15. error library files 05
16. error library files 06, 15
17. error library files 07
18. error library files 09
19. error library files 10
20. error library files 11
21. error library files 12
22. error library files 13
23. error library files 14
24. error library files 16
25. the pretend desktop for the tests
26. tests A
27. tests B
28. tests C
29. tests D
30. tests E
31. tests F
32. edits in setup, rules, tools, looks2 and actions
33. edits in KRunner, more.jsonl, test-helper-ai.sh and the CI step
34. tests G

## Rules
- Spaces only, no tabs. Every file ends with exactly one newline. Copy every backslash exactly once.
- Run bits (755): bin/forgeos-errors, bin/forgeos-errors-gui (Claude sets them). Version when done: v0.28.0.
