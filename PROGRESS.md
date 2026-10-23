# ForgeOS Job 4 "Cool Stuff" — progress log

Blueprint: RABBIT-BLUEPRINT.md. Job 2 docs moved to blueprints/ (job2-new-apps.md, job2-progress.md).

## Step 1 — Add the apps and KDE Connect to the recipe — 2026-10-23
What I did:
- `recipes/recipe.yml`: added a NEW `type: dnf` module installing Fedora package `kde-connect`, directly ABOVE the comment line `# Apps every ForgeOS user gets. All sandboxed (Flatpak) and free.` (between the `type: script` module and the `type: default-flatpaks` module), exactly as written in the blueprint, including its trailing blank line.
- `recipes/recipe.yml`: at the END of the existing `install:` list (after `it.mijorus.gearlever`, before `- scope: user`) added the `# Cool stuff` group with the 4 new Flatpak IDs in blueprint order: `net.mkiol.SpeechNote`, `com.github.wwmm.easyeffects`, `com.moonlight_stream.Moonlight`, `io.gitlab.adhami3310.Impression`.
- `tests/test-flatpak-list.sh`: added the same 4 IDs to the END of the `APPROVED_IDS` array (same order). Nothing else changed in either file.
- Verified both files keep LF line endings: `git ls-files --eol` shows `w/lf` for both, and a byte scan found 0 CR bytes in each file after editing.

What I ran + output:
1) `git diff --stat`:
```
 PROGRESS.md                |  88 +------------------------
 RABBIT-BLUEPRINT.md        | 157 +++++++++++++++++++++++++++++----------------
 recipes/recipe.yml         |  11 ++++
 tests/test-flatpak-list.sh |   4 ++
 4 files changed, 117 insertions(+), 143 deletions(-)
```
2) `git diff recipes/recipe.yml tests/test-flatpak-list.sh`:
```
diff --git a/recipes/recipe.yml b/recipes/recipe.yml
index 8950fbb..a6f262f 100644
--- a/recipes/recipe.yml
+++ b/recipes/recipe.yml
@@ -25,6 +25,12 @@ modules:
       - install-ollama.sh
       - forgeos-setup.sh
 
+  # Phone <-> PC link: texts, notifications, shared clipboard, send files
+  - type: dnf
+    install:
+      packages:
+        - kde-connect
+
   # Apps every ForgeOS user gets. All sandboxed (Flatpak) and free.
   - type: default-flatpaks
     configurations:
@@ -60,6 +66,11 @@ modules:
           - org.kde.kcalc                   # Calculator with formulas
           - org.kde.filelight               # See what is using your disk space
           - it.mijorus.gearlever            # Install & manage AppImage apps (adds them to the menu)
+          # Cool stuff
+          - net.mkiol.SpeechNote            # Talk to type, read aloud, translate — offline & private
+          - com.github.wwmm.easyeffects     # Sound equalizer + mic background-noise removal
+          - com.moonlight_stream.Moonlight  # Play your PC games on another screen
+          - io.gitlab.adhami3310.Impression # Make bootable USB sticks
       - scope: user
 
   # Image signing — systems only accept updates signed with our key
diff --git a/tests/test-flatpak-list.sh b/tests/test-flatpak-list.sh
index 2df6aaa..6286dfe 100644
--- a/tests/test-flatpak-list.sh
+++ b/tests/test-flatpak-list.sh
@@ -40,6 +40,10 @@ APPROVED_IDS=(
     org.kde.kcalc
     org.kde.filelight
     it.mijorus.gearlever
+    net.mkiol.SpeechNote
+    com.github.wwmm.easyeffects
+    com.moonlight_stream.Moonlight
+    io.gitlab.adhami3310.Impression
 )
 
 EOL_ID='org.mozilla.Thunderbird' # end-of-life ID — must not appear anywhere (case-sensitive)
```
3) `bash tests/test-flatpak-list.sh` (run via Git Bash, `C:\Program Files\Git\bin\bash.exe`, from the repo root):
```
PASS: all 29 approved app IDs are present in recipes/recipe.yml
PASS: no app ID is listed more than once under install:
PASS: end-of-life ID org.mozilla.Thunderbird does not appear in recipes/recipe.yml
PASS: every install entry is a valid reverse-DNS app ID
----------------------------------------
RESULT: all checks passed
exit code: 0
```

Questions / unsure about:
- `git diff --stat` also lists PROGRESS.md and RABBIT-BLUEPRINT.md as modified. I did NOT touch those files — their LastWriteTime (1:54 AM) predates my edits (2:28 AM), so they are pre-existing uncommitted changes in the working tree (presumably Robert/Claude's Job 4 setup). The blueprint check expected only `recipes/recipe.yml`, `tests/test-flatpak-list.sh` and `PROGRESS.md` to show up.
- I ran the bash test on Windows via Git Bash rather than native Linux; if Claude wants a pure-Linux run, please re-run it there.

STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 1 — 2026-10-23: APPROVED
Checked on disk (Linux):
- `recipes/recipe.yml` parses (python yaml). Module order: files → script → **dnf (packages: [kde-connect])** → default-flatpaks → signing. Flatpak install list = 29 IDs, `notify: true`, `scope: system`, `- scope: user` intact.
- The 4 new IDs match the blueprint exactly (case + order), with the `# Cool stuff` group comment. Test array has the same 4 at the end; nothing else in the script changed.
- `bash tests/test-flatpak-list.sh` on Linux: 4/4 PASS, `RESULT: all checks passed`, exit 0.
- 0 CR bytes in all changed files.
- Your question: correct — PROGRESS.md and RABBIT-BLUEPRINT.md were Claude's job setup (Job 2 docs moved to blueprints/). Good catch flagging it instead of touching them.
NEXT for Rabbit: Step 2 only (start a fresh Cline task).

