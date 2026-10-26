# RABBIT BLUEPRINT — Job 6: Panic Button

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype. Each step prompt gives you the EXACT file
contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
One key, **Meta+Shift+Esc** (or the "Panic Button" menu entry), instantly:
1. Switches the USB camera OFF at the USB level (apps cannot switch it back on).
2. Mutes EVERY microphone (PipeWire sources, not speaker "monitor" sources) and keeps them
   muted while the panic is on (a small guard re-mutes every 2 seconds).
3. Cuts the internet: Wi-Fi + mobile radios off (rfkill) and every network connection off
   (`nmcli networking off`, covers cable + VPN). Bluetooth stays on so keyboards/mice work.
4. Locks the screen, and shows a notification of what was cut.

"All Clear" (menu entry) asks first, then turns back on only what was on before.

## How (key facts — all verified by Claude)
- Root part: `/usr/libexec/forgeos-panic-helper cut|restore|status`, run through `pkexec`.
  Polkit action `org.forgeos.panic` (`/usr/share/polkit-1/actions/org.forgeos.panic.policy`):
  allow_active=yes (no password for the person at the screen), auth_admin otherwise,
  annotate `org.freedesktop.policykit.exec.path` = the helper. pkexec wipes the environment,
  so the helper's FORGEOS_PANIC_* test settings can't be abused.
- Camera: for each `/sys/class/video4linux/video*`, walk up from `device` to the folder that has
  `idVendor` + `authorized` (the USB device) and write 0 to `authorized`; restore writes 1.
  A camera with no USB parent (built-in MIPI type) is reported: "cover it".
- State: root part in `/run/forgeos-panic/` (cameras, radios, networking, active); user part in
  `$XDG_RUNTIME_DIR/forgeos-panic/` (mics, active). "Before" state is saved only on the first press.
  /run is empty after a restart → All Clear then just turns Wi-Fi + network on (cameras come back
  by themselves).
- Shortcut: Plasma 6 kglobalacceld loads every app whose .desktop has `X-KDE-Shortcuts`
  (globalshortcutsregistry.cpp, KApplicationTrader query) → `X-KDE-Shortcuts=Meta+Shift+Esc`.
- Screen lock: D-Bus `org.freedesktop.ScreenSaver.Lock`; fallback `loginctl lock-session`, then
  `loginctl lock-sessions`.
- Packages added to recipe dnf list: `pulseaudio-utils` (pactl), `libnotify` (notify-send).
  rfkill, nmcli, pkexec, kdialog, dbus-send, setsid are already in Bazzite.

## Files
- `files/system/usr/libexec/forgeos-panic-helper` (new)
- `files/system/usr/share/polkit-1/actions/org.forgeos.panic.policy` (new)
- `files/system/usr/bin/forgeos-panic` (new)
- `files/system/usr/share/applications/forgeos-panic.desktop` (new)
- `files/system/usr/share/applications/forgeos-all-clear.desktop` (new)
- `files/scripts/forgeos-setup.sh` (chmod line: add the two scripts)
- `recipes/recipe.yml` (dnf: add pulseaudio-utils, libnotify)
- `tests/test-panic.sh` (new, cases A-M) + `.github/workflows/tests.yml` (one new step)

## Steps (ONE per Cline task, then stop)
- Step 1: helper + polkit policy + forgeos-setup.sh chmod + recipe packages.
- Step 2: forgeos-panic + the two .desktop files.
- Step 3: tests/test-panic.sh (written in two parts) + tests.yml step.
- Then Claude tests on Linux, Robert's PC, and GitHub Actions → tag v0.7.0.

## Report format (append to PROGRESS.md)
```
## Step N — <title>
- Files changed: <list>
- Notes: <anything unclear>
- STATUS: WAITING FOR CLAUDE REVIEW
```
