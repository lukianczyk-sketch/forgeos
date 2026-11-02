# ForgeOS — by RL Forge Works

Secure, fast, Windows-friendly Linux with a built-in private AI helper.

- **Base:** Bazzite (Universal Blue / Fedora Atomic, KDE desktop: taskbar + Start menu)
- **Games:** Steam + Proton built in; Heroic for Epic / GOG / Amazon
- **Windows programs:** Bottles (Wine) — one click per program
- **Browser:** Brave (ads and trackers blocked)
- **AI helper:** Alpaca (on-device, private, offline)
- **Security:** read-only core, signed updates, one-click rollback, sandboxed apps (Flatseal to manage), full-disk encryption at install
- **Clean Sweep button:** "I think I've been hacked" — resets the system to genuine ForgeOS, removes hidden auto-start programs and remote-access keys, resets app permissions, forces new passwords. Personal files are kept; anything removed goes to `/var/lib/forgeos/quarantine/`.
- **GhostFinder — see who's watching:** one button finds cameras on your network, spy-camera Wi-Fi and Bluetooth trackers (AirTag, SmartTag, Tile...) away from their owner; hot/cold hunt meter, trip watch, background watch, plain-English "what do I do now". Nothing leaves the PC.
- **Family Mode — one switch makes this PC easy and safe:** big text, bigger mouse pointer and taller taskbar; every safety guard on; "Call for help" lets a family member see your screen and help through RustDesk — only after you click Accept, and only their RustDesk ID can ask; it texts them the number through your phone. Turn it off and everything goes back exactly as it was.
- **Always-On Guard — checks everything by itself:** every download is virus-checked the moment it lands (bad ones locked away, fake "invoice.pdf.exe" tricks flagged); every new email in Thunderbird is checked for scams and virus attachments; known scam and virus websites are blocked for the whole PC from free daily lists. Plain-English pop-ups with "Show why", one window to see and undo everything. Nothing leaves the PC.
- **Forge Helper — one private AI helper everywhere:** ask anything in plain English from the menu or by pressing Meta+H; it answers from 67 built-in help pages, runs the right ForgeOS tool for you (only after you say Yes), and quietly warns you about a full drive, a failed update or an old backup. It never shares anything — the AI runs on your own PC.
- **Drivers & BIOS — you never update a driver by hand again:** drivers update by themselves with ForgeOS and it tells you in plain words what changed; after every restart it checks your graphics, Wi-Fi, sound and Bluetooth still work and offers the way back if not; firmware for mice, docks and drives installs by itself, and a new BIOS is one tap (it finishes at your next restart, never forced). It also finds parts with no driver and picks the right ForgeOS for your graphics card.

## Which image?

- `forgeos` — PCs with AMD or Intel graphics.
- `forgeos-nvidia` — PCs with an NVIDIA GeForce GTX 16xx / RTX 20xx or newer card (including RTX 50 laptops). Uses NVIDIA's open driver.

Both images have exactly the same ForgeOS apps and tools (shared in `recipes/common-modules.yml`). With Secure Boot on, enroll the Universal Blue key once: `ujust enroll-secure-boot-key` (password `universalblue`).

## Install (switch an existing Fedora Atomic / Bazzite machine)

```
rpm-ostree rebase ostree-unverified-registry:ghcr.io/OWNER/forgeos:latest
systemctl reboot
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/OWNER/forgeos:latest
systemctl reboot
```

Replace `OWNER` with the GitHub account that hosts this repo. NVIDIA PCs: use `forgeos-nvidia` instead of `forgeos`. A USB installer (ISO) comes later — see the BlueBuild ISO guide.

## Verify an image

```
cosign verify --key cosign.pub ghcr.io/OWNER/forgeos
```

Built with [BlueBuild](https://blue-build.org/). Licensed Apache-2.0 (build config); included software keeps its own licenses.
