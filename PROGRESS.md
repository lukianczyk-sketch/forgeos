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

## Step 4b-1 — `quarantine restore <id>` (confirm + quarantine_find helpers) — 2026-10-23
Files changed: files/system/usr/bin/forgeos-cleansweep
What Rabbit Team / Cline did (3 small edits, one file):
- Globals next to QSUB=""/QID="" (top level, before dispatch): F_DATE="", F_ORIG="", F_SHA="", F_THREAT="", F_MOVED="", F_MODE="", F_OWNER="" — the matched quarantine.log line, filled by quarantine_find.
- New `confirm()` right after quarantine_list(): YES=1 → return 0; `[ ! -t 0 ]` → "No terminal to ask on — add --yes to confirm." >&2 + exit 3; otherwise `read -r -p "<question> [y/N] " ans`, returns 0 only for y/Y (anything else, including empty/EOF, returns 1).
- New `quarantine_find()` after it: refuses an empty id, one starting with "/", or one containing ".." → "Bad ID: <id>" >&2 + exit 3; want="$QUAR_DIR/<id>"; missing $QUAR_DIR/quarantine.log → "No quarantined file with ID <id>." >&2 + exit 3; reads the log with `while IFS=$'\t' read -r qdate qorig qsha qthreat qmoved qmode qowner` (file redirect, so no subshell) and keeps the LAST line where qmoved = want into F_DATE/F_ORIG/F_SHA/F_THREAT/F_MOVED/F_MODE/F_OWNER; if no line matched or `[ ! -e "$F_MOVED" ]` → "No quarantined file with ID <id>." >&2 + exit 3.
- New `quarantine_restore()` after that: quarantine_find "$QID"; now="$(sha256sum "$F_MOVED" | awk '{print $1}')", and if F_SHA is "unknown" or now != F_SHA → "Refusing: the quarantined file has changed since it was locked away." >&2 + exit 3; refuses when `[ -e "$F_ORIG" ] || [ -L "$F_ORIG" ]` ("Refusing: something already exists at $F_ORIG (will not overwrite)."); refuses when `[ ! -d "$(dirname "$F_ORIG")" ]` ("Refusing: folder ... no longer exists."); prints "WARNING: this file was flagged as: <threat>" + "Only restore it if you are sure it is safe."; confirm "Restore it to $F_ORIG?" — on cancel → "Cancelled — nothing was changed." + exit 0; `mv -n "$F_MOVED" "$F_ORIG"` and if the quarantined file still exists afterwards → "ERROR: could not restore the file." >&2 + exit 3; chmod F_MODE (or 600 when unknown); chown F_OWNER when not "unknown"; log "Restored $F_ORIG from quarantine (ID $QID)." + echo "Restored: $F_ORIG" + exit 0.
- quarantine_cmd() case split: restore) → quarantine_restore; delete) keeps the stub (`: "$QID" "$YES"` so shellcheck stays clean, then "quarantine delete: coming in Step 4b-2" >&2 + exit 3). Dispatch comment updated (list and restore work now; delete is a stub until Step 4b-2).
- usage(): "(coming in Step 4b)" removed from the quarantine restore line (it works now); the delete line left as is.
What I ran + output: nothing run — per instruction no test commands this step, so this is NOT claimed as tested or shellcheck-clean.
Questions / unsure about: one anticipated nitpick for Claude — F_DATE is saved by quarantine_find but not read anywhere yet (restore doesn't need the date), so if SC2034 fires at warning level it will be on F_DATE; kept because the spec says to save all 7 fields and Step 4b-2's delete will likely use it.
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 4b-1 — 2026-10-23
- APPROVED with fixes (Claude applied):
  1. **Security fix (real):** the plain `mv` + `chmod` + `chown` as root ran in the user's own folder, so a user could swap the file (or the folder) for a symlink in between and get root to chown/chmod or drop a file anywhere (e.g. take ownership of /etc/shadow). Now:
     - **User's file** (owner uid ≠ 0): written back AS that user via `runuser` with no-overwrite (`set -C`), then chmod/chgrp as that user — it can only land where that user could have put it. Owner uid missing from the system → refuse, exit 3.
     - **Root's file** (or owner unknown): mode + owner are set while it is still inside the root-only quarantine folder, and it only goes back into a real (no symlinks, `realpath` match) root-owned folder; otherwise refuse, exit 3. If the move fails, the file is locked again (chmod 000).
  2. `chmod`/`chown`/`sha256sum` failures no longer kill the script under `set -e` with the wrong exit code (1 = "threats"); they give a clear ERROR and exit 3.
  3. F_DATE now shown in the warning ("locked away <date>") — also clears the SC2034 Cline expected.
  4. Usage: delete line now says "(coming in Step 4b-2)".
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean, no CRLF.
- Sandbox tests (fake id / runuser / getent / stat / chown; quarantined files 600 because the sandbox is not root): no terminal + no --yes → exit 3, nothing moved; user file with a space in its name → restored, mode 640, content intact, gone from quarantine + list, logged, exit 0; restore again → "No quarantined file", 3; something already at the original spot → refuse, untouched, 3; tampered quarantined file → refuse, 3; IDs `../etc/passwd`, `/etc/passwd`, `S1/x/../../y` → "Bad ID", 3; root file into root folder → restored, mode 600, 0; root file into a symlinked folder → refuse, 3; owner uid gone → refuse, 3; original folder gone → refuse, 3; unknown owner into a user folder → refuse, 3.
- Next: Step 4b-2 (`quarantine delete <id|all>`).

## Step 4b-2 — `quarantine delete <id|all>` — 2026-10-23
Files changed: files/system/usr/bin/forgeos-cleansweep
What Rabbit Team / Cline did (small edits, one file):
- New `quarantine_delete()` right after quarantine_restore(): when QID is "all" — reads $QUAR_DIR/quarantine.log if it exists with `while IFS=$'\t' read -r _ _ _ _ qmoved _ _` (file redirect, no subshell), collecting every non-empty qmoved that still exists (`[ -e "$qmoved" ]`) into a bash array and skipping duplicates; empty array → "Quarantine is empty." + exit 0; confirm "Delete all N quarantined file(s) for good?" — cancel → "Cancelled — nothing was changed." + exit 0; `rm -f --` each file, on failure → "ERROR: could not delete <file>" >&2 + exit 3; log "Deleted all quarantined files (N)." + echo "Deleted N quarantined file(s)." + exit 0. Otherwise — quarantine_find "$QID"; echo "This will permanently delete: $F_ORIG (flagged as: $F_THREAT)"; confirm "Delete it for good?" — cancel → "Cancelled — nothing was changed." + exit 0; `rm -f -- "$F_MOVED"`, on failure → "ERROR: could not delete the file." >&2 + exit 3; log "Deleted quarantined file $F_ORIG (ID $QID)." + echo "Deleted: $F_ORIG" + exit 0.
- quarantine_cmd(): the whole delete) stub (`: "$QID" "$YES"` + "quarantine delete: coming in Step 4b-2" >&2 + exit 3) replaced with `delete) quarantine_delete ;;`. Dispatch comment updated (list, restore and delete all work now).
- usage(): "(coming in Step 4b-2)" removed from the quarantine delete line.
What I ran + output: nothing run — per instruction no test commands this step, so this is NOT claimed as tested or shellcheck-clean.
Questions / unsure about: none
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 4b-2 — 2026-10-23
- APPROVED. Code matched the spec; one small add by Claude:
  1. New `tidy_quar_dir()`: after a delete or restore, the scan's quarantine sub-folder is removed once it is empty (`rmdir` only, never `$QUAR_DIR` itself).
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean, no CRLF.
- Sandbox tests (fake id / runuser / getent): `delete all` with no log → "Quarantine is empty.", 0; no terminal + no --yes (one file and all) → exit 3, nothing deleted; delete one (name with a space) → gone, logged, 0; delete it again → "No quarantined file", 3; `../quarantine.log` → "Bad ID", 3; restore → empty S3 folder tidied; `delete all --yes` with a duplicate log line + an old 4-field line → "Deleted 2 quarantined file(s).", empty folders tidied, quarantine.log kept, 0; again → "Quarantine is empty.", 0; `list` → empty.
- **Step 4 (quarantine tools) is COMPLETE**: list / restore / delete.
- Next: Step 5 (`forgeos-cleansweep reset-system`, keeps personal files).

## Step 5a-1 — reset-system dry-run plan (/etc) — 2026-10-24
Files changed: files/system/usr/bin/forgeos-cleansweep (plus this PROGRESS.md report)
What Rabbit Team / Cline did (one file):
- Globals next to QSUB=""/QID="" (top level, before dispatch): RESET_RESTORE=0, RESET_REMOVE=0, RESET_PUTBACK=0, RESET_KEEP=0, RESET_FLAGS=0 — the reset-system plan counters.
- New `reset_keep()` right after legacy_sweep(): one case statement over the path RELATIVE to /etc; machine-id|passwd|group|shadow|gshadow|subuid|subgid|passwd-|group-|shadow-|gshadow-|.pwd.lock|.updated|hostname|fstab|crypttab|locale.conf|vconsole.conf|localtime|adjtime|X11/xorg.conf.d/00-keyboard.conf|NetworkManager/system-connections/* → return 0, anything else → return 1.
- New `reset_etc_plan()` after it: checks `command -v ostree` first (missing → "ERROR: ostree not found." + return 3), then captures the diff with `if ! diff_out="$(ostree admin config-diff)"` (failure → "ERROR: 'ostree admin config-diff' failed — cannot plan the /etc restore." + return 3); logs "Restore /etc to factory (keep-list skipped):"; loops `while read -r status path; do ... done <<< "$diff_out"` skipping empty paths; reset_keep hit → "  KEEP     /etc/<path>" + RESET_KEEP+1, else case on status: M → "  RESTORE  /etc/<path> (factory copy from /usr/etc; old one backed up)" + RESET_RESTORE+1, A → "  REMOVE   /etc/<path> (moved to the backup folder)" + RESET_REMOVE+1, D → "  PUT BACK /etc/<path> (copied from /usr/etc)" + RESET_PUTBACK+1; counters use VAR=$((VAR + 1)) (not ((VAR++)), set -e safe); after the loop logs "  Then: systemctl preset-all (turns factory services back on)."; return 0.
- New `reset_keep_warnings()` after it: for each name from `awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd` → "WARNING: extra administrator (UID 0) account found: <name> — it is kept, check it!" + RESET_FLAGS+1; only if /usr/etc/shadow is readable, compares root's 2nd field in /etc/shadow vs /usr/etc/shadow (`awk -F: '$1 == "root" {print $2}'`) and on difference → "NOTE: the root password was changed after install (kept as is)." + RESET_FLAGS+1; if RESET_FLAGS is still 0 → "Keep-list check: no extra admin accounts found."; return 0.
- New `reset_system()` after it: DRY_RUN=0 → "reset-system: the real run is coming in Step 5b — use --dry-run for now." >&2 + exit 3 (the real run is a stub this step); otherwise logs "System Reset plan (dry run — nothing will be changed). Personal files are kept.", runs `reset_etc_plan || exit 3`, then reset_keep_warnings, then "Summary: $RESET_RESTORE to restore, $RESET_REMOVE to remove, $RESET_PUTBACK to put back, $RESET_KEEP kept."; `: "$YES"` (used in Step 5b; keeps shellcheck quiet); exit 0.
- Argument parsing: new case branch `reset-system)` — allows 0–2 more args, each must be --dry-run or --yes (sets DRY_RUN=1 / YES=1), anything else → usage + exit 3; sets CMD="reset". Parsing comment block gained the reset-system line.
- Dispatch: added `elif [ "$CMD" = "reset" ]; then reset_system` before the final else.
- usage(): first line now includes "| reset-system [--dry-run] [--yes]" and a new command line "reset-system [--dry-run] [--yes]   Put the system back to factory; keeps personal files (real run coming in Step 5b)".
What I ran + output: nothing run — per instruction no test commands this step, so this is NOT claimed as tested or shellcheck-clean.
Questions / unsure about: none — the keep-list case patterns were implemented exactly as specified (note for review: `passwd-`/`group-`/`shadow-`/`gshadow-` are literal names without a wildcard, so they match only a file named exactly e.g. "passwd-", not files starting with that prefix).
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 5a-1 — 2026-10-24
- APPROVED with 2 small fixes (Claude applied):
  1. **Keep-list safety:** `ostree admin config-diff` can report a whole added folder as ONE line. If `NetworkManager/system-connections` itself showed as `A`, the reset would have moved the Wi-Fi passwords away with it. Parent folders are now on the keep-list too (`NetworkManager`, `NetworkManager/system-connections`, `X11`, `X11/xorg.conf.d`), plus `resolv.conf` so DNS keeps working. Exact names only, so `NetworkManager/conf.d/evil.conf` is still removed.
  2. Parsing: an empty flag (`reset-system ""`) is now rejected (usage, exit 3).
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean, no CRLF. Legacy sweep untouched.
- Sandbox tests (fake id + ostree; passwd/shadow pointed at test copies): mixed M/A/D fixture incl. Wi-Fi file with a space, `ld.so.preload`, an evil service, `NetworkManager/conf.d/evil.conf` → correct KEEP / RESTORE / REMOVE / PUT BACK lines + counts, exit 0; extra UID 0 account `toor` → WARNING; changed root hash → NOTE; clean passwd/shadow → "no extra admin accounts found"; `--yes --dry-run` (either order) → 0; real run (with or without --yes) → stub, 3; `--bogus`, `--dry-run x`, 3 flags, empty flag → 3; config-diff fails → ERROR, 3; `quarantine list` + unknown command unchanged.
- Next: Step 5a-2 (dry-run plan for the rest: user startup spots, clears, flatpak, signed image, reboot).

## Step 5a-2 — reset-system dry-run plan (the rest) — 2026-10-24
Files changed: files/system/usr/bin/forgeos-cleansweep (plus this PROGRESS.md report)
What Rabbit Team / Cline did (one file):
- Globals next to RESET_FLAGS=0: RESET_USERFILES=0 (user startup items counter) and RESET_REF="" (signed image reference for the rebase step).
- New `reset_image_ref()` right after reset_keep_warnings(): if rpm-ostree AND jq exist, `ref="$(rpm-ostree status --json | jq -r '.deployments[] | select(.booted) | ."container-image-reference" // empty')" || ref=""`; then case: ostree-image-signed:* → keep it; ostree-unverified-registry:* → "ostree-image-signed:docker://${ref#ostree-unverified-registry:}"; anything else → ""; stores the result in RESET_REF; always returns 0 (same logic as legacy_sweep step 1, for reuse in Step 5d).
- New `reset_users_plan()` after it: loops `while IFS=: read -r user _ uid _ _ home _; do ... done < <(getent passwd)`; skips UIDs that are not all digits (`case ''|*[!0-9]*`) and keeps only 1000–59999 where "$home" is a directory. For each user: every existing file in ~/.config/autostart/, ~/.config/systemd/user/, ~/.config/plasma-workspace/env/, ~/.config/plasma-workspace/shutdown/ and ~/.ssh/authorized_keys (guard `[ -e "$f" ] || [ -L "$f" ] || continue` for empty globs / broken links; names starting with forgeos- are skipped) → "  MOVE     <path> (to the backup folder)" + RESET_USERFILES+1; then .bashrc/.bash_profile/.profile: if both $home/<name> and /etc/skel/<name> exist AND `! cmp -s` on them → "  RESET    $home/<name> (fresh copy from /etc/skel; old one backed up)" + RESET_USERFILES+1; then "  LOCK     user <user> must choose a new password at next login". After the loop: if /root/.ssh/authorized_keys exists → "  MOVE     /root/.ssh/authorized_keys (to the backup folder)" + RESET_USERFILES+1. Returns 0.
- reset_system() dry-run body rewritten (DRY_RUN=0 stub kept as-is): keeps the first log line, then in order: "1. Scan first (threats in personal files get quarantined)."; "2. rpm-ostree reset (removes added packages and overrides)."; `log "3."` then `reset_etc_plan || exit 3` + reset_keep_warnings; "4. Clean each user's startup spots (personal files untouched):" + reset_users_plan; "5. Clear hiding spots:" — if /etc/ld.so.preload exists → "  CLEAR    /etc/ld.so.preload", each existing entry in /var/spool/cron/* → "  MOVE     <path> (to the backup folder)" (not counted in RESET_USERFILES), then "  EMPTY    /tmp" and "  EMPTY    /var/tmp"; "6. Re-check apps:" — flatpak present → "  flatpak repair --system, then flatpak update -y", else "  (flatpak not installed — skipped)"; "7. Fresh signed system image:" — reset_image_ref; RESET_REF non-empty → "  REBASE   $RESET_REF (if there is no update: redeploy the current image)", else "  WARNING: no signed image reference found — this step will be skipped."; "8. Show the summary, then restart after you click OK." Summary line now ends with ", $RESET_USERFILES user startup items.". `: "$YES"` and exit 0 kept. Counters use VAR=$((VAR + 1)) only (no ((VAR++))).
What I ran + output: nothing run — per instruction no test commands this step (Claude tests on Linux), so this is NOT claimed as tested or shellcheck-clean.
Questions / unsure about: one wording check — the instruction says `log "3."` with no description text, so the plan prints a bare "[Clean Sweep] 3." line right before reset_etc_plan's own header ("Restore /etc to factory (keep-list skipped):"). Implemented exactly as written; please confirm that is the intended wording.
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 5a-2 — 2026-10-24
- APPROVED with 1 small fix (Claude applied):
  1. Answer to Cline's question: the bare "3." line was a placeholder in the prompt. Removed it, and reset_etc_plan's header now reads "3. Restore /etc to factory (keep-list skipped):" so the plan reads 1–8 cleanly.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean, no CRLF. Legacy sweep untouched.
- Sandbox tests (fake id / getent / ostree / rpm-ostree / flatpak; passwd, shadow, skel, spool, /root/.ssh, ld.so.preload pointed at test copies):
  - Full plan prints steps 1–8 in order, exit 0. User bob: autostart file with a space, broken symlink, systemd/user, plasma env + shutdown scripts, authorized_keys → MOVE; `forgeos-helper.desktop` skipped; changed .bashrc → RESET; .profile same as skel → not listed; .bash_profile with no skel copy → not listed; LOCK line. amy (matches skel) → LOCK only. ghost (no home), uid 999, nobody (65534) → skipped. Root authorized_keys, spool cron file, ld.so.preload listed. Summary "8 user startup items" is correct.
  - unverified-registry ref → converted to ostree-image-signed:docker://…; already-signed ref kept; unknown ref or rpm-ostree failing → WARNING, still exit 0; no flatpak → "skipped".
  - config-diff fails → ERROR, 3; real run (with --yes) → stub, 3; empty system → only EMPTY /tmp + /var/tmp under step 5; `quarantine list` unchanged.
- **Step 5a (dry-run plan) is COMPLETE.**
- Next: Step 5b (real run part 1: confirm(), backup folder, rpm-ostree reset, /etc restore, systemctl preset-all).

## Step 5b — reset-system real run, part 1 (rpm-ostree reset + /etc restore) — 2026-10-24
Files changed: files/system/usr/bin/forgeos-cleansweep (plus this PROGRESS.md entry)
What Rabbit Team / Cline did (one file):
- Globals after QUAR_DIR: ETC_DIR="/etc", USR_ETC_DIR="/usr/etc", RESET_BK_DIR="/var/lib/forgeos/reset-backup"; next to RESET_REF: RESET_ERRORS=0, RESET_BK="".
- reset_etc_plan() takes an optional mode (`local mode="${1:-plan}"`); all log lines unchanged. New guard: paths starting with / or containing .. → "SKIP odd path". In "apply" mode: M → back up (mkdir -p + mv to $RESET_BK/etc/<path>) then cp -a the /usr/etc copy; A → mkdir -p + mv to the backup; D → mkdir -p parent + cp -a from /usr/etc. Every command checked; failure → "ERROR: …", RESET_ERRORS+1, next file. After the loop, apply mode runs `systemctl preset-all` (failure → WARNING + RESET_ERRORS+1).
- New reset_system_run(): confirm "System Reset puts ForgeOS system settings back to factory. Your personal files are kept. Continue?" (cancel → "Cancelled — nothing was changed.", exit 0); RESET_BK="$RESET_BK_DIR/$STAMP", mkdir -p + chmod 700 both; "System Reset started. Backup folder: …"; step 2 `rpm-ostree reset` (output to the log; failure or missing → WARNING + RESET_ERRORS+1); `reset_etc_plan apply || exit 3`; reset_keep_warnings; "Steps 4-8 … coming in Steps 5c/5d."; "Done: N restored, N removed, N put back, N kept, N problems. Changes take effect after a restart."; exit 3 if RESET_ERRORS > 0, else 0.
- reset_system(): the DRY_RUN=0 stub now calls reset_system_run; dry-run part unchanged; comments updated.
- Not finished by Cline: the usage() wording edit failed (exact-match miss). Claude made it.
What I ran + output: nothing (per instruction). Cline's task was cancelled by Claude before it wrote this report; Claude wrote it from the diff.
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 5b — 2026-10-24
- APPROVED with 4 small fixes (Claude applied):
  1. **Never leave /etc missing a file:** for M, if copying the factory version fails after the old file was moved to the backup, the old file is moved back (and the error says where it is if even that fails).
  2. **Added folders:** config-diff can list an added folder AND the files inside it. Once the folder is moved, its children are already in the backup, so they are now skipped instead of counted as errors.
  3. **Check before changing anything:** reset_system_run checks `ostree` exists before asking/starting, so a missing ostree can't stop the reset halfway (after rpm-ostree reset).
  4. usage() line now says "(Steps 4-8 coming in 5c/5d)" (Cline's edit had failed).
- Note for later: ostree merges the current /etc into the staged deployment at shutdown, so /etc changes made after `rpm-ostree reset` carry over to the next boot (that's why step 2 runs before step 3 safely).
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean, no CRLF.
- Sandbox tests (fake id / ostree / rpm-ostree / systemctl; ETC_DIR, USR_ETC_DIR, RESET_BK_DIR, passwd, shadow pointed at test folders):
  - No terminal + no --yes → exit 3, no backup folder, /etc untouched. Real terminal, answer "n" → "Cancelled", exit 0, nothing changed, rpm-ostree/systemctl never called.
  - `--yes` with a mixed fixture: modified sshd_config → backed up + factory copy; ld.so.preload and an added folder `evil.d` (+ its 2 files listed separately) → moved to the backup with full paths, no false errors; deleted `os-release` and `foo/bar` (missing parent folder) → put back; Wi-Fi file with a space and `passwd` → KEEP; `../escape` → SKIP; unreadable factory file → ERROR, old copy put back, exit 3. Backup folders are mode 700. rpm-ostree reset + systemctl preset-all each called once.
  - rpm-ostree failing → WARNING, /etc still restored, exit 3. Everything OK → exit 0. ostree missing → ERROR before the question, nothing changed, exit 3.
  - `--dry-run` output identical to the 5a-2 version; bad flags → 3.
- Next: Step 5c (real run part 2: per-user startup spots + dotfiles from /etc/skel, password expiry, clear ld.so.preload / spool cron / tmp).

## Step 5c — reset-system real run, part 2 (user startup spots + hiding spots) — 2026-10-24
Files changed: files/system/usr/bin/forgeos-cleansweep (plus this PROGRESS.md entry)
What Rabbit Team / Cline did (one file):
- New globals after RESET_BK_DIR: TMP_DIR="/tmp", VARTMP_DIR="/var/tmp" (so tests never touch the real temp folders).
- reset_users_plan() takes an optional mode (`local mode="${1:-plan}"`); log lines unchanged. In "apply" mode: MOVE → mkdir -p + mv into `$RESET_BK<full path>`; RESET → back up the old dotfile, then `runuser -u <user> -- cp /etc/skel/<name>` (written as the user, so root never writes into a user's folder; if the copy fails the old file is moved back); LOCK → `passwd -e <user>`; /root/.ssh/authorized_keys → moved to the backup. Every failure → "ERROR: …", RESET_ERRORS+1, next item.
- New reset_clears() (plan/apply): the "5. Clear hiding spots" block moved out of reset_system(). Apply: back up + empty /etc/ld.so.preload; move each /var/spool/cron/* to the backup, then mkdir -p + chmod 700 /var/spool/cron; /tmp is skipped when it is tmpfs ("emptied by the restart"), otherwise emptied like /var/tmp; /var/tmp emptied with find -mindepth 1 -maxdepth 1, skipping systemd-private-*, .X11-unix, .ICE-unix, .XIM-unix, .font-unix.
- reset_system_run(): now runs "4. …" reset_users_plan apply and "5. …" reset_clears apply; "Steps 6-8 … coming in Step 5d."; Done line adds "N user startup items". Comments + usage() updated.
What I ran + output: nothing (per instruction). Claude cancelled Cline while it was stuck writing this report and wrote it from the diff.
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 5c — 2026-10-24
- APPROVED with 3 small fixes (Claude applied):
  1. **Don't lose the evidence:** if Step 3 had already backed up a changed ld.so.preload (M) and copied the factory one in, the Step 5 backup copy overwrote it. Now `cp -a --backup=numbered`, so the bad copy is kept as `ld.so.preload.~1~`. CLEAR now only runs when the file is not empty (`-s`).
  2. `rm -rf --one-file-system` in the temp-folder clean, so a mount inside /tmp or /var/tmp is never followed.
  3. Removed 10 repeated "fail-safe" comment lines (from a confusing line in Claude's prompt); one note in the function header instead.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean, no CRLF.
- Sandbox tests (fake id / getent / runuser / passwd / findmnt / ostree / rpm-ostree / systemctl; skel, spool, /root/.ssh, ld.so.preload, tmp dirs pointed at test folders):
  - `--dry-run` output identical to 5b's (8 user startup items).
  - `--yes`, dirty user bob: autostart file with a space + broken symlink, systemd/user unit + .wants folder, plasma env script, authorized_keys → all moved into the backup with full paths; forgeos-helper.desktop kept; Documents untouched; .bashrc replaced from skel (old one in the backup); .profile (same as skel) untouched; passwd -e for bob and amy only (uid 999, 65534, no-home user skipped). Root authorized_keys moved; ld.so.preload backed up + emptied; both spool cron files (one with a space) moved; spool/cron + backup folders are 700. /tmp and /var/tmp emptied incl. hidden files, nested folders and a symlink (its target in amy's home untouched); .X11-unix and systemd-private-* kept. Exit 0.
  - runuser copy fails → ERROR, old .bashrc put back, exit 3. passwd fails for one user → ERROR, next user still done, exit 3. Read-only autostart folder → 2 ERRORs, rest of the reset still runs, exit 3. /tmp on tmpfs → left alone with a note.
  - ld.so.preload as A → moved by Step 3, Step 5 skips it (no false CLEAR). As M → bad copy kept as .~1~. Empty file → not listed.
  - No terminal + no --yes → exit 3, nothing changed. Answer "n" → Cancelled, exit 0, nothing changed.
- Next: Step 5d (real run part 3: scan first, flatpak repair + update, signed rebase or redeploy, summary, restart after OK).

## Step 5d — reset-system real run, part 3 (scan first, apps, fresh image, restart) — 2026-10-24
Files changed: files/system/usr/bin/forgeos-cleansweep (plus this PROGRESS.md entry)
What Rabbit Team / Cline did (one file):
- Split run_scan(): everything from core_check through write_report moved into a new scan_steps() that ends with `return "$rc"`; each tool error is now `|| return 3`. run_scan keeps the "Scan started" and dry-run log lines, then does `local rc=0; scan_steps || rc=$?; exit "$rc"`.
- reset_system_run(): step 1 added right after the backup-folder line — log "1. Scan first (threats in personal files get quarantined).", run scan_steps into a local scan_rc and never exit: rc 3 → WARNING + RESET_ERRORS+1; rc 1 or 2 → "Threats or tampering found — handled above; the reset continues."
- Step 6 replaces the old placeholder line: flatpak present → `flatpak repair --system` then `flatpak update -y --noninteractive`, both to $LOG_FILE, each failure → WARNING + RESET_ERRORS+1; missing → "(flatpak not installed — skipped)".
- Step 7: reset_image_ref; empty RESET_REF → "WARNING: no signed image reference found — skipped." + RESET_ERRORS+1; otherwise `rpm-ostree rebase "$RESET_REF"` to $LOG_FILE, success → "Fresh verified ForgeOS image staged for the next restart.", failure → WARNING (no internet?) + RESET_ERRORS+1.
- Step 8 after the Done line: YES=1 → "Restart the computer to finish." (no reboot — the Clean Sweep window handles it); otherwise confirm "Restart now to finish the reset?" → yes: log "Restarting..." + systemctl reboot, no: "Restart the computer later to finish."; then exit 3 if RESET_ERRORS > 0 else exit 0.
- Text clean-up: usage() line no longer says "(Steps 6-8 coming in 5d)"; comments above reset_system_run() and reset_system() updated to the Steps 5b-5d wording. Nothing else changed.
What I ran: nothing (per instruction).
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 5d — 2026-10-24
- APPROVED with 1 fix (Claude applied):
  1. **No false warning when already on the signed image:** rpm-ostree refuses to rebase to the ref you are already on, so every reset of an already-signed ForgeOS would have shown "could not get a fresh image". reset_image_ref now sets RESET_SAME_REF=1 when the booted ref already equals RESET_REF; Step 7 then runs `rpm-ostree upgrade` (exits 0 when there is no update, per the rpm-ostree man page; 77 only with --unchanged-exit-77) instead of rebase. `--dry-run` shows "UPGRADE … (already on the signed image; no update = keep the current one)" or "REBASE …".
- Rejected one Cline PowerShell Select-String command (quoting errors); Cline read the file instead.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean, no CRLF.
- Sandbox tests (fake id / ostree / rpm-ostree status JSON / flatpak / systemctl; scan tools and Steps 3-5 stubbed via an override file, since they were tested in 3a-5c):
  - `--yes`, unverified booted ref → order is scan → rpm-ostree reset → /etc → users → clears → flatpak repair → flatpak update → `rpm-ostree rebase ostree-image-signed:docker://…`; no reboot; exit 0.
  - `--yes`, already signed → `rpm-ostree upgrade` instead of rebase; exit 0.
  - Scan tool error → WARNING, reset still runs every step, exit 3. Threats / tampering → note, reset continues, exit 0.
  - flatpak repair fails → WARNING, update still runs, exit 3. flatpak missing → "skipped", exit 0. upgrade fails → WARNING (no internet?), exit 3. No signed ref → WARNING, no rebase, exit 3.
  - Real terminal: answer y then y → "Restarting..." + `systemctl reboot`; y then n → "Restart the computer later", no reboot.
  - `scan` exit codes unchanged: clean 0 / threats 1 / tamper 2 / tool error 3. Bad reset flag → 3.
- Step 5 (System Reset engine) is COMPLETE.
- Next: Step 6 (full wipe).

## Step 6a — full-wipe argument parsing + dry-run plan (real run stub) — 2026-10-24
Files changed: files/system/usr/bin/forgeos-cleansweep (plus this PROGRESS.md entry)
What Rabbit Team / Cline did (one file):
- New reset_system_plan() right above reset_system(): takes `local mode="${1:-reset}"`; contains the old plan body from "1. Scan first" through the step 7 REBASE/UPGRADE/WARNING block; no exit of its own. Step 4: mode "wipe" → log "4. (skipped — personal folders are erased in Part 2)" instead of the two step-4 lines (log + reset_users_plan).
- reset_system(): now just the DRY_RUN=0 check (reset_system_run, unchanged), the "System Reset plan (dry run …)" line, `reset_system_plan`, then the unchanged step 8 line, Summary line, `: "$YES"` and exit 0.
- New wipe_users_plan() right below reset_system(): same getent passwd loop header as reset_users_plan (skip non-numeric UID, skip UID < 1000 or >= 60000); per user — symlink home → "SKIP … (home is a symlink — not erased)" + continue; no folder → continue silently; path outside /home/?*|/var/home/?* → "SKIP … (not under /home — not erased)" + continue; else `du -sh -x` size, "ERASE $user $home ($size) → fresh copy of /etc/skel", WIPE_USERS+1.
- New full_wipe() right below wipe_users_plan(): DRY_RUN=0 → log "Full Wipe real run comes in Step 6b." + exit 3; otherwise the dry-run plan: header line, Part 1 `reset_system_plan wipe`, Part 2 wipe_users_plan, Part 3 local qcount from `find $QUAR_DIR -mindepth 1 -type f | wc -l` + "DELETE N quarantined files (for good)", Part 4 restart note, Summary with WIPE_USERS / qcount / RESET_RESTORE / RESET_REMOVE / RESET_PUTBACK; exit 0.
- Globals: WIPE_USERS=0 right below the RESET_BK="" line.
- Argument parsing: new full-wipe) case after reset-system — `full-wipe` | `--dry-run` (DRY_RUN=1) | `--yes WIPE` (YES=1), anything else → usage + exit 3; CMD="wipe". Parsing comment block gained the full-wipe line.
- Dispatch: added `elif [ "$CMD" = "wipe" ]; then full_wipe` after the reset line.
- usage(): Usage line now includes "| full-wipe [--dry-run | --yes WIPE]"; new command line under reset-system: "full-wipe [--dry-run | --yes WIPE] ERASE all personal files, then reset (asks twice)".
What I ran: nothing (per instruction).
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 6a — 2026-10-24
- APPROVED with 1 fix (Claude applied):
  1. **Right quarantine count:** `quarantine.log` lives in `$QUAR_DIR` too, so the count was always 1 too high. Now `find "$QUAR_DIR" -mindepth 2 -type f` (quarantined files are in per-scan sub-folders). Step 6c still empties everything, log included.
- Cancelled Cline during its final "verify" re-read (all edits + PROGRESS entry were already saved).
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean, no CRLF.
- Sandbox tests (fake id / getent passwd fixture; /home path check pointed at a test folder; /etc, clears and image-ref stubbed via an override file):
  - `full-wipe --dry-run` → Part 1 shows steps 1-7 with "4. (skipped …)", Part 2 ERASE bob (2.9M) + amy; eve (outside /home) and lnk (home is a symlink) → SKIP; missing home, UID 999 and 65534 → not listed; Part 3 counts 2 files (not the log); Summary right; exit 0. Nothing changed on disk.
  - `reset-system --dry-run` output unchanged (step 4 + users plan still there, step 8 + Summary); exit 0.
  - `full-wipe` and `full-wipe --yes WIPE` → "real run comes in Step 6b", exit 3.
  - Refused with usage + exit 3: `--yes`, `--yes wipe`, `--dry-run --yes`, `--yes WIPE x`, `WIPE --yes`, `--dry-run WIPE`, empty argument.
- Note for 6c: also check `realpath` of each home stays under /var/home (a home like /home/x passes the text check while /home itself is a symlink on Bazzite — that's fine, but the resolved path must not escape).
- Next: Step 6b (two confirmations + real run of Part 1).

## Step 6b — full-wipe real run part 1 (confirmations + System Reset) — 2026-10-24
Files changed: files/system/usr/bin/forgeos-cleansweep (plus this PROGRESS.md entry)
What Rabbit Team / Cline did (one file):
- reset_system_run(): first line of the function body is now `local mode="${1:-reset}"` (reset_system() still calls it with no argument, so plain System Reset behaves exactly as before).
- reset_system_run(): the confirm block ("System Reset puts ForgeOS system settings back to factory…") is now wrapped in `if [ "$mode" != "wipe" ] … fi` — a wipe run skips this question (its two own confirmations come first, in full_wipe_run).
- reset_system_run(): step 4 is now conditional — mode "wipe" → log "4. (skipped — personal folders are erased in Part 2)"; otherwise the old two lines (log + `reset_users_plan apply`).
- reset_system_run(): right after the "Done: …" line, added `if [ "$mode" = "wipe" ]; then return 0; fi` so a wipe run stops before step 8 and the exit lines below it (both left unchanged).
- New full_wipe_run() directly above full_wipe(), with its Step 6b comment: checks ostree exists first ("ERROR: ostree not found." + exit 3); confirm "Full Wipe ERASES all personal files, apps and settings for every user, then resets ForgeOS to factory. This cannot be undone. Continue?" (cancel → "Cancelled — nothing was changed.", exit 0); unless YES=1, `read -r -p "Type WIPE to erase everything: "` must equal exactly "WIPE" or cancel + exit 0; then "Full Wipe started.", "Part 1 — System Reset:", `reset_system_run wipe`, "Parts 2-4 come in Step 6c.", exit 3.
- full_wipe(): the DRY_RUN=0 stub (log "Full Wipe real run comes in Step 6b." + exit 3) is now one line: `full_wipe_run`; comment line 2 above it changed to "# A non-dry-run call goes to full_wipe_run (Step 6b).".
What I ran: nothing (per instruction).
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 6b — 2026-10-24
- APPROVED. Code matches the blueprint exactly. 1 fix (Claude applied, a 6a bug found while testing):
  1. **Dry-run no longer dies on an unreadable home:** in wipe_users_plan, `du` exits 1 when anything inside a home can't be read (e.g. a FUSE mount like ~/.gvfs, which even root can't read). With `set -euo pipefail` that killed the whole script at "Part 2". Now `size="$( { du -sh -x -- "$home" 2>/dev/null || true; } | cut -f1)"` plus `[ -n "$size" ] || size="?"`. Checked every other `$(… | …)` in the file — the rest are already guarded (or v1 legacy code).
- Cancelled Cline during its final "verify" re-read (all 4 script edits + PROGRESS entry were already saved). Cline caught and restored the Step 6a "Next:" line it had overwritten.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean, no CRLF.
- Sandbox tests (PATH shims for id/ostree/rpm-ostree/flatpak/systemctl that log their calls; scan, /etc, clears, users and image-ref stubbed through an override file; real terminal via `script`):
  - `full-wipe`, answer n → "Cancelled — nothing was changed.", exit 0, no commands run.
  - `full-wipe`, y then "wipe" (lowercase) → cancelled, exit 0, nothing run.
  - `full-wipe`, y then "WIPE" → "Full Wipe started.", "Part 1 — System Reset:", steps 1-7 with "4. (skipped …)" (users stub NOT called), Done line, "Parts 2-4 come in Step 6c.", exit 3. Ran: rpm-ostree reset, flatpak repair + update, rpm-ostree upgrade. No System Reset question, no step 8, no reboot.
  - `full-wipe --yes WIPE` → same, with no questions.
  - `full-wipe` with no terminal → "No terminal to ask on — add --yes to confirm.", exit 3.
  - No ostree → "ERROR: ostree not found.", exit 3 before anything changes.
  - rpm-ostree failing → 2 WARNINGs, Done shows "2 problems", still returns to full_wipe_run (exit 3).
  - `reset-system` (y, then n to restart) → unchanged: its own question, step 4 runs the users plan, step 8 asks to restart, exit 0.
  - `full-wipe --dry-run` → runs to the Summary, exit 0; quarantine.log not counted.
  - Still refused (usage + exit 3): `--yes`, `--yes wipe`, `--dry-run --yes`, `WIPE --yes`.
- Note for 6c: full_wipe_run must exit 3 if RESET_ERRORS > 0 OR any Part 2-3 error (reset_system_run wipe now just returns).
- Next: Step 6c (Parts 2-4: erase homes, empty quarantine, restart).
