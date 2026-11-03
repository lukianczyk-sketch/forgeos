# RABBIT BLUEPRINT — Job 13e: Install & Switch

Owner: Robert (RL Forge Works). Senior engineer / reviewer: Claude. Coder: Rabbit Team (Cline).
Claude already wrote and tested a working prototype (tests A-H pass). Each step prompt gives you the EXACT
file contents. Copy them exactly. Do not research, do not "improve", do not run commands.

## What it does
ForgeOS goes on ANOTHER PC next to Windows 11 (Windows on one drive, ForgeOS on a second drive) and switching is one click.
1. **Installer USB**: GitHub workflow `iso.yml` builds forgeos.iso and forgeos-nvidia.iso (free, from our signed images,
   JasonN3/build-container-installer v1.5.0, Fedora 44 Kinoite, Universal Blue Secure Boot key, password universalblue).
   Run it from the Actions tab or by pushing a version tag; download the ISO from the run's Artifacts.
2. **Restart into Windows** (ForgeOS): desktop icon + "Windows & ForgeOS" window. Root helper forgeos-switch-boot
   (polkit: no password for the person at the screen) finds "Windows Boot Manager" (or bootmgfw.efi) with efibootmgr and
   sets it as the NEXT start-up only (`efibootmgr -n`); then KDE's normal restart. The normal start-up order never changes.
3. **Restart into ForgeOS** (Windows): forgeos-switch-winsetup (PC password) writes 2 files on the Windows drive:
   Users\Public\Desktop\Restart into ForgeOS.cmd + Users\Public\Documents\ForgeOS\restart-into-forgeos.ps1 (Windows line
   endings). The script asks for admin (UAC), finds the ForgeOS entry (\EFI\fedora\ or "Fedora") with `bcdedit /enum firmware`,
   sets `bcdedit /set {fwbootmgr} bootsequence {id}` (one time) and restarts. Refuses BitLocker drives and a Windows that was
   not fully shut down (Fast Startup / hibernate).
4. **First run** (autostart, once): if Windows is on the PC, puts the "Restart into Windows" icon on the desktop and offers
   to set up the Windows button. "Show both systems in the start-up menu" = Bazzite's `ujust regenerate-grub` in a terminal.
5. Forge Helper: new tool `switch_windows` + help card "Windows and ForgeOS on one PC".

## Files
- files/system/usr/bin/forgeos-switch (status | windows --yes | windows-button [remove] | boot-menu | first-run)
- files/system/usr/bin/forgeos-switch-gui (--windows | --first-run)
- files/system/usr/libexec/forgeos-switch-boot (list | windows-next | clear-next), forgeos-switch-winsetup (find | install | remove)
- files/system/usr/share/forgeos/switch/restart-into-forgeos.ps1, "Restart into ForgeOS.cmd"
- files/system/usr/share/polkit-1/actions/org.forgeos.switch.policy
- files/system/usr/share/applications/forgeos-switch.desktop, forgeos-restart-windows.desktop; files/system/etc/xdg/autostart/forgeos-switch-firstrun.desktop
- files/system/usr/share/forgeos/helper/help/windows-forgeos.md; .github/workflows/iso.yml
- edits: forgeos-setup.sh (chmod), common-modules.yml (efibootmgr), helperlib tools/looks/actions/rulelist, tools-2.jsonl,
  tests/test-helper-ai.sh (G3), tests/test-autopilot-files.sh (Q1), .github/workflows/tests.yml
- tests/switch-fakes.sh, switch-pwsh.sh, test-switch.sh (A-C), test-switch-win.sh (D-F), test-switch-gui.sh (G), test-switch-files.sh (H)

## Steps (one Cline task each)
1. bin/forgeos-switch, libexec/forgeos-switch-boot, libexec/forgeos-switch-winsetup
2. bin/forgeos-switch-gui, the 2 Windows files, polkit policy, 3 desktop files, help card, iso.yml
3. edits: setup, recipe, Forge Helper (6), test-autopilot-files.sh
4. tests/switch-fakes.sh, switch-pwsh.sh, test-switch.sh
5. tests/test-switch-win.sh, test-switch-gui.sh, test-switch-files.sh + CI step

## Rules for every step
- Copy the given content exactly. Spaces only, no tab characters. One newline at the end of every file.
- Do NOT double any backslash. Do NOT research, run commands, verify or test.
- Add one line to PROGRESS.md as the step prompt says, then stop.

## Honest limits
The ISO is several GB; if GitHub's free runner runs out of disk space, the backup is the README path (install Bazzite,
then one rebase command). The Windows script reads English bcdedit output (other Windows languages: use the start-up menu).
Machines without UEFI can't switch by button (start-up menu only). Windows Boot Manager naming differs on a few boards
(the helper also looks for bootmgfw.efi).
