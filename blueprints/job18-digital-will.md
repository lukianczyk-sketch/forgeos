# RABBIT BLUEPRINT — Job 18: Digital Will

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (tests A-L pass, plus every other ForgeOS test).
Each step prompt gives you the EXACT file contents. Copy them exactly.
Do not research, do not "improve", do not run commands.

## What it does
If something happens to you, the people you picked can get into this PC, your accounts and your photos.
Approved by Robert 2026-11-07.
1. **Step 1 - the answers** (`forgeos-digitalwill-gui`, kdialog): up to 3 trusted people, accounts from a
   pick-list of 23 (+ your own) and what should happen to each (keep / close / give to a person / memorial
   page), the KeePassXC password safe file, folders to keep, a letter to each person, a note. Saved in
   ~/.local/share/forgeos/will/draft.json (600) - NEVER a password.
2. **Step 2 - the Emergency Envelope** (`forgeos-digitalwill make`): a new 10-word opening code (EFF Short
   Wordlist, 1,295 words, Python `secrets`), one 7-Zip file (AES-256, file names hidden: `7z a -t7z -mhe=on -p`,
   code on stdin) in Documents/ForgeOS Emergency Envelope and on a USB stick (lsblk: removable, under
   /run/media/<you>). Inside: "Open me first.html" (sign-in name + password, PC unlock code, password safe +
   its master password, other passwords, accounts table, note, letters), Letters/, Password safe/, Kept
   folders/. The pages are put together in memory ($XDG_RUNTIME_DIR, tmpfs); 7-Zip follows links to the
   safe and the folders, so nothing unlocked is written to the drive. Tested right after (`7z t`); older
   envelopes in those folders are removed. Next to it: "Letter to my family.html" (no secrets: who has the
   code, how to open it with free 7-Zip / Keka). Code cards page in memory, opened to print, then deleted.
   The sign-in password is checked with the PC's own checker (unix_chkpwd) before anything is made.
3. **Two-key lock**: the code is split into Half A (a trusted person) and Half B (a person or a place like
   "my lawyer"); 5 words each, one half alone can't be guessed.
4. **PC unlock for family**: an 8-word code added to the drive's lock (LUKS) by the root helper
   (`pkexec /usr/libexec/forgeos-digitalwill-unlock add DEV`, polkit asks for the PC password). The first
   time it needs the disk password; ForgeOS keeps the current code root-only in /var/lib/forgeos-digitalwill,
   so a new envelope swaps the code (old one removed) without asking again. The disk password never changes.
5. **Step 3 - company checklist**: Google Inactive Account Manager, Apple Legacy Contact, Facebook legacy
   contact, Microsoft (no such feature), bank "payable on death" - opens each page, ticks it off.
6. **Reminders** (user timer, daily): envelope 6 months old (then monthly), password safe changed after the
   envelope, started but no envelope after a week (then every 2 weeks). Note with "Open Digital Will".
7. **Test my envelope**: type the code (or both halves), it opens and checks every file.
8. **Ties in**: Forge Helper tool `digital_will` (rule first) + help card; 7zip in the image.

## Files
- files/system/usr/bin/forgeos-digitalwill (status | report | catalog | person | account | safe | folders |
  letter | letter-show | note | note-show | legacy | legacy-done | legacy-undo | legacy-open | usb |
  check-login | test | make | forget-cards | tick | root-unlock add DEV), files/system/usr/bin/forgeos-digitalwill-gui
- files/system/usr/lib/forgeos-digitalwill/willlib/: __init__ words draft pages cards pack unlock remind
  report actions cli (.py)
- files/system/usr/libexec/forgeos-digitalwill-unlock (root helper) + the window's screens (sourced):
  forgeos-digitalwill-answers, -accounts, -envelope, -finish
- polkit org.forgeos.digitalwill.policy; user units forgeos-digitalwill-remind.service + .timer;
  applications/forgeos-digitalwill.desktop; helper/help/digital-will.md
- files/system/usr/share/forgeos/digitalwill/: words-1.txt, words-2.txt, accounts.txt, legacy.txt
- edits: forgeos-setup.sh (a NEW chmod line + 1 enable line), recipes/common-modules.yml (7zip),
  helperlib rules/tools/actions/looks, tools-2.jsonl, tests/test-helper-ai.sh (G3), .github/workflows/tests.yml
- tests/digitalwill-fakes.sh, test-digitalwill.sh (A-C), test-digitalwill-make.sh (D-E),
  test-digitalwill-more.sh (E5-F), test-digitalwill-unlock.sh (G-H, real cryptsetup with sudo),
  test-digitalwill-remind.sh (I), test-digitalwill-gui.sh (J-K), test-digitalwill-files.sh (L)

## Steps (one Cline task each)
1. bin/forgeos-digitalwill, willlib __init__.py, words.py, words-1.txt
2. words-2.txt, accounts.txt, legacy.txt, willlib draft.py
3. willlib pages.py, cards.py, pack.py
4. willlib unlock.py, remind.py, report.py
5. willlib actions.py, cli.py
6. root helper, polkit, 2 user units, menu entry, help card, the window (bin/forgeos-digitalwill-gui)
7. screens: forgeos-digitalwill-answers, forgeos-digitalwill-accounts
8. screens: forgeos-digitalwill-envelope, forgeos-digitalwill-finish
9. edits: forgeos-setup.sh, common-modules.yml, tools-2.jsonl, test-helper-ai.sh
10. edits: Forge Helper rules.py, tools.py, actions.py, looks.py
11. tests/digitalwill-fakes.sh, test-digitalwill.sh
12. tests/test-digitalwill-make.sh, test-digitalwill-more.sh
13. tests/test-digitalwill-unlock.sh, test-digitalwill-remind.sh
14. tests/test-digitalwill-gui.sh, test-digitalwill-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.
- Run bits (Claude sets them in git): bin/forgeos-digitalwill, bin/forgeos-digitalwill-gui,
  libexec/forgeos-digitalwill-unlock = 755.

## Honest limits
It is not a legal will (the letter says so). If both the USB stick and the code card(s) are lost, nobody can
open the envelope - by design. An envelope left on a USB stick that was not plugged in for a new envelope
keeps the old (stale) passwords; the window says to put the stick in. Brave's saved passwords open only after
signing in. Protects ForgeOS only, not the Windows side. Checked on the real PC at the end of the full build:
Fedora's 7zip reads the code from stdin (`7z a -p`, `7z t`), unix_chkpwd checks the sign-in password from the
user's own session, `cryptsetup luksAddKey` through pkexec on the real LUKS2 drive (Argon2 slot) and the new
code works at the start-up prompt, Ark/7-Zip/Keka open the envelope, kdialog --checklist --separate-output,
the code card page prints from Brave, the reminder note's button.
