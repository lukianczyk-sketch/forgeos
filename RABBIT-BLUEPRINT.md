# RABBIT BLUEPRINT — Job 5: "Undo Button" (ForgeOS)

Owner: RL Forge Works (Robert). Written by Claude 2026-10-25. **Rabbit Team writes all code; Claude reviews every step.** Do ONE step, write the step report in PROGRESS.md, then STOP.
Everything must be free (open-source, from Fedora's signed repos). Do not download or install programs on the PC.

## What the Undo Button does (Robert's pitch: "what Windows/Linux should have built in")
"Deleted or ruined a file? Click Undo Button, pick the time, get it back. Bad system update? One click goes back."
1. **Automatic snapshots** of every user's home folder, every hour, with no setup and no password.
2. **Get back an older version** of any file or folder (from the Undo Button window or by right-clicking a file in Dolphin).
3. **Undo the last system update** (Fedora Atomic rollback, already built into the base).

## Verified facts (Claude, 2026-10-25: Bazzite source pulled today + real snapper/btrfs test)
- Bazzite stable = Fedora 44. It ships `snapper` (Fedora 44: **0.13.0**) and `btrfs-assistant` but snapshots are **OFF** by default.
- Bazzite's `ujust configure-snapshots enable` (`/usr/libexec/bazzite-snapper-config`) creates a snapper config **named `root` for `/var/home`**, but sets every limit to 0 and turns the timeline timer OFF, so it never takes automatic snapshots. ForgeOS keeps the **same config name `root`** so `ujust configure-snapshots status|disable|wipe` and Btrfs Assistant keep working.
- `ujust configure-snapshots status` reports "enable" when `/etc/sysconfig/snapper` has `SNAPPER_CONFIGS="root"` (snapper's `create-config` writes that line).
- On ForgeOS, `/home` is a symlink to `/var/home`, and `/var/home` is a btrfs subvolume. Snapshots live in `/var/home/.snapshots/<N>/snapshot/` (read-only), and each `<N>/info.xml` holds `<date>` (in **UTC**), `<description>` and `<cleanup>`.
- `ALLOW_GROUPS=wheel SYNC_ACL=yes` gives the wheel group (the PC's admins, which includes the first user) read access to `.snapshots` through an ACL. Tested: a group member can read their own old files, which can't be changed. A non-member gets "Permission denied". Users' homes are 0700, so nobody can read another user's old files.
- A wheel user can run `snapper -c root create ...` with **no password** (through snapperd/D-Bus). Tested. A non-member gets "No permissions."
- **Disk safety:** `FREE_LIMIT=0.2` makes cleanup delete the oldest snapshots whenever free space falls below 20%, with **no btrfs quota**. It only works when the limits are written as **ranges** (e.g. `TIMELINE_LIMIT_HOURLY=1-12`). Tested on a full btrfs disk: number and timeline cleanup both freed space. The warning "quota not working (qgroup not set)" is harmless.
- `snapper-cleanup.timer` normally runs once a day (`OnUnitActiveSec=1d`). ForgeOS makes it hourly with a drop-in so a deleted 100 GB game frees its space within about an hour.
- `snapper delete 1-999999` FAILS if any number in the range is missing. Delete by listing the numbers: `snapper --csvout -c root list --columns number`, skip `0` and the header, then `snapper -c root delete --sync <numbers...>`.
- Clean Sweep's ClamAV scan covers `/var`, so it would ALSO crawl every snapshot copy of `/var/home` (very slow). It must skip `^/var/home/\.snapshots`. Full Wipe must delete all home snapshots, or the "erased" files can still be recovered.

## Files (all new unless marked)
| File | What |
|---|---|
| `files/system/usr/libexec/forgeos-undo-setup` | root, first boot: turns snapshots on (Step 1) |
| `files/system/usr/lib/systemd/system/forgeos-undo-setup.service` | runs it once (Step 1) |
| `files/system/usr/lib/systemd/system/snapper-cleanup.timer.d/forgeos-hourly.conf` | cleanup every hour (Step 1) |
| `files/scripts/forgeos-setup.sh` (EDIT) | chmod + enable units (Step 1) |
| `recipes/recipe.yml` (EDIT) | add `jq` package (Step 1) |
| `files/system/usr/bin/forgeos-undo` | engine, runs as the normal user (Step 2) |
| `files/system/usr/bin/forgeos-undo-gui` + `files/system/usr/share/applications/forgeos-undo.desktop` | the window (Step 3) |
| `files/system/usr/share/kio/servicemenus/forgeos-undo.desktop` | Dolphin right-click "Get back an older version" (Step 3) |
| `files/system/usr/bin/forgeos-cleansweep` (EDIT) | skip snapshots in scan; Full Wipe deletes them (Step 4) |
| `tests/test-undo.sh` + `.github/workflows/tests.yml` (EDIT) | tests (Step 5) |

## Steps (Claude gives ONE exact Cline prompt per step, with all code inline)
1. **Turn it on:** setup script + service + hourly-cleanup drop-in + forgeos-setup.sh + jq. STOP.
2. **Engine `forgeos-undo`:** `status`, `versions <path>`, `restore <N> <path>` (never overwrites; it restores as "name (from DATE).ext"; a deleted file goes back to its old name; the restored copy is checked with clamscan when present), `snapshot-now`, `updates`, `undo-update`. STOP.
3. **Window + right-click:** kdialog window (Get back a file / Get back a folder / Undo last system update / Take a snapshot now / About), menu entry, Dolphin service menu. STOP.
4. **Clean Sweep fixes:** scan skips snapshots; Full Wipe Part 2b deletes all home snapshots. STOP.
5. **Tests:** fake snapshot tree + fake snapper/rpm-ostree/clamscan; plus one real btrfs+snapper test in CI. STOP. Claude does a final review, then tags v0.6.0.

## Honest limits (for the About box)
Snapshots are kept on the same drive. They undo mistakes, deleted files and ransomware damage, but they do NOT protect against a dead drive. Use Pika Backup to a USB drive for that. Only folders inside home are covered. The system itself is covered by system rollback.

## PROGRESS.md report format
```
## Step N — <title> — <date>
What I did:
- ...
Files changed:
- ...
STATUS: WAITING FOR CLAUDE REVIEW
```
