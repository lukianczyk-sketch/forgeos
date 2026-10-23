# ForgeOS — Progress log (Job 2: New Apps)

Job 1 log is in `blueprints/job1-progress.md` (finished, tagged v0.2.0).

### Claude — Job 2 blueprint written — 2026-10-23
Robert approved the 25-app list. Every Flathub ID checked live 2026-10-23 (license, verified publisher, not EOL).
NEXT for Rabbit: Step 1 only.

## Step 1 — Add the apps to the recipe — 2026-10-23
What I did:
- Edited ONLY `recipes/recipe.yml`: added the other 20 Flatpak IDs from the blueprint table below the existing 5, in the table's order.
- Grouped with short comment lines (`# Office & email`, `# Photo & video`, `# Safety`, `# Tools`) and a short end-of-line comment on each app, same style as the existing lines.
- Kept the original 5 apps in their original order with their comments; nothing else in the file changed (`notify: true`, `scope: system`, the empty `- scope: user` entry, all other modules untouched).
- Each of the 25 IDs appears exactly once. The end-of-life ID `org.mozilla.Thunderbird` (capital T) does not appear anywhere — only lowercase `org.mozilla.thunderbird`.
- Caught and fixed a line-ending problem I introduced: my first edit wrote CRLF into recipe.yml, but HEAD is LF and `.gitattributes` says `* text=auto eol=lf`. Converted back to LF with `sed -i 's/\r$//' recipes/recipe.yml`; verified 0 CR bytes after.
What I ran + output:
- `git --no-pager diff recipes/recipe.yml`:

```
diff --git a/recipes/recipe.yml b/recipes/recipe.yml
index 7fd95de..78a42ee 100644
--- a/recipes/recipe.yml
+++ b/recipes/recipe.yml
@@ -36,6 +36,30 @@ modules:
           - com.heroicgameslauncher.hgl   # Epic, GOG & Amazon games (Steam is built into the base)
           - com.jeffser.Alpaca            # Private on-device AI helper (Ollama-based, offline)
           - com.github.tchx84.Flatseal    # See/limit what each app is allowed to touch
+          # Office & email
+          - org.onlyoffice.desktopeditors   # Office suite — opens Word/Excel/PowerPoint files
+          - org.mozilla.thunderbird         # Email client
+          # Photo & video
+          - org.gimp.GIMP                   # Full-featured photo editor
+          - com.github.PintaProject.Pinta   # Lighter, easier photo editor
+          - org.kde.kdenlive                # Video editor
+          - com.obsproject.Studio           # Screen recording & live streaming
+          - org.kde.haruna                  # Modern video player
+          - org.kde.elisa                   # Music player
+          - org.kde.gwenview                # Photo viewer / slideshow
+          # Safety
+          - org.keepassxc.KeePassXC         # Password manager (local, encrypted)
+          - org.gnome.World.PikaBackup      # Back up files to a USB stick or other drive
+          # Tools
+          - io.missioncenter.MissionCenter  # Windows-style Task Manager
+          - org.localsend.localsend_app     # Share files with nearby devices — no internet needed
+          - com.rustdesk.RustDesk           # Free remote control of other computers
+          - com.github.jeromerobert.pdfarranger   # Reorder, merge & split PDF pages
+          - org.kde.okular                  # Document viewer (PDF, e-books and more)
+          - org.kde.skanpage                # Scan documents with a scanner
+          - org.kde.kcalc                   # Calculator with formulas
+          - org.kde.filelight               # See what is using your disk space
+          - it.mijorus.gearlever            # Tweak KDE settings in one place
       - scope: user
 
   # Image signing — systems only accept updates signed with our key
```
- Line endings (Git Bash): `tr -dc '\r' < recipes/recipe.yml | wc -c` → worktree after my first edit: 66; HEAD (`git show HEAD:recipes/recipe.yml`): 0. After `sed -i 's/\r$//' recipes/recipe.yml`: 0. `.gitattributes` says `* text=auto eol=lf`, so LF is correct.
- `git --no-pager diff --stat` (at time of writing, before appending this report):
```
 recipes/recipe.yml | 24 ++++++++++++++++++++++++
 1 file changed, 24 insertions(+)
```
(PROGRESS.md also shows as modified once this report is appended.)
Questions / unsure about: none
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 1 — 2026-10-23: ONE MUST FIX
Checked on disk:
- All 25 IDs present, exact spelling/case, exactly once, in blueprint order (scripted compare against the approved list). EOL `org.mozilla.Thunderbird` absent.
- YAML parses (python yaml): 25 installs, `notify: true`, `scope: system`, `- scope: user` intact. Only recipe.yml + PROGRESS.md changed. LF everywhere (0 CR). Good catch on the CRLF.
- **MUST FIX:** the comment on `it.mijorus.gearlever` is wrong. Gear Lever installs and manages AppImage apps — it does not tweak KDE settings. Change ONLY that comment to: `# Install & manage AppImage apps (adds them to the menu)`. Nothing else in the file.
NEXT for Rabbit: apply the MUST FIX, then STOP (no new report needed — Claude re-checks on disk). Step 2 comes after approval.

### Claude review — Step 1 — 2026-10-23: APPROVED
- MUST FIX applied: Gear Lever comment now correct; nothing else changed.
- Re-checked on disk: YAML parses, install list == approved 25 IDs exactly (order + case), 0 CR bytes.
NEXT for Rabbit: Step 2 only (start a fresh Cline task).

## Step 2 — Automatic check for the app list — 2026-10-23
Rabbit wrote `tests/test-flatpak-list.sh` (122 lines, bash + awk + grep only) and added the one step to `.github/workflows/tests.yml`, exactly as the blueprint says. Rabbit then got stuck on PowerShell quoting while checking line endings, so Claude stopped the task before the report and finished verification on Linux (below).

### Claude review — Step 2 — 2026-10-23: APPROVED
- Line endings: both files were saved with CRLF by the editor; Claude converted to LF (`sed -i 's/\r$//'`), 0 CR bytes now. No code changed.
- `shellcheck -S warning tests/test-flatpak-list.sh`: PASS.
- Real recipe: 4/4 PASS, `RESULT: all checks passed`, exit 0.
- Negative tests (temp copies, then deleted): missing `org.kde.kcalc` → FAIL check 1; duplicate `org.kde.okular` → FAIL check 2; `org.mozilla.Thunderbird` → FAIL check 3 (and check 1); bad ID `elisa` → FAIL check 4; missing file → FAIL, exit 1. CRLF recipe and an entry with no comment → still PASS (correct).
- Workflow YAML parses; new step is last, runs `bash tests/test-flatpak-list.sh`.
- Nice touches: awk stops the install block on dedent (so `- scope: user` is never read as an app), optional path argument, tolerant of CRLF.
STATUS: JOB 2 COMPLETE — committing, then tag v0.3.0 after the GitHub builds are green.
