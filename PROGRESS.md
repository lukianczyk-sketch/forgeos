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

## Step 3b-1 — Virus scan (clamscan) — 2026-10-23
Files changed: files/system/usr/bin/forgeos-cleansweep
What Rabbit Team / Cline did (3 edits, one file):
- `THREATS=0` added next to `TAMPER=0`.
- New `run_clamscan()` placed right after `core_check()`:
  - `rc=0; clamscan ... || rc=$?` so the expected non-zero exits survive `set -e`.
  - Scans `/home /var /etc /tmp /var/tmp` with `-r -i --no-summary`; skips `^/var/lib/clamav`, `^/var/lib/forgeos/quarantine`, `^/var/lib/containers/storage`.
  - DRY_RUN=0: `mkdir -p "$QUAR_DIR/$STAMP"` + chmod 700 first, then `--move="$QUAR_DIR/$STAMP"`. DRY_RUN=1: no `--move`, nothing moved.
  - Full clamscan output saved to `$LOG_DIR/clamscan-$STAMP.txt`.
  - Two passes over that file (order-independent): pass 1 counts every `... FOUND` line into THREATS and remembers path→threat name; pass 2 handles each `moved to '...'` line — chmod 000 the moved file, sha256sum it, append one tab-separated line to `$QUAR_DIR/quarantine.log`: date, original path, sha256, threat name.
  - rc=2 → log "ERROR: virus scan failed", return 3; otherwise return 0. Also returns 3 if clamscan is missing (same guard style as core_check's ostree check).
- `run_scan()`: `run_clamscan || exit 3` right after `core_check`; then TAMPER=1 → exit 2 still wins, THREATS>0 → exit 1. Updated the two now-stale "scanners land in Step 3b" comment/log lines (clamscan has landed; rkhunter/chkrootkit still pending).
What I ran + output: nothing run — per instruction no test commands this step, so this is NOT claimed as tested or shellcheck-clean.
Questions / unsure about: none
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 3b-1 — 2026-10-23
- APPROVED with fixes (Claude applied):
  1. Double scanning: on ForgeOS /home → /var/home and /var/tmp is inside /var, so `/home /var … /var/tmp` scanned the same files twice (double-counted threats in dry-run). Targets are now `/var /etc /tmp`, plus `/home` only if it is a real directory (not a symlink).
  2. clamscan returns 2 for ANY error, even when it also found threats. A scan that found threats now still reports them (exit 1) with a warning; only "errored and found nothing" is a tool error (3).
  3. sha256 is taken BEFORE chmod 000.
  4. quarantine.log dates are now sortable (`YYYY-MM-DD HH:MM:SS`).
  5. CRLF → LF.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean.
- Sandbox tests (fake clamscan / ostree / rpm-ostree / id): clean → 0; infected → 1, file moved, chmod 000, quarantine.log line (date, path, sha256, threat); error only → 3; infected + error → 1; `--dry-run` infected → 1 and nothing moved; clamscan missing → 3.
- Cline was cancelled after writing its report (it started re-reading the file while Claude was fixing it).
- Next: Step 3b-2 (rkhunter + chkrootkit).

## Step 3b-2 — Rootkit checks (rkhunter + chkrootkit) — 2026-10-23
Files changed: files/system/usr/bin/forgeos-cleansweep
What Rabbit Team / Cline did (2 edits, one file):
- New `run_rkhunter()` placed right after `run_clamscan()`:
  - rkhunter missing → log ERROR + return 3 (same guard style as run_clamscan's clamscan check).
  - Runs `rkhunter --check --sk --rwo --nocolors`, full output saved to `$LOG_DIR/rkhunter-$STAMP.txt`, captured with `rc=0; ... || rc=$?` so set -e does not abort mid-check.
  - Counts lines starting with "Warning:" into local `n` (while-read loop, same style as run_clamscan's passes).
  - n>0 → log "Rootkit check: $n warning(s) — System Reset recommended." and set TAMPER=1; else log "Rootkit check (rkhunter): clean."; return 0.
- New `run_chkrootkit()` right after it, same pattern: missing → ERROR + return 3; runs `chkrootkit -q` saving output to `$LOG_DIR/chkrootkit-$STAMP.txt`; counts any line containing "INFECTED" into local `n`; n>0 → log "$n infected finding(s) — System Reset recommended." and set TAMPER=1, else log "Rootkit check (chkrootkit): clean."; return 0.
- Ordering note (deliberate choice, flagged for review): in both functions the rc check runs before the verdict logging, so an errored run (rc other than 0/1) reports only "ERROR: rootkit check failed" + return 3 and does not also print a clean/warning verdict from partial output. All specified behaviors are unchanged.
- `run_scan()`: added `run_rkhunter || exit 3` and `run_chkrootkit || exit 3` right after `run_clamscan || exit 3`; kept the existing order TAMPER=1 → exit 2, THREATS>0 → exit 1, else exit 0.
- Updated two now-stale lines in run_scan (same as Step 3b-1 did): the header comment (rkhunter/chkrootkit have landed; only the plain-English report is pending for Step 3c) and the final success log line (no longer says "land later in Step 3b").
What I ran + output: nothing run — per instruction no test commands this step, so this is NOT claimed as tested or shellcheck-clean.
Questions / unsure about: none
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 3b-2 — 2026-10-23
- APPROVED. Both functions match the prompt; exit order in run_scan() is right (tool error 3 → TAMPER 2 → THREATS 1 → 0).
- Claude touch-ups: fixed two stale comments/usage lines (clamscan targets; `scan` help text now lists all four checks); CRLF → LF.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean.
- Sandbox tests (fake rkhunter / chkrootkit / clamscan / ostree / rpm-ostree / id): both clean → 0; rkhunter "Warning:" line → 2; chkrootkit "INFECTED" line → 2; rkhunter exit 2 → 3; chkrootkit exit 5 → 3; chkrootkit missing → 3.
- Design note: any rkhunter warning recommends System Reset (exit 2). rkhunter can give false positives after updates, so the build-time `--propupd` baseline (Step 2) matters, and Step 3c's report must show the warning text so the user can judge.
- Next: Step 3c (startup-spot audit, plain-English report + user copy via $PKEXEC_UID, final exit codes).

## Step 3c-1 — Startup-spot audit (list only) — 2026-10-23
Files changed: files/system/usr/bin/forgeos-cleansweep
What Rabbit Team / Cline did (3 edits, one file):
- New `run_startup_audit()` placed right after `run_chkrootkit()`. It only LISTS things; it changes nothing. Writes `$LOG_DIR/startup-$STAMP.txt` with a heading line before each group:
  - "System autostart:" — every regular file in /etc/xdg/autostart/.
  - "System services/timers added by the admin:" — every *.service and *.timer file directly in /etc/systemd/system/ (subdirectories not listed).
  - "Cron jobs:" — /etc/crontab (if present), plus every regular file in /etc/cron.d/ and /var/spool/cron/.
  - "Preload (ld.so.preload):" — the contents of /etc/ld.so.preload if it exists and is not empty.
  - Then, for each real user from `getent passwd` with UID 1000–59999 (field 3; home = field 6): a "User <name>:" heading followed by every regular file in `<home>/.config/autostart/` and `<home>/.config/systemd/user/` (missing directories are skipped).
- nullglob-safe loops: `shopt -s nullglob` at the top of the function, `shopt -u nullglob` before the return; each glob loop also guards with `[ -f "$f" ] || continue` so subdirectories are never listed.
- Global `STARTUP_ITEMS=0` added next to `THREATS=0`; the function resets it to 0 and counts every entry listed (each file = 1; ld.so.preload contents = 1 when present and non-empty).
- If /etc/ld.so.preload exists and is not empty: logs "Preload file is set — System Reset recommended." and sets TAMPER=1.
- Summary line logged: `Startup audit: $STARTUP_ITEMS item(s) listed in <file path>.` (path = `$LOG_DIR/startup-$STAMP.txt`).
- `run_scan()`: added `run_startup_audit || exit 3 # tool error` right after `run_chkrootkit || exit 3`; existing exit order unchanged (TAMPER=1 → exit 2, THREATS>0 → exit 1, else exit 0). Consequence to note: a set ld.so.preload now drives the scan to exit 2 via TAMPER.
- Design notes for review: the user loop reads `getent passwd` via process substitution (`< <(getent passwd)`, not a pipe) so STARTUP_ITEMS increments persist in the parent shell; non-numeric UIDs are skipped with a case guard before the numeric compare (set -e safe); the function has a single return path, so nullglob is always restored.
What I ran + output: nothing run — per instruction no test commands this step, so this is NOT claimed as tested or shellcheck-clean.
Questions / unsure about: none
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 3c-1 — 2026-10-23
- APPROVED as written — no fixes needed. List-only (changes nothing), nullglob turned on and back off, `[ -f ]` skips dirs and masked units, real users = UID 1000–59999 from `getent passwd`.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean; CRLF → LF.
- Sandbox tests (fake getent with root, a UID-1000 user and nobody): user autostart file with a space in its name listed; root/nobody skipped; no preload → 0; preload with content → "Preload file is set" + exit 2; empty preload → 0.
- Next: Step 3c-2 (plain-English report + user copy via $PKEXEC_UID).

## Step 3c-2 — Plain-English report — 2026-10-23
Files changed: files/system/usr/bin/forgeos-cleansweep
What Rabbit Team / Cline did (2 saved edits): new `write_report()` after `run_startup_audit()` (headline + "Scanned:" date + each per-run log under a "== title ==" heading → `$LOG_DIR/report-$STAMP.txt`; user copy via `runuser` when PKEXEC_UID is set); `run_scan()` now computes rc (THREATS → 1, TAMPER → 2), calls `write_report "$rc"`, then exits with it.
Cline was cancelled before writing this report: it saw Claude's fixes on disk and was about to "correct" them. Claude wrote this report.
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 3c-2 — 2026-10-23
- APPROVED with fixes (Claude applied):
  1. **Real bug:** `runuser -u` keeps root's environment, and pkexec sets HOME=/root, so the user copy would have gone to /root (and failed). The user's home now comes from `getent passwd` field 6 and is passed into the `sh -c` as `$1`. The copy is still written AS the user (no root writes into a user-owned folder, so no symlink tricks).
  2. Empty sections now say "(nothing found)", with a blank line between sections.
  3. CRLF → LF.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean.
- Sandbox tests (fake runuser that forces HOME=/root like pkexec, fake getent): clean → 0 "All clear — no threats found." + user copy; infected → 1 "1 threat(s) found and locked away."; infected dry-run → 1 "(dry run — nothing was moved)"; preload + infected → 2 "System files changed — System Reset recommended. 1 threat(s) were also found and locked away."; no PKEXEC_UID → no copy; unknown UID → WARNING, no copy, still exit 0.
- **Step 3 (scan) is COMPLETE.** `forgeos-cleansweep scan` = core check → ClamAV → rkhunter → chkrootkit → startup audit → report; exit 0/1/2/3.
- Next: Step 4 (quarantine list / restore / delete).

## Step 4a — Quarantine log columns + `quarantine list` — 2026-10-23
Files changed: files/system/usr/bin/forgeos-cleansweep
What Rabbit Team / Cline did (8 small edits, one file):
- run_clamscan() pass 2 now records the original mode and owner BEFORE `chmod 000`: `mode="$(stat -c %a "$moved")" || mode="unknown"` and `owner="$(stat -c %u:%g "$moved")" || owner="unknown"` (both added to the function's local line). The quarantine.log line is now 7 tab-separated fields: date, original path, sha256, threat name, moved path, mode, owner (uid:gid) — printf format updated to match.
- Comment above run_clamscan() updated to list all 7 fields.
- `YES=0` added next to `DRY_RUN=0`.
- New `quarantine_list()` placed right after write_report(): reads `$QUAR_DIR/quarantine.log` with `while IFS=$'\t' read -r qdate qorig qsha qthreat qmoved qmode qowner`; skips lines where qmoved is empty (old 4-field lines) or the file no longer exists (`[ -e ]`); ID = qmoved with the `$QUAR_DIR/` prefix removed; prints the header `ID<TAB>Date<TAB>Threat<TAB>Original location` once before the first entry, then one TAB-separated line per kept entry (id, date, threat, original path); prints "Quarantine is empty." if the log is missing or nothing was printed; returns 0.
- New `quarantine_cmd()` after it: `case "$QSUB"` — list → quarantine_list + exit 0; restore|delete → `echo "quarantine $QSUB: coming in Step 4b" >&2` + exit 3 (stubs for Step 4b).
- Argument parsing replaced (the old CMD= for-loop and the --dry-run-alone block): the FIRST argument now picks the command — no args → CMD=legacy; `scan [--dry-run]` → CMD=scan; `--dry-run` alone → CMD=scan with DRY_RUN=1; `quarantine list` / `restore <id> [--yes]` / `delete <id|all> [--yes]` → CMD=quarantine with QSUB, QID and YES set (QSUB="" and QID="" initialized next to CMD=""); anything else, a missing `<id>`, or extra args → usage + exit 3. All `$2/$3/$4` references are `${n:-}`-guarded for `set -u`.
- The root check and the mkdir/chmod/LOG_FILE lines stay exactly where they were (after parsing, before dispatch). Dispatch is now: scan → run_scan; quarantine → quarantine_cmd; legacy → legacy_sweep.
- usage() gained the three quarantine command lines plus `--yes` ("Skip the question — used by the Clean Sweep window").
What I ran + output: nothing run — per instruction no test commands this step, so this is NOT claimed as tested or shellcheck-clean.
Questions / unsure about: none
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 4a — 2026-10-23
- APPROVED with small touch-ups (Claude applied):
  1. `quarantine_list()` reads the unused fields (sha256, mode, owner) into `_` — fixes 3 shellcheck SC2034 warnings.
  2. QID / YES are parsed now but used only in Step 4b: referenced with `: "$QID" "$YES"` in the stub so shellcheck stays clean.
  3. Usage first line updated (it still said `[scan] [--dry-run]` only).
  4. `--dry-run scan` (the old argument order) works again, same as `scan --dry-run`.
  5. CRLF → LF.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean.
- Sandbox tests (fake id / clamscan / rkhunter / chkrootkit / ostree / rpm-ostree): empty quarantine → "Quarantine is empty." exit 0; scan with an infected file named with a space → quarantine.log has 7 fields (mode 640 + uid:gid recorded BEFORE chmod 000; file is now mode 000); `quarantine list` shows header + ID `<STAMP>/bad file.exe`, and skips an old 4-field line; restore/delete stubs → exit 3; bad args (`quarantine`, `quarantine delete`, `quarantine list x`, `scan x`, `--dry-run x`, `bogus`) → usage, exit 3.
- Next: Step 4b (restore with sha256 check + no overwrite + put back mode/owner; delete <id|all>; ask first, `--yes` skips, no terminal + no `--yes` → exit 3).
