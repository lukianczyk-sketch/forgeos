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

## Status (updated 2026-10-25)
- v0.2.0 tagged (commit 7f24744): Job 1 "ForgeOS AI Setup" complete — Ollama v0.40.8 baked in (checksum-verified), local-only ollama.service, `forgeos-ai-setup` picks best Apache-2.0 model by VRAM and downloads only on Yes, menu entry + one-time first-login offer. GitHub `tests` + `bluebuild` both green.
- v0.3.0 (deeb157): Job 2 "New Apps" — 25 verified free Flathub apps + tests/test-flatpak-list.sh.
- v0.4.0 (955b6e1): Job 4 "Cool Stuff" — KDE Connect (dnf `kde-connect`), Speech Note, Easy Effects, Moonlight, Impression (29 Flatpaks total); menu buttons "Android Apps Setup" (`ujust setup-waydroid`) and "Game Streaming Setup" (`ujust setup-sunshine`); tests/test-cool-stuff.sh. tests + bluebuild green.
- v0.5.0 (42bef3b): Job 3 "Clean Sweep" upgrade — `forgeos-cleansweep scan [--dry-run]` (core check, ClamAV, rkhunter, chkrootkit, startup audit; exit 0/1/2/3), `quarantine list|restore|delete`, `reset-system [--dry-run] [--yes]`, `full-wipe [--dry-run | --yes WIPE]`; GUI `forgeos-cleansweep-gui`; weekly scan timer; after reset/wipe a one-time login reminder asks for a new password (`/usr/libexec/forgeos-password-reminder`; never `passwd -e` — the KDE login freezes on expired passwords). tests/test-clean-sweep.sh cases A-Q (+ real ClamAV in CI). tests + bluebuild green.

## How we work
- Rabbit Team (Cline + LM Studio on Robert's PC) writes all code from `RABBIT-BLUEPRINT.md` (current job), one step at a time, logs to `PROGRESS.md`. Claude reviews, then commits + pushes.
- Finished jobs: `blueprints/job1-*`, `blueprints/job2-*`, `blueprints/job3-*`, `blueprints/job4-*` (blueprint + progress log each).

## Next steps
Robert approved the "what Windows/Linux should have built in" roadmap (details in the Claude project: forgeos-feature-roadmap.md). Order:
1. Job 5 Undo Button (turn on Bazzite's snapper /var/home snapshots + one timeline button).
2. Job 6 Panic Button → Job 7 Privacy Report → Job 8 Scam Shield → Job 9 Ask Your PC → Job 10 Will It Run? → Job 11 Find Anything → Job 12 GhostFinder → Job 13 Family Mode → Job 14 Moving Day → Job 15 Drive Death Warning → Job 16 Ransomware Tripwire → Job 17 Fake Tech Support Guard → Job 18 Digital Will → Job 19 Find My PC (private) → Job 20 Why Is It Slow? → Job 21 PC Report Card → Job 22 Show Me How → Job 23 Plain-English Errors → Job 24 Ask Before Connecting → Job 25 Power Outage Saver → Job 26 Never Bricks → Job 27 Offline Survival Kit → Job 28 Password Breach Alarm → Job 29 Kids Mode.
3. Later: branding / Windows-style layout, USB installer (ISO), AMD + NVIDIA variants, real-machine test.

## Known gaps / to verify at test time
- Alpaca may need its Ollama plugin for fully local models.
- Clean Sweep quarantines user-enabled services in /etc/systemd/system too (by design for "hacked" mode) — user may need to re-enable things like VPNs.
- Can't remove firmware/boot-level malware; Secure Boot + reinstall is the answer there.
