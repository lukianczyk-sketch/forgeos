# RABBIT BLUEPRINT — ForgeOS Job 2: "New Apps"

**For:** Rabbit Team (Cline in VS Code). **Reviewer:** Claude.
**Repo:** `lukianczyk-sketch/forgeos` (BlueBuild image, base `ghcr.io/ublue-os/bazzite:stable`).
Job 1 (AI Setup) is finished and tagged `v0.2.0`. Its blueprint and progress log are in `blueprints/` — do not edit them.

## Rules (read every time)
1. Do **ONE step only**, then stop. Write what you did in `PROGRESS.md` (format at the bottom) and wait for Claude's OK before the next step.
2. **Free only.** No paid tools, services, keys or accounts.
3. Only change the files the step names. Never edit `cosign.pub`, `blueprints/`, or anything under `files/system/usr/bin/forgeos-cleansweep*`.
4. Bash scripts start with `#!/usr/bin/env bash` and `set -euo pipefail`, use LF line endings, and must pass `shellcheck -S warning`.
5. Never claim "tested" or "passed" unless you actually ran it — paste the exact command and its output.
6. Do NOT install or download any program on Robert's PC. Do NOT write Windows-only test harnesses. If a check needs Linux, say so and Claude will run it.
7. Use the app IDs below **exactly** (capital letters matter). Claude already checked every one live on Flathub — do not swap any ID for one you "remember".

## Goal
Every ForgeOS user gets a full set of the best free apps on first boot, so a person coming from Windows has everything they need without hunting: office, email, photo/video tools, passwords, backups, a Windows-style Task Manager, and more. All apps are Flatpaks from Flathub (sandboxed, auto-updating), installed by the existing `default-flatpaks` module in `recipes/recipe.yml`.

## The approved app list (Claude-verified on Flathub 2026-10-23: free/open-source license, verified publisher, not end-of-life)
| Group | App | Flathub ID |
|---|---|---|
| Already in recipe | Brave | `com.brave.Browser` |
| Already in recipe | Bottles | `com.usebottles.bottles` |
| Already in recipe | Heroic | `com.heroicgameslauncher.hgl` |
| Already in recipe | Alpaca | `com.jeffser.Alpaca` |
| Already in recipe | Flatseal | `com.github.tchx84.Flatseal` |
| Office & email | ONLYOFFICE | `org.onlyoffice.desktopeditors` |
| Office & email | Thunderbird | `org.mozilla.thunderbird` |
| Photo & video | GIMP | `org.gimp.GIMP` |
| Photo & video | Pinta | `com.github.PintaProject.Pinta` |
| Photo & video | Kdenlive | `org.kde.kdenlive` |
| Photo & video | OBS Studio | `com.obsproject.Studio` |
| Photo & video | Haruna | `org.kde.haruna` |
| Photo & video | Elisa | `org.kde.elisa` |
| Photo & video | Gwenview | `org.kde.gwenview` |
| Safety | KeePassXC | `org.keepassxc.KeePassXC` |
| Safety | Pika Backup | `org.gnome.World.PikaBackup` |
| Tools | Mission Center | `io.missioncenter.MissionCenter` |
| Tools | LocalSend | `org.localsend.localsend_app` |
| Tools | RustDesk | `com.rustdesk.RustDesk` |
| Tools | PDF Arranger | `com.github.jeromerobert.pdfarranger` |
| Tools | Okular | `org.kde.okular` |
| Tools | Skanpage | `org.kde.skanpage` |
| Tools | KCalc | `org.kde.kcalc` |
| Tools | Filelight | `org.kde.filelight` |
| Tools | Gear Lever | `it.mijorus.gearlever` |

Total: 25 IDs. Note: the OLD Thunderbird ID `org.mozilla.Thunderbird` (capital T) is end-of-life on Flathub — it must NOT appear anywhere.

---

## Step 1 — Add the apps to the recipe
Edit ONLY `recipes/recipe.yml`, inside the existing `default-flatpaks` → first configuration → `install:` list:
- Keep the 5 apps already there, in the same order, with their comments.
- Below them, add the other 20 IDs from the table, grouped in the table's order. Put a short comment line before each group (e.g. `# Office & email`), and a short end-of-line comment on each app saying what it is (same style as the existing lines, e.g. `# Office suite — opens Word/Excel/PowerPoint files`).
- Do not change anything else in the file (`notify: true`, `scope: system`, the empty `- scope: user` entry, the other modules all stay exactly as they are).
- Each ID must appear exactly once.
Check you ran: `git diff --stat` (only `recipes/recipe.yml` and `PROGRESS.md` changed) and paste `git diff recipes/recipe.yml`.

## Step 2 — Automatic check for the app list
Create `tests/test-flatpak-list.sh` (bash) that reads `recipes/recipe.yml` and FAILS (exit 1) if:
1. any of the 25 IDs in the table is missing from the file (keep the 25 IDs in ONE array at the top of the script);
2. any Flatpak ID listed under `install:` appears more than once;
3. the end-of-life ID `org.mozilla.Thunderbird` appears anywhere (match it case-sensitively — `org.mozilla.thunderbird` lowercase is the correct one and must pass);
4. any `install:` line is not a valid reverse-DNS app ID (regex: `^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2,}$` after stripping the leading `- ` and any `# comment`).
It prints `PASS:`/`FAIL:` per check and ends with `RESULT: all checks passed` (exit 0) or `RESULT: N check(s) failed` (exit 1).
Use only bash, grep, sed, awk (no Python, no yq — the GitHub runner and Robert's PC must not need extra installs).
Then add ONE new step at the end of `.github/workflows/tests.yml` (this step is allowed to edit that file):
```yaml
      - name: Check default Flatpak app list
        run: bash tests/test-flatpak-list.sh
```
Run it yourself with Git Bash if available and paste the output. Also prove check 3 works: copy recipe.yml to a temp file, add the bad ID, run the script against it (the script may take an optional path argument, default `recipes/recipe.yml`), paste the FAIL output, delete the temp file.

---

## PROGRESS.md format (append after each step)
```
## Step N — <title> — <date>
What I did:
- ...
What I ran + output:
<exact commands and output>
Questions / unsure about: <or "none">
STATUS: WAITING FOR CLAUDE REVIEW
```
