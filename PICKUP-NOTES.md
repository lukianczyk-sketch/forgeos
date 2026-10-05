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

## Built so far (v0.1, not yet built on GitHub)
- recipes/recipe.yml — base ghcr.io/ublue-os/bazzite:stable, default Flatpaks (Brave, Bottles, Heroic, Alpaca, Flatseal), signing.
- files/system/usr/bin/forgeos-cleansweep — root script. Order: stage fresh signed image (online) → network off → rpm-ostree reset → quarantine non-factory files in /etc persistence dirs (compared against /usr/etc) → per-user autostart/systemd-user/authorized_keys → passwd -e users → flatpak override --reset → clamscan if present. Log: /var/log/forgeos-cleansweep-*.log
- files/system/usr/bin/forgeos-cleansweep-gui + .desktop — confirm dialog (kdialog/zenity), pkexec, offer reboot.
- Scripts pass bash -n and shellcheck (-S warning). NOT yet tested on a real machine.

## Next steps
1. Robert creates the GitHub repo + signing key (BlueBuild Workshop: https://workshop.blue-build.org/), repo name `forgeos`, public.
2. Push these files, first GitHub Actions build.
3. Test on a spare PC / USB / VM: rebase, check apps, run Clean Sweep.
4. Then: branding (logo, wallpaper, boot splash), Windows-like layout tweaks, Alpaca + Ollama local model setup, ClamAV, ISO installer + free hosting for it, NVIDIA variant (base bazzite-nvidia).

## Known gaps / to verify at test time
- Alpaca may need its Ollama plugin for fully local models.
- Clean Sweep quarantines user-enabled services in /etc/systemd/system too (by design for "hacked" mode) — user may need to re-enable things like VPNs.
- Can't remove firmware/boot-level malware; Secure Boot + reinstall is the answer there.
