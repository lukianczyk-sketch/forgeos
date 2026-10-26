# RABBIT BLUEPRINT — Job 7: Privacy Report

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype. Each step prompt gives you the EXACT file
contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
KDE already shows a live light when the camera or mic is on. ForgeOS adds what KDE is missing:
1. **Usage log**: a small background note-taker (user service) writes down every time an app
   starts/stops using the camera, the microphone, or sees the screen (screen sharing/recording).
   It pops up a notice when an app turns on the camera or starts seeing the screen.
2. **Plain-English report** ("Privacy Report" in the menu): who used the camera/mic/screen in the
   last 7 days, how many times, for how long, who is using it RIGHT NOW, what you blocked, and what
   each sandboxed (Flatpak) app is ALLOWED to do (camera, microphone, all your files, location).
3. **Block button**: block an app from the camera, the microphone or all your files. Undo any block.

## How (key facts — all verified by Claude)
- Who uses what: `pw-dump` (pipewire-utils) JSON + jq. A link from a node to a *running*
  input stream = use. Mic = from an `Audio/Source*` node into `Stream/Input/Audio`, skipping volume
  meters (`stream.monitor`=true, set by pipewire-pulse for peak-detect streams). Recording speaker
  sound (from an `Audio/Sink`) is NOT counted. Camera = from a `Video/Source` node with `device.api`.
  Screen = from a `Stream/Output/Video` node whose `media.name` starts with `kwin-screencast`
  (KWin's screencast stream). Plasma's own window thumbnails (plasmashell) are skipped.
- App name: Flatpak id from `pipewire.access.portal.app_id` (pipewire-pulse puts it on the client,
  and pactl merges client props into each stream), else the program name. Programs that open
  /dev/video* directly are found in /proc/*/fd; their Flatpak id comes from the systemd scope
  `app-flatpak-<id>-<n>.scope` (`-` is escaped as `\x2d`).
- Log: `~/.local/state/forgeos-privacy/usage.log`, lines `epoch<TAB>start|stop<TAB>kind<TAB>app<TAB>name`.
  90 days kept. On stop (logout) every open use is closed; leftovers from a crash are closed at start.
- Blocks: `~/.config/forgeos-privacy/blocked`, lines `kind<TAB>app[<TAB>what was removed]`.
  - Camera (Flatpak only): `flatpak permission-set devices camera <app> no` (camera portal) and, if
    the app has `devices=all`, `flatpak override --user --nodevice=all`. Undo puts back exactly that.
  - Files (Flatpak only): remove `home`/`host` access with `flatpak override --user --nofilesystem=`.
  - Microphone (any app): Flatpak has no mic-only switch (the sound socket is both speaker and mic),
    so the note-taker mutes every recording stream of a blocked app with `pactl set-source-output-mute`
    the moment it starts (`pactl subscribe`), and re-checks every 2 seconds. Sound still plays.
- `flatpak permission-show` printed nothing on Flatpak 1.14 → use `flatpak permissions devices camera`
  and `flatpak permissions location location` instead (tab-separated when not on a terminal).
- Package added to the recipe: `pipewire-utils` (pw-dump). jq, pactl (pulseaudio-utils), notify-send,
  kdialog, flatpak are already in the image.
- Service on for every user: `systemctl --global enable forgeos-privacy-watch.service` in forgeos-setup.sh.

## Files
- `files/system/usr/libexec/forgeos-privacy-lib` (new, shared parts, sourced)
- `files/system/usr/bin/forgeos-privacy` (new: watch / now / report)
- `files/system/usr/lib/systemd/user/forgeos-privacy-watch.service` (new)
- `files/system/usr/bin/forgeos-privacy-block` (new: block / unblock / list)
- `files/system/usr/bin/forgeos-privacy-gui` (new: the window, kdialog)
- `files/system/usr/share/applications/forgeos-privacy.desktop` (new: menu entry "Privacy Report")
- `files/scripts/forgeos-setup.sh` (chmod + enable), `recipes/recipe.yml` (pipewire-utils)
- `tests/test-privacy.sh` (new, cases A-O) + `.github/workflows/tests.yml` (one new step)

## Steps (ONE per Cline task, then stop)
- Step 1: lib + forgeos-privacy (2 parts) + service + setup.sh (chmod forgeos-privacy, enable) + recipe.
- Step 2: forgeos-privacy-block + forgeos-privacy-gui + menu entry + setup.sh chmod for both.
- Step 3: tests/test-privacy.sh (4 parts) + tests.yml step.
- Then Claude tests on Linux, Robert's PC and GitHub Actions → tag v0.8.0.

## Report format (append to PROGRESS.md)
```
## Step N — <title>
- Files changed: <list>
- Notes: <anything unclear>
- STATUS: WAITING FOR CLAUDE REVIEW
```
