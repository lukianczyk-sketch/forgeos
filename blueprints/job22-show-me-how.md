# RABBIT BLUEPRINT — Job 22: Show Me How

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (tests A-L pass, plus every other ForgeOS test; an
independent review found 15 issues, all fixed and tested). Each step prompt gives you the EXACT file contents.
Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
Ask "how do I print?" and the PC SHOWS you: a glowing yellow ring and arrow on the screen over the thing to
click, with one short sentence. You click it yourself; the arrow moves on. It only points - it never clicks,
types or changes anything. Nothing leaves the PC. Approved by Robert 2026-11-09.
1. **Start it**: menu "Show Me How" / Meta+Shift+H (a list of 24 guides, most used first + "Something else"),
   Forge Helper ("show me how to ..." rule, and a "Show me on the screen" button on help answers), KRunner.
2. **Open the right place first** (guide `open:` line: a System Settings page, an app, a ForgeOS window).
3. **Read the screen**: every 2 s a quiet Spectacle screenshot (`-b -n -f -o`, in $XDG_RUNTIME_DIR, 0700, deleted
   at once) read by Tesseract (TSV = each word + its box). Places are parts of the screen (0-1). OCR look-alike
   letters count (Caneel = Cancel). Our own panel/label text never counts.
4. **Draw**: ONE fixed KWin QML file (/usr/share/forgeos/showme/overlay.qml, loaded with busctl
   loadDeclarativeScript ss + start) asks our D-Bus service org.forgeos.ShowMe /ShowMe State(s) every 250 ms
   (DBusCall) and draws ring + arrow + sentence; clicks go through (outputOnly). It keeps the kdialog step panel
   (Next / Back / Stop, Esc = Stop) on top in the corner away from the arrow.
5. **Move on**: by itself when the next step's words show up in a NEW place, or the clicked words are gone;
   Back / Next always work. Can't see it (after 10 s) = "I can't see X" + the steps in writing + Try again /
   Show me where to start. Never points at a guess.
6. **Safety**: stops if someone can see or control the screen (Fake Tech Support Guard), after 2 minutes with no
   progress, after 5 errors in a row. Refuses scam / stranger / emergency questions (Forge Helper's rules).
   No guide = the private AI may only pick ONE word that is really on the screen (enum), never money,
   password, download, install, allow or remote-control words; not sure = it says so. Family Mode = bigger.

## Files
- files/system/usr/bin/forgeos-showme (list | find | guide NAME | ask Q | check | written; --no-draw),
  files/system/usr/bin/forgeos-showme-gui
- files/system/usr/lib/forgeos-showme/showlib/: __init__ guides screen walk ai cli session show (.py)
- files/system/usr/share/forgeos/showme/overlay.qml + guides/*.txt (24; NAME = the help card it shows)
- applications/forgeos-showme.desktop; help/show-me-how.md; helperlib/showme.py (new)
- edits: forgeos-setup.sh (a NEW chmod line), forgeos-helper-gui, forgeos-helper-krunner, helperlib rules/tools/
  looks2/actions/talk, tools-2/seniors .jsonl, tests/test-helper-ai.sh (G3), .github/workflows/tests.yml
- tests/showme-make.py, showme-fakes.sh, test-showme.sh (A-C), -walk (D), -steps (E-F), -ai (G), -dbus (H),
  -gui (I-J), -real (K), -files (L)

## Steps (one Cline task each, every prompt under ~8,000 characters)
1. bin/forgeos-showme, showlib __init__.py
2. showlib guides.py
3. showlib screen.py
4. showlib walk.py
5. showlib ai.py, the menu entry, the help card
6. showlib cli.py
7. showlib session.py
8. showlib show.py
9. overlay.qml
10. guides 1-12
11. guides 13-24
12. bin/forgeos-showme-gui, helperlib showme.py
13. edits: setup, helper window, KRunner, rules, tools, looks2
14. edits: actions, talk, two test-question files, test-helper-ai.sh
15. tests/showme-make.py, tests/showme-fakes.sh
16. tests/test-showme.sh (A-C)
17. tests/test-showme-walk.sh (D)
18. tests/test-showme-steps.sh (E-F)
19. tests/test-showme-ai.sh (G)
20. tests/test-showme-dbus.sh (H)
21. tests/test-showme-gui.sh (I-J)
22. tests/test-showme-real.sh (K)
23. tests/test-showme-files.sh (L) + the CI step

## Rules
- Spaces only, no tabs. Every file ends with exactly one newline. Copy every backslash exactly once.
- Run bits (755): bin/forgeos-showme, bin/forgeos-showme-gui (Claude sets them). Version when done: v0.27.0.
