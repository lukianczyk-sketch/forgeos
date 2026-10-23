# ForgeOS — pick-up notes

## Decisions (locked with Robert)
- Name: ForgeOS, an RL Forge Works product.
- Linux-based (not from scratch). 64-bit. Built on Bazzite (Universal Blue) with BlueBuild + GitHub Actions (free).
- Must run Linux AND Windows software + games. Layers: native Linux → Proton/Wine (Steam, Heroic, Bottles) → Windows in a VM or dual-boot only if a legit license exists. Kernel anti-cheat games (e.g. Valorant) won't run outside real Windows — be honest about this.
- Security first: atomic read-only core, signed images, rollback, Flatpak sandboxing, LUKS2 AES-256 full-disk encryption at install.
- AI helper is local/private and may only SUGGEST; never changes system without user approval.
- Clean Sweep "hacked" button (v1 done, see below).
- Own browser = ship a fast hardened one (Brave) now. A ForgeOS-branded Chromium build is a possible later step (Chromium is open source). Don't use Microsoft/Windows logos or look-alike trademarks.
- OS image + source must be public (GPL / free GHCR hosting). Robert's money apps stay private.

## Status (updated 2026-10-23)
- v0.2.0 tagged (commit 7f24744): Job 1 "ForgeOS AI Setup" complete — Ollama v0.40.8 baked in (checksum-verified), local-only ollama.service, `forgeos-ai-setup` picks best Apache-2.0 model by VRAM and downloads only on Yes, menu entry + one-time first-login offer. GitHub `tests` + `bluebuild` both green.
- Clean Sweep v1 in image (`forgeos-cleansweep` + `-gui`).
- Default Flatpaks so far: Brave, Bottles, Heroic, Alpaca, Flatseal.

## How we work
- Rabbit Team (Cline + LM Studio on Robert's PC) writes all code from `RABBIT-BLUEPRINT.md` (current job), one step at a time, logs to `PROGRESS.md`. Claude reviews, then commits + pushes.
- Finished jobs: `blueprints/job1-ai-setup.md` + `blueprints/job1-progress.md`.

## Next steps
1. Job 2 "New Apps": DONE — 25 verified free Flathub apps + tests/test-flatpak-list.sh. Tag v0.3.0.
2. Job 3 "Clean Sweep" upgrade (blueprint in Claude project; upgrade v1, keep names; v1 behavior becomes `reset-system`).
3. Later: branding / Windows-style layout, USB installer (ISO), AMD + NVIDIA variants, real-machine test.

## Known gaps / to verify at test time
- Alpaca may need its Ollama plugin for fully local models.
- Clean Sweep quarantines user-enabled services in /etc/systemd/system too (by design for "hacked" mode) — user may need to re-enable things like VPNs.
- Can't remove firmware/boot-level malware; Secure Boot + reinstall is the answer there.
