# RABBIT BLUEPRINT — Job 11: Find Anything

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype. Each step prompt gives you the EXACT file
contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
"Where is that file?" Type what you are looking for in plain English ("my 2023 tax papers",
"the photo of my driver's license") and ForgeOS finds it, even when the words are only INSIDE the
file: text files, PDFs, Word/Excel/PowerPoint and LibreOffice files, and printed text in photos
and scanned papers (OCR). Menu entry "Find Anything". Nothing ever leaves the PC.
1. **Search list**: a private SQLite file in ~/.local/share/forgeos/find (folder 0700, file 0600).
   It holds each file's name, its two folder names and up to 200 KB of its words.
2. **Reading files** (findlib/extract.py): text (first 200 KB), PDFs with `pdftotext` (first 50
   pages); a scanned PDF (under 20 letters) gets its first 3 pages drawn with `pdftoppm` and read
   with `tesseract`; photos 8 KB - 30 MB read with `tesseract` (English); Office files are zip
   files of XML (read with Python's zipfile, tags removed). Other files (videos, music...) and
   files over 50 MB are found by name only. A missing tool = found by name + a note in `status`.
3. **Keeping it up to date** (findlib/walk.py): goes through the home folder; skips hidden
   folders/files, .snapshots, node_modules, __pycache__, site-packages, Games, SteamLibrary and
   anything in ~/.config/forgeos/find-skip.txt; never follows links; max 50000 files. Only new
   and changed files (other time or size) are read again; deleted files are dropped. A lock
   file stops two updates at once. A user timer runs it 10 minutes after login, then every hour,
   at the lowest priority, never on battery.
4. **Searching** (findlib/store.py): SQLite FTS5 with word stems ("returns" finds "return"),
   ranked by bm25 with a hit in the name worth 5 times a hit in the words. If FTS5 is missing,
   a simple LIKE search with the same ranking is used (FORGEOS_FIND_NO_FTS=1 forces it).
   All words must match first; if no file has them all, files with some of them come back.
5. **Plain-English questions** (findlib/ask.py): the private AI (local Ollama, the model from
   AI Setup) turns the question into words + kind (photo, pdf...) + dates, as JSON, temperature
   0, never through a proxy. The question is only data. AI words are cleaned to letters and
   digits before the search. No AI, a broken answer, or no results = simple word search: small
   words dropped, "photo/picture/scan" = photos only, a year 1990-2099 = files changed that year
   first (then any year).
6. **Window** (forgeos-find-gui, kdialog): question box -> list of files found (name, folder,
   date, the words around the hit) -> "Open it" (xdg-open) or "Show it in its folder"
   (dolphin --select). Empty list = offer to build it now.

## Key facts (checked by Claude on 2026-10-26)
- Bazzite KDE keeps KDE's own file search (Baloo) as it is: no OCR, no plain-English questions.
  Find Anything is separate and does not change it.
- Fedora 44 packages (all free): `tesseract` 5.5 (Apache-2.0) needs `tesseract-langpack-eng`
  for English; `poppler-utils` has pdftotext + pdftoppm; `python3` is in the base image.
- Python standard library only (sqlite3, zipfile, json, urllib, subprocess). No pip.
- /usr is read-only, so the program never writes Python cache files (sys.dont_write_bytecode).

## Files
- files/system/usr/lib/forgeos-find/findlib/__init__.py, words.py, extract.py, store.py, walk.py, ask.py
- files/system/usr/bin/forgeos-find — Python command: index [--full] [--quiet], search [--kind K]
  [--limit N] WORDS, ask [--no-ai] QUESTION, status, forget PATH.
  Exit 0 found / 1 nothing found / 2 search list empty / 3 wrong use.
  Each file found also prints `RESULT<tab>path<tab>kind<tab>YYYY-MM-DD<tab>words` for the window.
- files/system/usr/bin/forgeos-find-gui — kdialog window
- files/system/usr/lib/systemd/user/forgeos-find-index.service + .timer
- files/system/usr/share/applications/forgeos-find.desktop
- files/scripts/forgeos-setup.sh — chmod both commands, `systemctl --global enable forgeos-find-index.timer`
- recipes/common-modules.yml — dnf: tesseract, tesseract-langpack-eng, poppler-utils, python3
- tests/find-fakes.sh, tests/find-fake-ollama.py, tests/test-find.sh (A-H),
  tests/test-find-ask.sh (I-N), tests/test-find-extras.sh (O-T), tests/test-find-real.sh (U, real tools)
- .github/workflows/tests.yml — shellcheck only shell scripts; 2 new test steps

## Steps (one Cline task each)
1. findlib/__init__.py, words.py, extract.py, store.py
2. findlib/walk.py, ask.py, bin/forgeos-find + tests.yml shellcheck filter (Python is not shell)
3. Window, menu entry, user service + timer, forgeos-setup.sh, common-modules.yml
4. tests/find-fakes.sh, tests/find-fake-ollama.py, tests/test-find.sh
5. tests/test-find-ask.sh, tests/test-find-extras.sh, tests/test-find-real.sh + 2 CI steps

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.

## Honest limits
OCR reads printed English text (handwriting poorly). Scanned PDFs: first 3 pages. .heic photos
are found by name only. The first search list of a big home folder can take a long time (it runs
quietly in the background, then hourly). The private AI only helps pick words; it never sees the files.
