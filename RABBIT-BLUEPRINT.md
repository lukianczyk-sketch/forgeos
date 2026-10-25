# RABBIT BLUEPRINT — Job 3: "Clean Sweep" upgrade (ForgeOS security app)

Owner: RL Forge Works (Robert). Written by Claude 2026-10-22, updated 2026-10-23. **Rabbit Team writes all code; Claude reviews every step.** Do ONE step, write the step report in PROGRESS.md, then STOP.
Everything must be free (open-source, from Fedora's signed repos). Do not download or install programs on the PC. Do not use `curl | sh`.

## IMPORTANT — this is an UPGRADE of Clean Sweep v1
The repo already has Clean Sweep v1. **Keep these names** (do not create new `forgeos-clean-sweep` files):
- `files/system/usr/bin/forgeos-cleansweep` (the engine, runs as root) — upgrade it into the subcommand tool below.
- `files/system/usr/bin/forgeos-cleansweep-gui` (the window people click) — upgrade it to the 3-button window.
- `files/system/usr/share/applications/forgeos-cleansweep.desktop` — keep it (name "Clean Sweep").
- `files/scripts/forgeos-setup.sh` already makes the tools executable — extend it, don't replace it.
Read v1 first and keep what already works (signed-image rebase, `rpm-ostree reset`, offline step, quarantine-not-delete).

## What Clean Sweep does (Robert's words)
"If a virus, trojan or anything bad gets onto ForgeOS, Clean Sweep wipes the system clean."
Robert picked **option C**, which has three buttons:
1. **Scan Now** finds threats and quarantines bad files.
2. **System Reset** (the normal fix) returns the system to factory state and **keeps personal files**.
3. **Full Wipe** (worst case) erases everything, personal files included. It asks twice before it runs.

## Verified free tools (re-checked 2026-10-23, packages.fedoraproject.org)
| Tool | Fedora package(s) | Version F43/F44/F45 | Catches |
|---|---|---|---|
| ClamAV | `clamav`, `clamav-freshclam` | 1.4.6 (Fedora-signed; still the newest in every Fedora release) | viruses, trojans, worms |
| rkhunter | `rkhunter` | 1.4.6 | rootkits, backdoors |
| chkrootkit | `chkrootkit` | 0.58 | 70+ known rootkits |
| ostree / rpm-ostree | already in base | — | core-image integrity + /etc changes |

Use Fedora's packages, not upstream tarballs: they are signed and get updates automatically with each image rebuild.

## Key facts about ForgeOS (Fedora Atomic) that the design relies on
- `/usr` is read-only and comes from the signed image, so we **verify** it instead of scanning it.
- The factory `/etc` defaults are in `/usr/etc`. `ostree admin config-diff` lists every file in `/etc` that was **M**odified, **A**dded, or **D**eleted.
- `rpm-ostree reset` removes all layered packages, overrides, and initramfs changes.
- Malware that survives on Linux usually hides in "startup spots": `/etc/systemd/system`, `/etc/cron*`, `/etc/profile.d`, `/etc/ld.so.preload`, `~/.config/autostart`, `~/.config/systemd/user`, `~/.bashrc`, `~/.profile`, and user crontabs. System Reset must clean **all** of these.

## Locations
- Engine: `/usr/bin/forgeos-cleansweep` (bash, `set -euo pipefail`, shellcheck clean). Subcommands: `scan`, `quarantine`, `reset-system`, `full-wipe`.
- Window: `/usr/bin/forgeos-cleansweep-gui`
- Quarantine: `/var/lib/forgeos/quarantine/` (root:root, mode 0700; quarantined files chmod 000)
- Backups of anything removed by a reset: `/var/lib/forgeos/clean-sweep-backup/<YYYYMMDD-HHMMSS>/`
- Logs/reports: `/var/log/forgeos/clean-sweep/` plus a copy for the user at `~/.local/state/forgeos/clean-sweep/last-report.txt`
- Every destructive action needs root through `pkexec` and has a `--dry-run` that prints exactly what it would do and changes nothing.

---

## Step 1 — Research (no code)
Confirm, and write the results in PROGRESS.md:
- Which Fedora version our Bazzite base uses right now, and whether `clamav`, `clamav-freshclam`, `rkhunter`, `chkrootkit` install there with no conflicts. Also check whether Bazzite already ships any of them.
- The exact output format of `ostree admin config-diff` (M/A/D lines).
- The `rpm-ostree status --json` field that shows the booted image is signature-verified (an `ostree-image-signed:` origin).
- The safe flags for automated runs: `rkhunter --check --sk --rwo --nocolors`, `chkrootkit -q`, `clamscan -r -i --move=`.
- A short list of what v1 (`forgeos-cleansweep`) already does, and which parts Steps 3–7 will reuse.
STOP.

## Step 2 — Put the tools in the image
- `recipes/recipe.yml` → the existing `dnf` module (next to `kde-connect`): add `clamav`, `clamav-freshclam`, `rkhunter`, `chkrootkit`.
- **Order fix (Claude, 2026-10-23):** move the `type: script` module (install-ollama.sh + forgeos-setup.sh) to just AFTER the `dnf` module, so the packages exist when forgeos-setup.sh runs. Don't change anything else in those modules.
- In `files/scripts/forgeos-setup.sh`, enable `clamav-freshclam.service` so virus signatures update daily (the database lives in `/var/lib/clamav`, which is writable).
- **rkhunter baseline must live in /usr** (image `/var` is only copied on first install, so a /var baseline goes stale after every update and causes false alarms). Add `files/system/etc/rkhunter.d/forgeos.conf` with `DBDIR=/usr/share/forgeos/rkhunter-db`. In forgeos-setup.sh: `mkdir -p /usr/share/forgeos/rkhunter-db`, copy the stock db files from `/var/lib/rkhunter/db/` into it, then run `rkhunter --propupd` so the baseline matches the clean image.
STOP.

## Step 3 — `forgeos-cleansweep scan`
**Split into 3a / 3b / 3c (Claude, 2026-10-23):** the local model looped (36k tokens) trying to write all of Step 3 at once. Do ONE sub-step per Cline task:
- **3a** — Structure: wrap the v1 body in `legacy_sweep()` (no args = run it, so the GUI keeps working until Step 7); add `set -euo pipefail`; argument parsing (`scan`, `--dry-run`, anything else → usage, exit 3); shared helpers (`log`, paths, `mkdir` of log/quarantine dirs); the **core check** function only.
- **3b** — Scanners: clamscan / rkhunter / chkrootkit functions, quarantine chmod 000 + `quarantine.log` lines.
- **3c** — Startup-spot audit, the plain-English report (+ user copy via `$PKEXEC_UID`), final exit codes.
- Runs, in order: (1) **core check**, which verifies the booted deployment is signed and runs `ostree admin config-diff`, flagging any Added/Modified file in a startup spot; (2) **clamscan** of `/home`, `/var` (skip `/var/lib/clamav`, the quarantine, and `/var/lib/containers/storage` overlay noise), `/etc`, `/tmp`, `/var/tmp`; (3) **rkhunter**; (4) **chkrootkit**; (5) a **startup-spot audit** listing every autostart entry, user systemd unit, cron job, and `ld.so.preload`.
- Infected files are moved to quarantine with `--move` and then chmod 000. Write a `quarantine.log` line for each file: date, original path, sha256, and threat name.
- Report: one plain-English summary at the top ("All clear" / "3 threats found and locked away" / "System files changed — System Reset recommended"), followed by the details.
- Exit codes: 0 = clean, 1 = threats quarantined, 2 = system tampering found (reset recommended), 3 = tool error.
- `--dry-run` scans but moves nothing.
STOP.

## Step 4 — Quarantine tools
**Split into 4a / 4b (Claude, 2026-10-23):** one sub-step per Cline task.
- **4a** — quarantine.log gets 3 more columns (moved path, original mode, original owner uid:gid) so files can be put back; argument parsing for `quarantine list|restore|delete` + `--yes`; `quarantine list` only (restore/delete stubs exit 3).
- **4b** — `restore <id>` (sha256 must still match, never overwrite an existing file, put back mode + owner) and `delete <id|all>`. Both ask first; `--yes` skips the question (the GUI asks in its own window, Step 7). No terminal and no `--yes` → refuse, exit 3.
- **4b split (Claude, 2026-10-23):** 4b-1 = shared `confirm()` + `quarantine_find()` helpers + `restore`; 4b-2 = `delete <id|all>`.
- ID = the quarantined file's path inside the quarantine folder, e.g. `20261023-101500/eicar.com`.
- `forgeos-cleansweep quarantine list`
- `forgeos-cleansweep quarantine restore <id>`: asks first and warns that the file was flagged.
- `forgeos-cleansweep quarantine delete <id|all>`: asks first.
STOP.

## Step 5 — `forgeos-cleansweep reset-system` (keeps personal files)
Order matters. Log every action and back up before removing anything:
1. Run a scan first, so threats in personal files get quarantined.
2. `rpm-ostree reset` (removes layered packages and overrides).
3. **Restore /etc:** for each `M` file, back it up and copy the factory version from `/usr/etc`. For each `A` file, move it to the backup folder. For each `D` file, copy it back from `/usr/etc`. Skip only this keep-list so the PC still works afterward: `/etc/machine-id`, `/etc/passwd`, `/etc/group`, `/etc/shadow`, `/etc/gshadow`, `/etc/subuid`, `/etc/subgid`, `/etc/hostname`, `/etc/NetworkManager/system-connections/*` (Wi-Fi), `/etc/fstab`, `/etc/crypttab`. Exception: if a keep-list file has an unknown UID 0 user or a changed root password hash, flag it in the report.
4. **Clean each user's startup spots** (personal files untouched): move `~/.config/autostart/*` (except ForgeOS's own entries), `~/.config/systemd/user/*`, and user crontabs to the backup folder. Reset `~/.bashrc`, `~/.bash_profile`, and `~/.profile` from `/etc/skel` (back up the old ones).
5. Clear `/etc/ld.so.preload`, `/var/spool/cron/*`, `/tmp`, and `/var/tmp`.
6. Run `flatpak repair --system` and then `flatpak update -y` to re-verify the apps.
7. Pull a fresh **signed** ForgeOS image (reuse v1's `ostree-image-signed:` rebase logic), falling back to a redeploy of the current signed image if there is no update.
8. Show the summary, then reboot after the user clicks OK.
`--dry-run` prints the full plan and changes nothing.

**Split into small Cline steps (Claude, 2026-10-24):**
- **5a-1:** parse `reset-system [--dry-run] [--yes]`; `--dry-run` prints the /etc part of the plan (keep-list, M/A/D actions) + keep-list warnings. Real run = stub, exit 3.
- **5a-2:** dry-run plan for the rest: per-user startup spots, clears, flatpak, signed image ref, reboot.
- **5b:** real run, part 1: `confirm()`, backup folder, `rpm-ostree reset`, /etc restore, then `systemctl preset-all` (re-enables factory services whose `.wants` links were in /etc).
- **5c:** real run, part 2: per-user startup spots + dotfiles from /etc/skel, clear ld.so.preload / spool cron / tmp.
- **5d:** real run, part 3: scan first, flatpak repair + update, signed rebase (or `rpm-ostree upgrade` when already on the signed ref), summary, reboot after OK. **DONE (Step 5 complete).**
- Backup folder: `/var/lib/forgeos/reset-backup/<STAMP>/` (mode 700); each file keeps its full path inside it.
- Keep-list (Claude added safe extras so language, time and keyboard survive): machine-id, passwd, group, shadow, gshadow, subuid, subgid, passwd-, group-, shadow-, gshadow-, .pwd.lock, .updated, hostname, fstab, crypttab, locale.conf, vconsole.conf, localtime, adjtime, X11/xorg.conf.d/00-keyboard.conf, NetworkManager/system-connections/*, resolv.conf, and the parent folders NetworkManager, NetworkManager/system-connections, X11, X11/xorg.conf.d (config-diff can list a whole added folder as one line). Done in 5a-1.
STOP.

## Step 6 — `forgeos-cleansweep full-wipe` (erases personal files)
- Confirmation 1: a Yes/No dialog: "This erases ALL your files, apps and settings. It cannot be undone."
- Confirmation 2: the user must type `WIPE`.
- Then: run all of Step 5 (no backups of user data), delete every regular user's home contents, recreate them from `/etc/skel`, remove user Flatpak data (`~/.var/app`), empty the quarantine, and reboot.
- Never runs without both confirmations. `--dry-run` is required in all tests.

### Step 6 split (Claude, 2026-10-24)
- Command forms (exact):
  - `full-wipe --dry-run` → plan only, changes nothing.
  - `full-wipe` (terminal) → asks Yes/No, then the user must type `WIPE` (exact, capitals).
  - `full-wipe --yes WIPE` (GUI) → the Clean Sweep window shows its own Yes/No box and a text box; it only passes the word `WIPE` after the user typed it. `--yes` without `WIPE` right after it = usage error, exit 3. No other forms.
- Full wipe = System Reset steps 1-3 and 5-7 (step 4 "user startup spots" is skipped — the homes are erased anyway), then erase homes, then empty quarantine, then restart.
- Safety: a home is only erased if it is a real folder (not a symlink) under `/home/` or `/var/home/`, owned by a regular user (UID 1000-59999). Anything else → skipped with a note. `rm` always uses `--one-file-system`.
- 6a: argument parsing + usage line + `full-wipe --dry-run` plan (reset plan moved into `reset_system_plan` so both commands share it). Real run = stub, exit 3.
- 6b: the two confirmations + the real run of Part 1 (System Reset without step 4).
- 6c: erase each home's contents, fresh copy from /etc/skel (as that user), expire password, empty quarantine, restart.
STOP.

## Step 7 — The app people click
- Keep `/usr/share/applications/forgeos-cleansweep.desktop`, named "Clean Sweep", shield icon from Breeze (`security-high` is fine).
- `forgeos-cleansweep-gui` main window (reuse the kdialog → zenity → tty helpers from Job 1, with the `say() … || true` fix) has 3 buttons: **Scan Now**, **System Reset**, **Full Wipe**. Show a progress bar during scans (kdialog D-Bus progressbar, same as Job 1).
- **Auto-protect:** a `forgeos-cleansweep.timer` + `forgeos-cleansweep.service` in `files/system/usr/lib/systemd/system/` runs a weekly scan (Sunday 3 AM, `Persistent=true`). If it finds a threat, it sends a desktop notification: "Clean Sweep found a threat and locked it away — open Clean Sweep?" If the exit code is 2, the notification says "System Reset recommended".
STOP.

## Step 8 — Tests (GitHub Actions, extend tests.yml)
- shellcheck both scripts.
- `tests/test-clean-sweep.sh` with fake `clamscan`/`rkhunter`/`chkrootkit`/`ostree`/`rpm-ostree`/`pkexec`/`kdialog` on PATH. Cases: clean system → exit 0; infected file → quarantined, logged, exit 1; config-diff shows `A    ld.so.preload` (paths are relative to /etc) → exit 2; reset-system --dry-run plan respects the keep-list; full-wipe refuses without `WIPE`; quarantine restore/delete.
- One real ClamAV test in CI: install `clamav`, create the standard harmless **EICAR test file**, and confirm the scan catches and quarantines it.
- Tests must NEVER run reset-system or full-wipe without `--dry-run`.
STOP. Claude does a final review → tag release.

## Honest limits (for the About box)
No scanner catches 100% of threats. ForgeOS's locked, signed core is the main protection, and Clean Sweep is the cleanup crew. System Reset is guaranteed to restore the system, but it cannot guarantee that every personal file is clean (they are scanned, not replaced). Full Wipe is the guaranteed clean slate.
