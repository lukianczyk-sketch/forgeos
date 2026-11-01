# RABBIT BLUEPRINT — Job 13c: Forge Helper

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype. Each step prompt gives you the EXACT file
contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
One private AI helper for the whole PC. Press Meta+H (or menu "Forge Helper", or press Meta and type
"help ..." / a question ending in "?"). Type a question in your own words:
1. **Router** — quick rules (no AI, instant) pick one tool; if no rule fits, the QUICK model
   (gemma4:e2b when downloaded) picks ONE tool from a fixed list with a JSON schema (enum). The list is
   in code, so text in a question, email or web page can never invent a command.
2. **Tools** (look only): Scam Shield, Ask Your PC (+ its 12 safe fixes), Find Anything, Will It Run?,
   GhostFinder, Always-On Guard, Undo Button, Privacy Report, Clean Sweep, Family Mode (text size,
   Call for help), Panic Button, the help library, or a short chat answer.
3. **Actions** — anything that CHANGES the PC is only a button. The window asks "Yes, do it" first,
   then runs `forgeos-helper run ACTION ARG --yes`, which checks the action and argument again
   (fix ids are read from Ask Your PC's own list; files only inside the home folder; downloads only
   from candidates.txt).
4. **Honest** — Scam Shield gets the message exactly as typed and its verdict is shown as it is (never
   softened). Help answers come only from the help cards (the AI must name the card it used). Phone
   numbers and web links the AI writes are removed unless they came from the cards, the question or the
   user's own notes. Not sure = "I'm not sure, so I won't guess".
5. **Help library** — 67 short fact cards (/usr/share/forgeos/helper/help/*.md), word-scored search.
6. **Tested like a product** — 302 test questions (/usr/share/forgeos/helper/tests/*.jsonl);
   `forgeos-helper selftest` prints a score (rules only: 92.7%). The weekly `forgeos-helper models`
   scores every downloaded model and switches only to a HIGHER score; better free models are only
   SUGGESTED (the window asks once), never downloaded without Yes.
7. **Speaks up first** — user timer every 15 min: drive over 90% full, failed update, Guard caught
   something, Ask Your PC health problem, a program hogging the PC 10+ min, backup older than 14 days.
   One notification with [fix] [Not now]; max 3 a day; same topic max once a day; "Not now" = 3 days;
   never while a game/video stops the screen saver or gamescope runs; everything logged.
8. **Fast** — the quick model warms up 45 s after login (keep_alive 30 min).
9. **Learns privately** — thumbs up/down (~/.local/share/forgeos/helper/feedback.jsonl; thumbs-down
   questions become the user's own tests), "remember that..." (~/.config/forgeos/helper/memory.json,
   never passwords/PINs/card numbers), "Forget everything". Nothing leaves the PC.

## Files
- files/system/usr/lib/forgeos-helper/helperlib/: __init__.py, ai.py, rulelist.py, rules.py, actions.py,
  tools.py, looks.py, helpdocs.py, talk.py, router.py, memory.py, checks.py, watch.py, selftest.py, cli.py
- files/system/usr/bin/forgeos-helper (ask | run | remember | memory | forget | feedback | selftest |
  models | brains | watch-tick | warm | tools | help-search), files/system/usr/bin/forgeos-helper-gui
- files/system/usr/libexec/forgeos-helper-krunner (KRunner D-Bus runner org.kde.krunner1)
- files/system/usr/share/applications/forgeos-helper.desktop (Meta+H),
  usr/share/krunner/dbusplugins/forgeos-helper.desktop, usr/share/dbus-1/services/org.forgeos.helper.service
- files/system/usr/lib/systemd/user/forgeos-helper-watch.{service,timer}, forgeos-helper-warm.service,
  forgeos-helper-models.{service,timer}
- files/system/usr/share/forgeos/helper/candidates.txt, help/*.md (67), tests/*.jsonl (7 files)
- files/scripts/forgeos-setup.sh (chmod + enable), recipes/common-modules.yml (+ python3-gobject-base)
- tests/helper-fakes.sh, helper-fake-ollama.py, helper-last.py, helper-watch-run.py,
  helper-check-tests.py, helper-ai-map.json, test-helper.sh (A-F), test-helper-ai.sh (G-K),
  test-helper-brains.sh (L), test-helper-do.sh (M-P), test-helper-watch.sh (Q-T),
  test-helper-gui.sh (U-W), test-helper-krunner.sh (X), test-helper-files.sh (Y-Z) + 1 CI step

## Steps (one Cline task each)
1. helperlib __init__.py, ai.py, rulelist.py, rules.py, actions.py
2. helperlib tools.py, looks.py, helpdocs.py, talk.py, router.py
3. helperlib memory.py, checks.py, watch.py, selftest.py, cli.py + bin/forgeos-helper
4. window, KDE search runner, menu entry, runner + D-Bus files, 5 user units, candidates.txt,
   forgeos-setup.sh, common-modules.yml
5. help cards (first half)
6. help cards (second half)
7. test questions (7 .jsonl files)
8. tests: fakes + helpers + test-helper.sh
9. tests: test-helper-ai.sh, test-helper-brains.sh, test-helper-do.sh, test-helper-watch.sh
10. tests: test-helper-gui.sh, test-helper-krunner.sh, test-helper-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.

## Honest limits
Voice (talking out loud) is Job 30. The quick rules answer instantly but only for wording they know;
the rest needs the private AI (ForgeOS AI Setup). Tool results are shown in the tools' own plain words
(no AI rewrite, so nothing can be softened). Bigger-text needs Family Mode (it offers to turn it on).
The backup check reads Pika Backup's files (to verify on a real machine).
