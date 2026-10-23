# RABBIT BLUEPRINT — ForgeOS Job 4: "Cool Stuff"

**For:** Rabbit Team (Cline in VS Code). **Reviewer:** Claude.
**Repo:** `lukianczyk-sketch/forgeos` (BlueBuild image, base `ghcr.io/ublue-os/bazzite:stable`, KDE).
Job 1 (`v0.2.0`) and Job 2 (`v0.3.0`) are finished. Their blueprints and progress logs are in `blueprints/` — do not edit them.
(Job 3 "Clean Sweep" is planned for later; this job comes first.)

## Rules (read every time)
1. Do **ONE step only**, then stop. Write what you did in `PROGRESS.md` (format at the bottom) and wait for Claude's OK before the next step.
2. **Free only.** No paid tools, services, keys or accounts.
3. Only change the files the step names. Never edit `cosign.pub`, `blueprints/`, or anything under `files/system/usr/bin/forgeos-cleansweep*`.
4. Bash scripts start with `#!/usr/bin/env bash` and `set -euo pipefail`, use LF line endings (not CRLF), and must pass `shellcheck -S warning`.
5. Never claim "tested" or "passed" unless you actually ran it — paste the exact command and its output.
6. Do NOT install or download any program on Robert's PC. Do NOT write Windows-only test harnesses or fight PowerShell quoting. If a check needs Linux, say so in PROGRESS.md and Claude will run it.
7. Use the IDs, package names and commands below **exactly** (capital letters matter). Claude already checked every one — do not swap anything for one you "remember".

## Goal
Add the best "only on Linux" extras to ForgeOS:
- **Speech Note** — talk and it types, reads text aloud, translates; fully offline and private.
- **Easy Effects** — sound equalizer + removes background noise from the microphone.
- **Moonlight** — play your PC games on another screen (pairs with Sunshine below).
- **Impression** — make bootable USB sticks (ForgeOS will need this for its USB installer).
- **KDE Connect** — phone ↔ PC: texts, notifications, shared clipboard, send files, use phone as a remote.
- **Android Apps** menu button — one click opens Bazzite's built-in Waydroid setup.
- **Game Streaming** menu button — one click opens Bazzite's built-in Sunshine setup.

## What Claude verified (2026-10-23)
| Item | Exact value | Source checked |
|---|---|---|
| Speech Note | `net.mkiol.SpeechNote` | Flathub API: MPL-2.0, verified, 4.8.4 |
| Easy Effects | `com.github.wwmm.easyeffects` | Flathub API: GPL-3.0+, verified, 8.3.0 |
| Moonlight | `com.moonlight_stream.Moonlight` | Flathub API: GPL-3.0+, verified, 6.2.0 |
| Impression | `io.gitlab.adhami3310.Impression` | Flathub API: GPL-3.0, verified, 3.8.0 |
| KDE Connect | Fedora package `kde-connect` | packages.fedoraproject.org (subpackages: kde-connect, kdeconnectd) |
| Android setup | `ujust setup-waydroid` | Bazzite repo: `82-bazzite-waydroid.just` (alias of `configure-waydroid`), waydroid is in the image |
| Streaming setup | `ujust setup-sunshine` | Bazzite repo: `82-bazzite-sunshine.just` |
| Terminal | `konsole` | Bazzite KDE pins `org.kde.konsole.desktop` |
| Package module | BlueBuild `type: dnf` → `install:` → `packages:` | blue-build/modules `dnf/README.md` |

---

## Step 1 — Add the apps and KDE Connect to the recipe
Edit ONLY `recipes/recipe.yml` and `tests/test-flatpak-list.sh`.

**A. `recipes/recipe.yml`**
1. Add a NEW module directly ABOVE the comment line `# Apps every ForgeOS user gets. All sandboxed (Flatpak) and free.` (so it sits between the `type: script` module and the `type: default-flatpaks` module), exactly:
```yaml
  # Phone <-> PC link: texts, notifications, shared clipboard, send files
  - type: dnf
    install:
      packages:
        - kde-connect

```
2. At the END of the existing `install:` list (after `it.mijorus.gearlever`), add:
```yaml
          # Cool stuff
          - net.mkiol.SpeechNote            # Talk to type, read aloud, translate — offline & private
          - com.github.wwmm.easyeffects     # Sound equalizer + mic background-noise removal
          - com.moonlight_stream.Moonlight  # Play your PC games on another screen
          - io.gitlab.adhami3310.Impression # Make bootable USB sticks
```
3. Change nothing else (`notify: true`, `scope: system`, the `- scope: user` entry, and all other modules stay exactly as they are).

**B. `tests/test-flatpak-list.sh`**
- Add the same 4 IDs to the END of the `APPROVED_IDS` array (same order as above). Change nothing else in the script.

Check you ran: `git diff --stat` (only `recipes/recipe.yml`, `tests/test-flatpak-list.sh` and `PROGRESS.md` changed) and paste `git diff recipes/recipe.yml tests/test-flatpak-list.sh`. If Git Bash is available, also run `bash tests/test-flatpak-list.sh` and paste the output (it must say 29 approved IDs).

## Step 2 — "Android Apps" and "Game Streaming" menu buttons + automatic check
Create exactly these 3 files and edit `.github/workflows/tests.yml` (allowed for this step only).

**A. `files/system/usr/share/applications/forgeos-android-apps.desktop`** — exactly:
```
[Desktop Entry]
Type=Application
Name=Android Apps Setup
Comment=Set up Android apps on ForgeOS (Waydroid)
Exec=konsole --hold -e ujust setup-waydroid
Icon=waydroid
Categories=System;
Keywords=android;phone;apps;waydroid;
Terminal=false
```

**B. `files/system/usr/share/applications/forgeos-game-streaming.desktop`** — exactly:
```
[Desktop Entry]
Type=Application
Name=Game Streaming Setup
Comment=Stream your PC games to a phone, tablet or TV (Sunshine + Moonlight)
Exec=konsole --hold -e ujust setup-sunshine
Icon=applications-games
Categories=Game;
Keywords=stream;sunshine;moonlight;games;tv;
Terminal=false
```

**C. `tests/test-cool-stuff.sh`** (bash; only bash/grep/sed/awk — no Python, no yq). Takes an optional repo-root argument (default `.`). It FAILS (exit 1) if any of these is false:
1. both `.desktop` files above exist;
2. neither `.desktop` file contains a carriage return (CR) byte;
3. in each file, line 1 is exactly `[Desktop Entry]`, and the file has the exact lines `Type=Application`, `Terminal=false`, and its exact `Name=` and `Exec=` lines from A/B;
4. if the command `desktop-file-validate` exists, it passes on both files (if it does not exist, print `SKIP:` for this check — not FAIL);
5. `recipes/recipe.yml` has a `type: dnf` module whose install packages include the exact line `- kde-connect`.
Prints `PASS:`/`FAIL:`/`SKIP:` per check and ends with `RESULT: all checks passed` (exit 0) or `RESULT: N check(s) failed` (exit 1). Same style as `tests/test-flatpak-list.sh`.

**D. `.github/workflows/tests.yml`** — add ONE new step at the END (after "Check default Flatpak app list"), exactly:
```yaml
      - name: Check Cool Stuff menu buttons and KDE Connect
        run: |
          sudo apt-get install -y --no-install-recommends desktop-file-utils
          bash tests/test-cool-stuff.sh
```
Change nothing else in that file.

Check you ran: `git status --short` and paste it. Do not try to run the test on Windows — Claude runs it on Linux.

---

## PROGRESS.md format (PROGRESS.md already exists for this job — append after each step)
```
## Step N — <title> — <date>
What I did:
- ...
What I ran + output:
<exact commands and output>
Questions / unsure about: <or "none">
STATUS: WAITING FOR CLAUDE REVIEW
```
