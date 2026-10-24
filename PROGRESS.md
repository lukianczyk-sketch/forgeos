# ForgeOS — Progress log (Job 3: Clean Sweep)

## Step 1 — Research (no code) — 2026-10-23

What I did:
- Read the three v1 files Robert named: `files/system/usr/bin/forgeos-cleansweep`, `files/system/usr/bin/forgeos-cleansweep-gui`, `files/scripts/forgeos-setup.sh`. No other research or fetching (per instruction — the facts below are Claude's verified results, re-checked 2026-10-23).
- Wrote this report only. No code written, no files changed besides PROGRESS.md.

### 1. Bazzite base + tool availability
- Bazzite stable = **Fedora 44** (Bazzite 45 / F45 has only been in testing since 2026-10-15).
- `clamav` (1.4.6-1.fc44), `rkhunter`, and `chkrootkit` are all available in the Fedora 44 repos, so Step 2's dnf-module additions should install on our base without conflicts.
- Bazzite does **not** ship any of them (none appear in its spec_files) — no "already installed" surprises expected.
- Actual install behavior will be confirmed by the bluebuild run in Step 2 (nothing has been installed yet, so this is not claimed as tested).

### 2. `ostree admin config-diff` output format
- One line per file: a letter **M**/A/D, spaces, then the path **relative to /etc**. Examples: `M    shadow`, `A    ld.so.preload`.
- Code must prepend `/etc/` before using the path.

### 3. Signed-image check (booted deployment)
- `rpm-ostree status --json` → the booted deployment's `"container-image-reference"` starts with `ostree-image-signed:`.
- v1 already does exactly this (`forgeos-cleansweep`, incl. converting an `ostree-unverified-registry:` reference to its signed form before rebasing).

### 4. Safe flags for automated runs
- rkhunter: `rkhunter --cronjob --rwo` (implies `--check --sk --nocolors`, i.e. the set listed in the blueprint).
- chkrootkit: `chkrootkit -q`.
- clamscan: `clamscan -r -i --move=DIR --exclude-dir=REGEX`. Exit codes: 0 = clean, 1 = virus found, 2 = error (these map onto Step 3's exit-code design).

### 5. What v1 already does — and what Steps 3/5/7 reuse
v1 (`forgeos-cleansweep`, one monolithic run as root):
1. Root check; timestamped quarantine dir `/var/lib/forgeos/quarantine/<STAMP>` (0700) + log `/var/log/forgeos-cleansweep-<STAMP>.log`; `quarantine()` helper moves files while keeping their full path inside the quarantine dir.
2. Signed rebase: reads the booted deployment's `container-image-reference` from `rpm-ostree status --json`, forces the `ostree-image-signed:` form, rebases to stage a fresh signed image (while still online).
3. Goes offline: `nmcli networking off`.
4. `rpm-ostree cancel` + `rpm-ostree reset` (removes layered packages/overrides).
5. /etc startup-spot cleanup vs the factory copies in `/usr/etc`: quarantines added files, restores changed ones from `/usr/etc` — systemd/system, xdg/autostart, profile.d, sudoers.d, sshd_config.d, cron dirs, yum.repos.d, udev/rules.d, plus `ld.so.preload`, `rc.local`, `crontab`; clears `/var/spool/cron`.
6. Per-user (UID 1000–59999): quarantines `~/.config/autostart`, `~/.config/systemd/user`, `~/.ssh/authorized_keys`, plasma env/shutdown scripts; `passwd -e` to force a new password at next login; also `/root/.ssh/authorized_keys`.
7. Flatpak: `flatpak override --reset` + `flatpak uninstall --unused`.
8. ClamAV (if present): `clamscan -r -i --move=<QUAR>/infected /home`.

Reuse map:
- **Step 3 (`scan`)**: the signed check from items 2/3; clamscan flags and exit codes from fact 4 (plus `--exclude-dir` for the skip list); quarantine dir + `quarantine()` helper + log/report writing.
- **Step 5 (`reset-system`)**: the signed rebase (item 2 — blueprint reset step 7 says reuse it explicitly), `rpm-ostree reset` (item 4), /etc startup-spot quarantine/restore mechanics (item 5, driven by config-diff instead of v1's hardcoded dir list), per-user autostart/systemd/cron cleanup + `passwd -e` (item 6), flatpak override reset (item 7).
- **Step 7 (GUI)**: the kdialog→zenity fallback helpers and pkexec pattern from `forgeos-cleansweep-gui`; v1's log paths for the "check the log" message.

What I ran + output:
- No shell commands were needed for this research step; facts above are Claude's verified results (re-checked 2026-10-23) and direct reads of the three v1 files listed at the top.

Questions / unsure about:
- Note for Claude: blueprint Step 8 test case says config-diff shows `A /etc/ld.so.preload`, but per fact 2 the real line is `A    ld.so.preload` (path relative to /etc). The fake ostree in tests should emit that form.
- Design note for the record: v1 uses `set -uo pipefail` (no `-e`); the blueprint wants `set -euo pipefail` for the new engine, so Step 3 will need care with commands that legitimately return non-zero (e.g. clamscan exit 1).

STATUS: WAITING FOR CLAUDE REVIEW
### Claude review — Step 1 — 2026-10-23
- APPROVED. All five research items match Claude's checks (Bazzite stable = F44; Fedora clamav 1.4.6-1.fc44; config-diff paths relative to /etc per the ostree man page; `container-image-reference` signed prefix; rkhunter/chkrootkit/clamscan flags + exit codes per their man pages).
- v1 summary verified line-by-line against `forgeos-cleansweep` and `forgeos-cleansweep-gui` (kdialog→zenity `ask()`/`info()`, pkexec call).
- Fixed: blueprint Step 8 example now reads `A    ld.so.preload`.
- Agreed on `set -euo pipefail`: Step 3 must capture expected non-zero exits (`clamscan ... || rc=$?`) instead of letting them abort.
- Note: first Cline run looped after a context overflow and was cancelled; this report came from the second run.
- Next: Step 2.

## Step 2 — Put the tools in the image — 2026-10-23
Files changed: recipes/recipe.yml, files/scripts/forgeos-setup.sh, files/system/etc/rkhunter.d/forgeos.conf (new)
What I did (Rabbit Team / Cline):
- dnf module: added clamav, clamav-freshclam, rkhunter, chkrootkit next to kde-connect.
- Moved the script module (install-ollama.sh + forgeos-setup.sh) to just after the dnf module (order fix).
- forgeos-setup.sh: `systemctl enable clamav-freshclam.service`; created /usr/share/forgeos/rkhunter-db, copied the stock db from /var/lib/rkhunter/db/, ran `rkhunter --propupd`.
- New /etc/rkhunter.d/forgeos.conf: `DBDIR=/usr/share/forgeos/rkhunter-db`.
What I ran + output: nothing run (no build/install allowed on the PC).
Questions / unsure about: none
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 2 — 2026-10-23
- APPROVED. Diff matches the blueprint exactly; existing setup lines kept; the files module (which installs /etc/rkhunter.d/forgeos.conf) still runs first, so `rkhunter --propupd` writes the baseline into /usr/share/forgeos/rkhunter-db.
- Checked on Linux: YAML parses, `bash -n` clean on forgeos-setup.sh, CRLF fixed to LF.
- Cline was cancelled after the edits (its last command was only a line-ending check); Claude wrote this report from the verified diff.
- Real proof = the bluebuild run after push (confirms the packages install on Fedora 44 with no conflicts and propupd succeeds). Then Step 3.

## Step 3a — Engine structure — 2026-10-23
Files changed: files/system/usr/bin/forgeos-cleansweep
What Rabbit Team / Cline did (3 saved edits):
- v1 body wrapped in `legacy_sweep()` (first line `set +e`); no arguments still runs it, so the GUI (`pkexec /usr/bin/forgeos-cleansweep`) keeps working until Step 7.
- `set -euo pipefail`; args `scan` / `--dry-run` / anything else → usage + exit 3.
- Helpers: DRY_RUN, STAMP, LOG_DIR=/var/log/forgeos/clean-sweep, QUAR_DIR=/var/lib/forgeos/quarantine (chmod 700), LOG_FILE, log().
- `core_check()`: signed check via `rpm-ostree status --json | jq` on `container-image-reference`; `ostree admin config-diff` A/M lines in startup spots → TAMPER=1.
- `run_scan()`: exit 2 if TAMPER, else 0.
- Cline got stuck in a PowerShell quoting loop while smoke-testing on Windows and was cancelled; Claude wrote this report.
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 3a — 2026-10-23
- APPROVED with fixes (Claude applied):
  1. `--dry-run` on its own ran the destructive v1 sweep → now means `scan` (move nothing).
  2. Not-root exit was 1 (= "threats quarantined") → now 3 (tool error).
  3. `core_check || exit 3` made explicit instead of relying on `set -e`.
  4. Signed check falls back to `rpm-ostree status --booted` text when jq is missing.
  5. Startup spots extended: `/etc/xdg/autostart/*`, `/etc/rc.local`, `/etc/rc.d/*`, `/etc/udev/rules.d/*` (common persistence spots; Step 5 already restores every A/M file in /etc).
  6. CRLF → LF.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean.
- Sandbox tests (fake ostree / rpm-ostree / id, paths moved to a temp dir): clean diff → 0; `A    ld.so.preload` → 2; `A    udev/rules.d/99-evil.rules` → 2; empty diff → 0; config-diff fails → 3; `--dry-run` alone → scan (2 on tampered); `--bogus` → 3; non-root → 3; quarantine dir mode 700; per-run log file written.
- v1 sweep NOT executed (destructive); syntax-checked only.
- Next: Step 3b (clamscan / rkhunter / chkrootkit + quarantine.log).
