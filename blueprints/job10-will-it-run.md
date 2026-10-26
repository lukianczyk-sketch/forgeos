# RABBIT BLUEPRINT — Job 10: Will It Run?

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype. Each step prompt gives you the EXACT file
contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
"Will this program run on my PC?" Pick a file (setup.exe, an .msi, an .apk, an AppImage) or type
a program's name, and ForgeOS says Yes / Maybe / No in plain English plus the best FREE way to run
it, with one button to do it. Menu entry "Will It Run?" + Dolphin right-click "Will it run on ForgeOS?".
1. **Looks inside, never runs it**: reads the file's first bytes and the Windows program header
   (32/64-bit, ARM, driver, library, .NET), spots installers (Inno Setup, NSIS, InstallShield) and
   files that lie about what they are (a ".exe" that is not a program = "Do not open it").
2. **Anti-cheat**: finds anti-cheat files next to a game (and names inside it). Kernel anti-cheat
   (Vanguard, FACEIT, EA anticheat, nProtect GameGuard, XIGNCODE3, Anti-Cheat Expert) = No.
   Easy Anti-Cheat / BattlEye = check the free "Are We Anti-Cheat Yet?" list (MIT license,
   downloaded daily; a copy from build day is kept in /usr). Supported/Running = Yes,
   Planned = Maybe, Broken/Denied = No.
3. **Known programs**: 59 well-known Windows programs (Office, Photoshop, Spotify, Teams, Steam,
   Epic, Battle.net, Roblox, Minecraft, antivirus...) with the answer: already on ForgeOS, own
   Linux version on Flathub, free swap, game launcher (Steam / Heroic / Lutris), website, or won't
   run. Every Flathub app ID was checked on 2026-10-26.
4. **The way to run it** (only after the user clicks the button): Bottles (sees only the program's
   own folder, or only the file when it sits in Downloads/Desktop/home), install from Flathub in a
   Konsole window (only IDs on the checked lists), open an installed app, Waydroid (sets it up
   first with `ujust setup-waydroid` if needed, starts it, `waydroid app install`), Gear Lever for
   AppImages, Steam. Old DOS programs = DOSBox Staging.
5. **Safety check first (added 2026-10-26, Robert asked)**: before ANY answer for a file: virus scan
   with ClamAV (already in ForgeOS; found = No + Clean Sweep), fake double endings (invoice.pdf.exe,
   "song.mp3      .scr") = No, the website the file came from (Brave/Chrome save it in the file's
   user.xdg.origin.url attribute) is shown, and if it is on the Scam Shield lists = No; cracked or
   pirated names (crack, keygen, activator, KMS, "free robux") get a warning.
6. **Names it does not know**: the private AI (local Ollama) gives a best guess, clearly marked
   "it can be wrong". No AI = honest "not on my list" with tips. Nothing leaves the computer.

## How (key facts — all verified by Claude on 2026-10-26)
- Bazzite 44 removed QEMU/libvirt from the image, so a Windows VM is only suggested (GNOME Boxes
  Flatpak, needs your own Windows license) — never set up by us.
- Bottles 67.4 (Flatpak, no home access): `flatpak run --filesystem=DIR com.usebottles.bottles -e FILE`
  or `flatpak run --file-forwarding com.usebottles.bottles -e @@ FILE @@` opens its bottle picker.
- Waydroid: set up when /var/lib/waydroid/waydroid.cfg exists; `waydroid status` prints
  "Session: RUNNING"; `waydroid app install` needs a running session.
- Gear Lever opens a file passed to it (`--file-forwarding it.mijorus.gearlever @@ FILE @@`).
- Anti-cheat list: raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/HEAD/games.json
  (1167 games), stored as name|status|anti-cheats in /var/lib/forgeos-willitrun/anticheat.list.
- AI: same as Scam Shield / Ask Your PC (ai-model file, /api/chat, temperature 0, JSON answer).
- Pipelines never use `grep -q` / early `exit` on a pipe (pipefail made that fail at random).

## Files
- files/system/usr/libexec/forgeos-willitrun-lib — file type + Windows header reader (sourced)
- files/system/usr/libexec/forgeos-willitrun-match — anti-cheat check + list lookups (sourced)
- files/system/usr/share/forgeos/willitrun/1-games.txt, 2-office-media.txt, 3-internet-tools.txt
- files/system/usr/libexec/forgeos-willitrun-answers, -check, -windows, -open, -safety (sourced)
- files/system/usr/bin/forgeos-willitrun — command: check [--no-ai] FILE-OR-NAME / open WAY [ARG]
- files/system/usr/libexec/forgeos-willitrun-update + forgeos-willitrun-update.service/.timer
- files/system/usr/bin/forgeos-willitrun-gui — kdialog window (+ --file FILE)
- files/system/usr/share/applications/forgeos-willitrun.desktop, kio/servicemenus/forgeos-willitrun.desktop
- files/scripts/forgeos-setup.sh — chmod, enable the timer, build-day copy of the list
- tests/willitrun-fakes.sh + test-willitrun.sh (A-D), -games.sh (E-H), -open.sh (I-L), -extras.sh (M-P),
  -safety.sh (Q)
- .github/workflows/tests.yml — new step "Run Will It Run? tests (fake tools)"

## Steps (Cline does one step per prompt, then stops)
1. Blueprint + PROGRESS + lib + match + the 3 list files.
2. The command + answers + check + windows + open + safety + chmod for the command (+ this blueprint again).
3. The list download + timer + window + menu entries + setup.
4. Fakes + tests A-H.
5. Tests I-Q + CI step.
After each step Claude reviews (diff against the prototype), runs the tests, commits and pushes.

## Rules for the Rabbit Team
- Copy file contents EXACTLY. Do NOT double any backslash. Do NOT change quotes.
- Use LF line endings. Keep every file under 6000 characters (they already are).
- Do not run commands, do not research, do not verify. Stop after each step.
