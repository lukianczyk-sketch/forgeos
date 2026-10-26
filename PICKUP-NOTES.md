# ForgeOS — pick-up notes

## Decisions (locked with Robert)
- Name: ForgeOS, an RL Forge Works product.
- Linux-based (not from scratch). 64-bit. Built on Bazzite (Universal Blue) with BlueBuild + GitHub Actions (free).
- Must run Linux AND Windows software + games. Layers: native Linux → Proton/Wine (Steam, Heroic, Bottles) → Windows in a VM or dual-boot only if a legit license exists. Kernel anti-cheat games (e.g. Valorant) won't run outside real Windows — be honest about this.
- Security first: atomic read-only core, signed images, rollback, Flatpak sandboxing, LUKS2 AES-256 full-disk encryption at install.
- AI helper is local/private and may only SUGGEST; never changes system without user approval.
- Clean Sweep "hacked" button (v2 done in v0.5.0, see below).
- Own browser = ship a fast hardened one (Brave) now. A ForgeOS-branded Chromium build is a possible later step (Chromium is open source). Don't use Microsoft/Windows logos or look-alike trademarks.
- OS image + source must be public (GPL / free GHCR hosting). Robert's money apps stay private.

## Status (updated 2026-10-25, v0.8.0)
- v0.2.0 tagged (commit 7f24744): Job 1 "ForgeOS AI Setup" complete — Ollama v0.40.8 baked in (checksum-verified), local-only ollama.service, `forgeos-ai-setup` picks best Apache-2.0 model by VRAM and downloads only on Yes, menu entry + one-time first-login offer. GitHub `tests` + `bluebuild` both green.
- v0.3.0 (deeb157): Job 2 "New Apps" — 25 verified free Flathub apps + tests/test-flatpak-list.sh.
- v0.4.0 (955b6e1): Job 4 "Cool Stuff" — KDE Connect (dnf `kde-connect`), Speech Note, Easy Effects, Moonlight, Impression (29 Flatpaks total); menu buttons "Android Apps Setup" (`ujust setup-waydroid`) and "Game Streaming Setup" (`ujust setup-sunshine`); tests/test-cool-stuff.sh. tests + bluebuild green.
- v0.5.0 (42bef3b): Job 3 "Clean Sweep" upgrade — `forgeos-cleansweep scan [--dry-run]` (core check, ClamAV, rkhunter, chkrootkit, startup audit; exit 0/1/2/3), `quarantine list|restore|delete`, `reset-system [--dry-run] [--yes]`, `full-wipe [--dry-run | --yes WIPE]`; GUI `forgeos-cleansweep-gui`; weekly scan timer; after reset/wipe a one-time login reminder asks for a new password (`/usr/libexec/forgeos-password-reminder`; never `passwd -e` — the KDE login freezes on expired passwords). tests/test-clean-sweep.sh cases A-Q (+ real ClamAV in CI). tests + bluebuild green.
- v0.6.0 (a757b26): Job 5 "Undo Button" — hourly snapshots of /var/home with snapper (config `root`, same as Bazzite's `ujust configure-snapshots`; first-boot `/usr/libexec/forgeos-undo-setup`, safe range limits + FREE_LIMIT=0.2, cleanup timer hourly); engine `forgeos-undo` (status, versions, restore never overwrites + ClamAV check on the restored copy, snapshot-now, updates, undo-update = rpm-ostree rollback); window `forgeos-undo-gui`, menu entry + Dolphin right-click "Get back an older version"; Clean Sweep scan skips `.snapshots` and Full Wipe deletes every home snapshot. tests/test-undo.sh A-K, test-undo-extras.sh L-T, test-undo-real.sh U-Y (real btrfs + snapper, root, CI). tests + bluebuild green.
- v0.7.0 (1dd2b69): Job 6 "Panic Button" — Meta+Shift+Esc (or menu "Panic Button") runs `forgeos-panic on`: mutes every mic (pactl, non-.monitor sources; a guard re-mutes every 2 s), cuts the USB camera at the USB level (sysfs `authorized`=0) and the internet (rfkill wlan/wwan + `nmcli networking off`; Bluetooth left on for keyboards/mice) via root helper `/usr/libexec/forgeos-panic-helper` (pkexec, polkit action org.forgeos.panic: no password for the active user), locks the screen (D-Bus ScreenSaver.Lock → loginctl), critical notification. "All Clear" menu entry (`forgeos-panic off`) asks first, then restores only what was on before (state in /run/forgeos-panic + $XDG_RUNTIME_DIR/forgeos-panic). Recipe adds pulseaudio-utils + libnotify. tests/test-panic.sh A-M. tests + bluebuild green.
- v0.8.0 (2211d7d): Job 7 "Privacy Report" — user service `forgeos-privacy-watch` (enabled with `systemctl --global`) runs `forgeos-privacy watch`: every 2 s reads `pw-dump` (pipewire-utils, added to recipe) + /proc/*/fd for /dev/video*, logs start/stop of camera / mic / screen-share use to ~/.local/state/forgeos-privacy/usage.log (90 days), notifies when an app turns on the camera or sees the screen. `forgeos-privacy report [days]` = plain-English report (who, how often, how long, RIGHT NOW, blocks, what each Flatpak is allowed: camera / mic / all files / location). `forgeos-privacy-block block|unblock <app> camera|mic|files [--close]` (camera: portal permission-set + `--nodevice=all` override; files: `--nofilesystem=home|host`; mic: the watcher mutes that app's recording streams via pactl the moment they start). Window `forgeos-privacy-gui` + menu entry "Privacy Report". Shared code in /usr/libexec/forgeos-privacy-lib. tests/test-privacy.sh A-O. tests + bluebuild green.

## How we work
- Rabbit Team (Cline + LM Studio on Robert's PC) writes all code from `RABBIT-BLUEPRINT.md` (current job), one step at a time, logs to `PROGRESS.md`. Claude reviews, then commits + pushes.
- Finished jobs: `blueprints/job1-*`, `blueprints/job2-*`, `blueprints/job3-*`, `blueprints/job4-*`, `blueprints/job5-*`, `blueprints/job6-*`, `blueprints/job7-*` (blueprint + progress log each).

## Next steps
Robert approved the "what Windows/Linux should have built in" roadmap (details in the Claude project: forgeos-feature-roadmap.md). Order:
1. Job 8 Scam Shield → Job 9 Ask Your PC → Job 10 Will It Run? → Job 11 Find Anything → Job 12 GhostFinder → Job 13 Family Mode → Job 14 Moving Day → Job 15 Drive Death Warning → Job 16 Ransomware Tripwire → Job 17 Fake Tech Support Guard → Job 18 Digital Will → Job 19 Find My PC (private) → Job 20 Why Is It Slow? → Job 21 PC Report Card → Job 22 Show Me How → Job 23 Plain-English Errors → Job 24 Ask Before Connecting → Job 25 Power Outage Saver → Job 26 Never Bricks → Job 27 Offline Survival Kit → Job 28 Password Breach Alarm → Job 29 Kids Mode.
2. Later: branding / Windows-style layout, USB installer (ISO), AMD + NVIDIA variants, real-machine test.

## Known gaps / to verify at test time
- Alpaca may need its Ollama plugin for fully local models.
- Clean Sweep quarantines user-enabled services in /etc/systemd/system too (by design for "hacked" mode) — user may need to re-enable things like VPNs.
- Can't remove firmware/boot-level malware; Secure Boot + reinstall is the answer there.
- Undo Button needs /var/home on btrfs (the Bazzite default); on other filesystems setup skips and the window says it is off. Snapshots are not backups — a dead drive loses them too.
- Panic Button: check on a real machine that Meta+Shift+Esc is free in KDE, that the USB camera really drops off, and that the lock works from the shortcut. Built-in (non-USB, MIPI) cameras cannot be cut — the notification says "cover it". Mic mute is software-level (PipeWire); the guard re-mutes, but a program with direct ALSA access could still record.
- Privacy Report: mic block = mute of the app's recording streams (sound still plays); a program with direct ALSA access could still record. Camera + files blocks work only for Flatpak apps and need the app restarted ("Close it now" offered). Camera-in-use via PipeWire counts only cameras with device.api; check on a real machine that Firefox/Zoom calls show up and that KWin screen sharing is logged (media.name kwin-screencast-*).
- Cline prompt lesson (Job 7): it turns real TAB characters in prompt files into the text "\t" — avoid literal tabs in code given to Cline (use printf '\t' or $'\t').
