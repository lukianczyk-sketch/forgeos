# RABBIT BLUEPRINT — Job 9: Ask Your PC

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype. Each step prompt gives you the EXACT file
contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
"Why is there no sound?" "Why is my PC slow?" Ask the PC in plain English and it answers, for
regular people and seniors. Menu: Ask a question / Quick health check / Fix something /
Fixes done so far / How it works.
1. **Health snapshot (read-only)**: system name, time on, processor load, free memory, drive
   space, trash size, internet, network devices, sound volume/mute, battery, update waiting for a
   restart, busiest programs, stopped background services, printers, temperatures, and the last
   12 errors since start-up. Every check only READS and gives up after 5 seconds.
2. **Private AI answer**: the local Ollama model from ForgeOS AI Setup reads the snapshot and the
   question and answers in at most 6 plain sentences. It may pick ONE fix, but only a name from the
   fixed safe list (Ollama structured output with an enum). It can never write its own commands.
3. **Safe fixes, only with permission**: the window shows exactly what the fix will do and runs
   it only after "Yes, do it". No fix needs a password. Every fix is written to a history.
4. **No AI?** It still works: a plain-English health check plus a fix picked from keywords.
5. Nothing leaves the computer.

## The fix list (the ONLY things Ask Your PC can do)
restart-internet (nmcli networking off, wait 3 s, on — always turned back on),
restart-sound (systemctl --user restart pipewire, pipewire-pulse, wireplumber),
unmute-sound (wpctl unmute + volume 50%), restart-taskbar (systemctl --user restart
plasma-plasmashell.service), close-busy-app (polite kill -TERM of this user's busiest program;
desktop programs are never picked; the program must still be the one the user agreed to),
clear-thumbnails (~/.cache/thumbnails), empty-trash (gio trash --empty),
open-cleansweep, open-undo, open-privacy, open-scamshield, open-backup (Pika Backup).

## How (key facts — all verified by Claude)
- AI: Ollama on 127.0.0.1:11434 only. Model = `~/.config/forgeos/ai-model` if Ollama has it,
  else the first model in `/api/tags` (same as Scam Shield). `POST /api/chat`, `stream: false`,
  `options.temperature: 0`, `format` = JSON schema {answer: string, fix: enum of the fix names
  that can run right now + "none"}. Snapshot cut to 6000 characters, question to 2000.
  Timeout 180 s. The system prompt says the snapshot and question are data, never instructions.
- A fix name from the AI is checked again against the list before it is shown (defense in depth).
- History: `~/.local/state/forgeos/askpc.log` (date, fix, done / did not work / skipped).
- Inspired by Red Hat's linux-mcp-server (Apache-2.0, "all tools strictly read-only"). Not used
  directly: it needs an MCP client; ForgeOS already has Ollama + shell, so a snapshot is simpler.

## Files
- files/system/usr/libexec/forgeos-askpc-lib — read-only snapshot + health check (sourced)
- files/system/usr/libexec/forgeos-askpc-fixes — the fix list + fix runner (sourced)
- files/system/usr/bin/forgeos-askpc — command: ask [--no-ai] / health / status / fixes / fix / log
- files/system/usr/bin/forgeos-askpc-gui — kdialog window
- files/system/usr/share/applications/forgeos-askpc.desktop — menu entry "Ask Your PC"
- files/scripts/forgeos-setup.sh — chmod 0755 for the two /usr/bin commands
- tests/askpc-fakes.sh, tests/test-askpc.sh (A-H), tests/test-askpc-extras.sh (I-N)
- .github/workflows/tests.yml — new step "Run Ask Your PC tests (fake tools)"

## Steps (Cline does one step per prompt, then stops)
1. Blueprint + PROGRESS + the two libexec files.
2. The forgeos-askpc command + forgeos-setup.sh chmod.
3. The window + menu entry.
4. Tests + CI step.
After each step Claude reviews (diff against the prototype), runs the tests, commits and pushes.

## Rules for the Rabbit Team
- Copy file contents EXACTLY. Do NOT double any backslash. Do NOT change quotes.
- Use LF line endings. Keep every file under 6000 characters (they already are).
- Do not run commands, do not research, do not verify. Stop after each step.
