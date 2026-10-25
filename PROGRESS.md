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

## Step 6c — full-wipe real run parts 2-4 (erase homes, empty quarantine, restart) — 2026-10-24
Files changed: files/system/usr/bin/forgeos-cleansweep (plus this PROGRESS.md entry)
What Rabbit Team / Cline did (one file):
- Globals: `WIPE_ERRORS=0    # problems during a real wipe (Step 6c)` right below the `WIPE_USERS=0` line.
- wipe_users_plan(): comment block replaced — now "Full Wipe Part 2 (Steps 6a/6c)", says mode "apply" really erases, and that only real folders under /home or /var/home are touched (checked by text AND by realpath).
- wipe_users_plan(): `local user uid home size` replaced with two lines: `local mode="${1:-plan}"` + `local user uid home size real`.
- wipe_users_plan(): right above the du line, added the realpath guard — `real="$(realpath -e -- "$home" 2>/dev/null)" || real=""`, then a case that skips (with "SKIP … (real path is outside /home — not erased)") unless $real matches /home/?*|/var/home/?*.
- wipe_users_plan(): right below `WIPE_USERS=$((WIPE_USERS + 1))`, added the mode "apply" block — erase contents with `find "$real" -mindepth 1 -maxdepth 1 -exec rm -rf --one-file-system -- {} +` (failure → WARNING + WIPE_ERRORS+1 + continue), then `runuser -u "$user" -- cp -a /etc/skel/. "$real/"` (failure → WARNING + count), then `passwd -e "$user"` (failure → WARNING + count).
- full_wipe_run(): its 2 comment lines replaced with "# Real run (Steps 6b-6c): two confirmations, then Part 1 (System Reset)," / "# Part 2 (erase homes), Part 3 (empty quarantine), Part 4 (restart)."
- full_wipe_run(): the stub (`log "Parts 2-4 come in Step 6c."` + `exit 3`) replaced with: "Part 2 — Erase personal files:" + `wipe_users_plan apply`; "Part 3 — Empty the quarantine:" + `find "$QUAR_DIR" -mindepth 1 -delete` (success → "Quarantine emptied.", failure → WARNING + WIPE_ERRORS+1); "Wipe done: $WIPE_USERS personal folders erased, $((RESET_ERRORS + WIPE_ERRORS)) problems."; "Part 4 — Restart:" (YES=1 → no reboot here, note only; else confirm "Restart now to finish the wipe?" → systemctl reboot or later-finish note); exit 3 if RESET_ERRORS+WIPE_ERRORS > 0, else exit 0.
What I ran: nothing (per instruction).
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 6c — 2026-10-24
- APPROVED. Code matches the blueprint. 2 fixes (Claude applied):
  1. **skel copy without `-a`:** `cp -a` tries to keep /etc/skel's SELinux label on the new files in the home. Now `runuser -u "$user" -- cp -R --preserve=mode,timestamps -- /etc/skel/. "$real/"` — files are created by the user, so they get the user as owner and the normal home-folder label.
  2. **Missing quarantine folder is not an error:** Part 3 now says "Quarantine is already empty." if $QUAR_DIR doesn't exist, instead of a WARNING + exit 3.
- Cancelled Cline during its final "verify" re-read (all 7 script edits + PROGRESS entry were already saved).
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean, no CRLF.
- Sandbox tests (PATH shims for id/ostree/rpm-ostree/flatpak/systemctl/passwd/runuser/getent that log their calls; fixture passwd; /home check + skel pointed at test folders; scan, /etc, clears, users and image-ref stubbed; real terminal via `script`):
  - `full-wipe --dry-run` → bob + amy ERASE; eve (outside /home), lnk (home is a symlink), esc (home under a symlinked folder → real path outside /home) SKIP; missing home + UID 65534 not listed; exit 0; nothing changed.
  - `full-wipe --yes WIPE` → bob + amy emptied (incl. hidden files and sub-folders) and refilled from skel; eve + esc untouched; quarantine (files + quarantine.log) emptied; runuser + `passwd -e` per user; "Wipe done: 2 … 0 problems."; no reboot; exit 0.
  - Interactive y / WIPE / restart y → `systemctl reboot`, exit 0. Restart n → no reboot, exit 0. First answer n → cancelled, nothing run, files untouched.
  - Erase fails (read-only sub-folder in amy) → WARNING, skel copy skipped for amy, "1 problems", exit 3.
  - skel copy fails (unreadable skel sub-folder) → WARNING per user, exit 3.
  - rpm-ostree failing → "2 problems" (RESET_ERRORS counted), exit 3.
  - `reset-system` (y, n) unchanged, homes untouched; still refused (exit 3): `--yes`, `--yes wipe`, `--dry-run --yes`.
- Next: Step 7 (GUI + weekly timer).

## Step 7a — Clean Sweep window: menu + Scan Now — 2026-10-24
Files changed: files/system/usr/bin/forgeos-cleansweep-gui (plus this PROGRESS.md entry)
What Rabbit Team / Cline did:
- Header: line 1 `#!/usr/bin/env bash`, then the Step 7a comment, then `set -uo pipefail`, `TITLE="ForgeOS Clean Sweep"`, and `ENGINE="/usr/bin/forgeos-cleansweep"`.
- has_gui(): returns 0 only when `${DISPLAY:-}${WAYLAND_DISPLAY:-}` is not empty.
- ask_yes_no "<question>": kdialog `--warningyesno` → zenity `--question` → terminal `[y/N]` prompt; returns the dialog's exit code (or 0/1 for a y/n answer in the terminal).
- say <info|error> "<text>": kdialog (`--msgbox` for info / `--error`) → zenity (`--info` / `--error`) → `echo`; every dialog command ends with `|| true`.
- pick_action: shows the 3-item menu (kdialog `--menu`, zenity `--list --hide-column=1 --print-column=1`, or a numbered terminal list) and prints one word — scan/reset/wipe — on stdout, or nothing if cancelled/failed.
- run_scan: optional kdialog progressbar, runs `pkexec "$ENGINE" scan` (saving rc), closes the progressbar via dbus-send when present, then maps rc 0 / 1 / 2 / 126|127 / * to info/error messages; always returns 0.
- main: `action="$(pick_action)"`; scan → run_scan, reset|wipe → "This button comes in the next update.", anything else → exit 0; then exit 0. Last line of the file is `main "$@"`.
- Each function has a single-line comment above it; no other features added.
What I ran: nothing (per instruction).
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 7a — 2026-10-24
- APPROVED. Code matches the blueprint. 3 fixes (Claude applied):
  1. **Terminal menu was swallowed:** main runs `action="$(pick_action)"`, so the numbered menu (echoed to stdout) was captured as the answer and never shown. Menu + a "Choose 1-3 (Enter to quit): " prompt now go to stderr; ask_yes_no's `[y/N]` prompt and terminal error messages also go to stderr.
  2. **Exit 127 now explained:** 126 (password box closed) still does nothing; 127 (account not allowed) shows "Your account is not allowed to run Clean Sweep. Sign in as an administrator and try again."
  3. **Small polish:** dbus-send output silenced (`>/dev/null 2>&1`); exit 1 and 2 messages now point to the full report at `~/.local/state/forgeos/clean-sweep/last-report.txt`.
- Cline's first whole-file replace failed because the GUI file had CRLF line endings on disk. Claude converted it to LF (`sed -i 's/\r$//'`); Cline's next replace went through. Cancelled Cline's final "verify" re-read.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean (only info: ask_yes_no not used yet — used in 7b), no CRLF.
- Tests (fake kdialog/zenity/pkexec/dbus-send that log their calls):
  - kdialog, Scan Now, pkexec exit 0/1/2/3 → busy bar opened, `pkexec /usr/bin/forgeos-cleansweep scan`, bar closed via dbus, then the right msgbox/error; GUI exits 0.
  - pkexec 126 → bar closed, no message. 127 → "not allowed" error.
  - Menu reset / wipe → "This button comes in the next update." Menu cancelled → nothing, exit 0.
  - zenity only (no kdialog) → zenity list + zenity info; no progress bar.
  - No GUI (no DISPLAY/WAYLAND_DISPLAY): menu shows on the terminal; 1 → scan, 2/3 → "next update", Enter / x / closed stdin → quit, exit 0.
- Next: Step 7b (System Reset + Full Wipe buttons in the GUI).

## Step 7b — Clean Sweep window: System Reset + Full Wipe buttons — 2026-10-24
Files changed: files/system/usr/bin/forgeos-cleansweep-gui (plus this PROGRESS.md entry)
What Rabbit Team / Cline did (one file, small replace edits):
- Item 1: new ask_wipe_word() below run_scan — kdialog `--inputbox` → zenity `--entry` → terminal prompt on stderr + `read -r word || word=""`; prints the typed word on stdout, nothing if cancelled; always returns 0.
- Item 2: new offer_restart() — asks via ask_yes_no "$1"; on yes runs `systemctl reboot`, and if that fails says "Could not restart. Please restart the computer yourself."; always returns 0.
- Item 3: new run_engine() — opens the kdialog progressbar with text $1 (only when has_gui + kdialog), shifts, runs `pkexec "$ENGINE" "$@"`, saves rc, closes the bar with the same dbus-send line as run_scan (`>/dev/null 2>&1 || true`), then returns the engine's exit code.
- Item 4: new run_reset() — confirmation dialog (cancel → return 0), then `run_engine "Resetting your PC — this can take a while..." reset-system --yes`; rc 0 → offer_restart; 3 → error + offer_restart anyway; 126 → silent return 0; 127 → same "not allowed" error as run_scan; * → could-not-finish error pointing at /var/log/forgeos/clean-sweep/; always returns 0.
- Item 5: new run_wipe() — first ask_yes_no (cancel → return 0), then `word="$(ask_wipe_word)"`; if not exactly WIPE → info "Full Wipe cancelled. Nothing was changed." + return 0; else `run_engine "Wiping your PC — this can take a while..." full-wipe --yes WIPE` with the same rc mapping as run_reset (Full Wipe wording); always returns 0.
- Item 6: main now dispatches `reset) run_reset ;;` and `wipe) run_wipe ;;` (replacing the "This button comes in the next update." placeholder).
- Item 7: line 2 comment is now "# Clean Sweep window (Steps 7a-7b): main menu with Scan Now, System Reset and Full Wipe."
What I ran: nothing (per instruction).
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 7b — 2026-10-24
- APPROVED, no fixes needed. Code matches the blueprint: the GUI asks its own confirmations, then runs the engine with `--yes` (the engine never reboots by itself with `--yes`; the GUI offers the restart).
- Cancelled Cline's final "verify" re-read (all script edits + PROGRESS entry were already saved). File was already LF (no CRLF).
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean.
- Tests (fake kdialog/zenity/pkexec/dbus-send/systemctl that log their calls):
  - Reset: yes → busy bar, `pkexec /usr/bin/forgeos-cleansweep reset-system --yes`, bar closed, restart asked; yes → `systemctl reboot`, no → nothing. First answer no → engine never runs.
  - Reset rc 3 → "finished with some problems" error + restart still offered. 126 → silent. 127 → "not allowed". Other (2) → "could not finish".
  - Wipe: yes + WIPE → `pkexec … full-wipe --yes WIPE` + restart offered. Lowercase "wipe" / inputbox cancelled → "Full Wipe cancelled. Nothing was changed.", engine never runs. First answer no → nothing.
  - Wipe rc 3 + reboot failing → problems error, then "Could not restart. Please restart the computer yourself."
  - zenity only → zenity list/question/entry path works end to end.
  - No GUI (terminal): reset y/n, wipe y + wrong word (cancelled), wipe y + WIPE + y (reboot) all correct.
  - Scan Now unchanged.
- Next: Step 7c (weekly timer + desktop notification).

## Step 7c — Clean Sweep weekly scan timer — 2026-10-24
Files changed: files/system/usr/lib/systemd/system/forgeos-cleansweep.service (new), files/system/usr/lib/systemd/system/forgeos-cleansweep.timer (new), files/system/usr/libexec/forgeos-cleansweep-weekly (new), files/scripts/forgeos-setup.sh, plus this PROGRESS.md entry
What Rabbit Team / Cline did:
- Item 1: new forgeos-cleansweep.service — Type=oneshot, ExecStart=/usr/libexec/forgeos-cleansweep-weekly, Nice=19, IOSchedulingClass=idle (exactly as specified).
- Item 2: new forgeos-cleansweep.timer — OnCalendar=Sun *-*-* 03:00:00, Persistent=true (catches up after a missed run), RandomizedDelaySec=15min, WantedBy=timers.target (exactly as specified).
- Item 3: new /usr/libexec/forgeos-cleansweep-weekly — `set -uo pipefail`; ENGINE=/usr/bin/forgeos-cleansweep, RUN_DIR="${RUN_DIR:-/run/user}"; notify_all loops over "$RUN_DIR"/*/bus, skips non-sockets (`[ -S ]`), takes the folder name as uid and skips uids that are not all digits or < 1000, resolves the account with `id -nu … || continue`, then sends a desktop notification via runuser + gdbus on that user's session bus (app "Clean Sweep", icon security-high, silenced, `|| true`); main runs `"$ENGINE" scan` and saves rc — rc 1 → notify_all "Clean Sweep found threats" (quarantine + /var/log/forgeos/clean-sweep/), rc 2 → notify_all "Clean Sweep: your system was changed" (choose System Reset), any other rc → nothing; one single-line comment above each function, last line `exit 0` so the timer never shows as failed.
- Item 4: forgeos-setup.sh — added /usr/libexec/forgeos-cleansweep-weekly to the existing chmod 0755 list (line 5); after `systemctl enable clamav-freshclam.service` added a blank line, the Step 7c comment, and `systemctl enable forgeos-cleansweep.timer`.
What I ran: nothing (per instruction).
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 7c — 2026-10-24
- APPROVED. Logic matches the blueprint. 4 fixes (Claude applied):
  1. **CRLF:** all 3 new files had Windows line endings (Cline on Windows) — converted to LF (a CRLF shebang would break the script on Linux).
  2. **RUN_DIR is now fixed at /run/user** (was `${RUN_DIR:-/run/user}`) — a root script should not take paths from the environment. Tests sed it instead.
  3. **Urgent notification:** hints changed from `{}` to `{'urgency': <byte 2>}` (critical) so the warning stays on screen until the user sees it.
  4. **Unit files:** added the header comment lines; removed `After=network-online.target` from the service (not needed — the scan is offline and an After without Wants does nothing).
- Cline's own deviations kept: `set -uo pipefail`, engine output goes to the journal (useful for `journalctl -u forgeos-cleansweep`), loop over `"$RUN_DIR"/*/bus`.
- Cancelled Cline's final "verify" re-read (all edits + PROGRESS entry were saved).
- Checked on Linux: `bash -n` OK, `shellcheck` clean (no findings at any level), `systemd-analyze verify` OK on both units, `systemd-analyze calendar "Sun *-*-* 03:00:00"` → next run Sunday 03:00.
- Tests (fake engine/runuser/gdbus/id + a fake /run/user with real sockets):
  - Engine rc 0 / 3 / 7 → no notifications, script exits 0.
  - rc 1 → "Clean Sweep found threats" sent to uid 1000 and 1001 only, each on its own bus via `runuser -u <name>`; rc 2 → "your system was changed" message, same users.
  - Skipped correctly: uid 0 and 42 (system), 1002 (no account), 1003 (bus is a plain file, not a socket), "abc" (not a number).
  - gdbus failing → still exits 0. Empty /run/user → no calls, exits 0.
- Next: Step 7d (.desktop update: shield icon + Comment; no-args switches from legacy_sweep).

## Step 7d — remove v1 sweep + menu entry update — 2026-10-24
Files changed: files/system/usr/bin/forgeos-cleansweep, files/system/usr/share/applications/forgeos-cleansweep.desktop, plus this PROGRESS.md entry
What Rabbit Team / Cline did (small replace edits only):
- Item 1 (engine): deleted the whole old v1 block — from "# The original v1 sweep, kept working until the new GUI lands (Step 7)." through the closing "}" of legacy_sweep() (the "}" after "exit 0" following "Removed items are kept in $QUAR. Full log: $LOG"). Done as three small deletions; one blank line and the next comment ("# forgeos-cleansweep reset-system (Step 5a-1)...") left untouched.
- Item 2 (engine): argument parsing — `"" ) CMD="legacy"` is now `""|-h|--help|help) usage; exit 0 ;;`.
- Item 3 (engine): final dispatch — removed the trailing `else legacy_sweep` branch, so it ends at `elif [ "$CMD" = "wipe" ]; then full_wipe fi`.
- Item 4 (engine): argument-parsing comment — "#   (no args)            -> legacy v1 sweep" is now "#   (no args) / -h / --help / help -> show usage, exit 0 (Step 7d)".
- Item 5 (engine): usage() — "(no command)  Run the original v1 clean sweep (kept until the new GUI lands, Step 7)" is now "(no command), -h, --help  Show this help".
- Item 6 (engine): reset_image_ref comment — "same logic as legacy" replaced with "reads the image the same way:"; the rest of that comment is unchanged.
- Item 7 (.desktop): Comment= is now "Scan for viruses, lock threats away, or reset your PC to a clean state".
- Item 8 (.desktop): Keywords= is now "hacked;virus;malware;antivirus;scan;quarantine;reset;wipe;clean;security;" — Icon=security-high and every other line left as is.
What I ran: nothing (per instruction).
STATUS: WAITING FOR CLAUDE REVIEW

### Claude review — Step 7d — 2026-10-24
- APPROVED. All 8 items match the blueprint; the v1 sweep is fully gone (no "legacy" left anywhere in files/). 3 fixes (Claude applied):
  1. **Top-of-file comment** still described the v1 reset and said "with no arguments the original v1 sweep still runs" — rewritten to describe what Clean Sweep does now (scan + quarantine, reset-system, full-wipe; run with --help).
  2. **reset_image_ref comment** read "reads the image the same way: sweep step 1 — read …" (dangling reference to the deleted sweep) — now "read the booted deployment's container-image-reference and force the ostree-image-signed form."
  3. **Help goes to stdout:** `""|-h|--help|help) usage 2>&1; exit 0` — when the user ASKS for help it now prints on stdout (so `forgeos-cleansweep --help | less` works); wrong arguments still print usage on stderr with exit 3.
- Line endings: all 3 files LF (no CRLF this time).
- Checked on Linux: `bash -n` OK; `shellcheck -S warning` clean (only the old, intended SC2016 info on the `sh -c '…"$1"…'` report copy).
- Tests (non-root): no args / `-h` / `--help` / `help` → usage on stdout, exit 0, before the root check; `bogus` → exit 3; `scan extra` → exit 3; `scan` as non-root → "must run as administrator", exit 3.
- Tests (sandbox, fake root, stubbed scan_steps): `scan` passes through 0 / 1 / 2 / 3; no args as root → usage, exit 0, nothing created; `quarantine list` → "Quarantine is empty.", exit 0.
- GUI (`pkexec "$ENGINE" scan` / `"$@"`) and the weekly timer (`"$ENGINE" scan`) never call the engine with no arguments — nothing else depended on the old default.
- .desktop: Comment + Keywords updated, Icon=security-high kept; checked by hand (desktop-file-validate not available in the test VM).
- Next: Step 8 — tests/test-clean-sweep.sh + EICAR test in CI (extend tests.yml), then final review → tag v0.5.0.

## Step 8a — scan tests — 2026-10-25
Files changed: tests/test-clean-sweep.sh (new), plus this PROGRESS.md entry
What Rabbit Team / Cline did:
- First attempt (old prompt) looped ~20 min re-reading the engine without writing anything — Claude cancelled it and gave a self-contained prompt (all engine facts inline, no reading).
- Wrote tests/test-clean-sweep.sh in one write: sed-rewritten engine copy in a mktemp work dir (LOG_DIR / QUAR_DIR / RESET_BK_DIR), fake bin dir (id -u → 0, rpm-ostree signed JSON, ostree config-diff via FAKE_DIFF, rkhunter exit FAKE_RKH_RC, chkrootkit 0, clamscan with FAKE_INFECTED → FOUND + --move + "moved to" line), run() helper, cases A–G.
- Stalled on how to append to PROGRESS.md without reading it — Claude cancelled and wrote this entry.
STATUS: REVIEWED

### Claude review — Step 8a — 2026-10-25
- APPROVED. All 7 cases match the blueprint. 4 fixes (Claude applied):
  1. **CRLF:** the whole file had Windows line endings — converted to LF.
  2. **Engine missing → clear FAIL + exit 1** up front (was: every case failing with confusing rc values).
  3. **Case B is stricter:** also checks quarantine.log field 2 = the original path and field 4 = "Eicar-Test-Signature" (so a broken threat-name lookup is caught).
  4. shellcheck tidy: report found with a glob instead of `ls | head` (SC2012); final `&& exit 1 || exit 0` → plain if.
- Checked on Linux (device VM): `bash -n` OK, `shellcheck` clean (no findings at any level). Run: 7/7 PASS, exit 0, ~0.4 s. Work dir (incl. the chmod-000 quarantined file) is fully removed by the EXIT trap — no tmp.* left behind.
- Mutation tests (broke the engine on purpose, each must be caught): no chmod 000 → B fails; never moves → B fails; threat name lost → B fails; tamper ignored → D fails; rkhunter error ignored → E fails; wrong headline → A fails; engine missing → FAIL + exit 1. All caught.
- Not wired into CI yet (Step 8c).
- Next: Step 8b — more cases in the same file: quarantine list / restore / delete --yes, reset-system --dry-run keep-list, full-wipe without WIPE refuses / --dry-run.

## Step 8b — quarantine / reset / wipe tests — 2026-10-25
Files changed: tests/test-clean-sweep.sh (fake runuser shim, run_keep(), cases H-N, header comment), plus this PROGRESS.md entry
What Rabbit Team / Cline did:
- EDIT 1: fake `runuser` shim in $WORK/bin right after `unset PKEXEC_UID` — drops every argument up to and including "--", then execs the rest; chmod +x (same style as the other shims).
- EDIT 2: added run_keep() right after run() — same as run() but WITHOUT deleting $WORK/log and $WORK/quar, so the quarantine survives between steps; still writes $WORK/out and sets RC.
- EDIT 3: cases H-N inserted before the failures summary (one pass/fail line each): H list -> RC 0, ID = field 1 of line 2 ($WORK/out via awk -F'\t'), out contains Eicar-Test-Signature; I restore without --yes -> RC 3 (chmod u+r $WORK/quar/$ID first — the engine runs as root and can read a mode-000 file, this test is a normal user); J restore --yes -> RC 0, bad.txt back with mode 640, quarantine entry gone; K delete --yes -> RC 0 + entry gone, then list says "Quarantine is empty."; L restore ../x --yes -> RC 3 + "Bad ID"; M reset-system --dry-run -> RC 0 with KEEP /etc/hostname, KEEP /etc/passwd, REMOVE /etc/ld.so.preload, "1 to remove", "2 kept" (KEEP+5 spaces, REMOVE+3); N full-wipe safety -> `full-wipe --yes NOPE` RC 3, `full-wipe </dev/null` RC 3 (refuses before changing anything), `full-wipe --dry-run` RC 0 + "Full Wipe plan" — one pass line only if all three are right.
- EDIT 4: header comment now says cases A-N (scan, quarantine, reset plan, full-wipe safety).
What I ran: nothing (per instruction).
STATUS: REVIEWED

### Claude review — Step 8b — 2026-10-25
- APPROVED. All 5 edits match the blueprint; LF line endings this time. 4 safety/strength fixes (Claude applied):
  1. **The test can never touch the real machine.** If a future engine bug let full-wipe / reset start for real, it would empty /tmp + /var/tmp and erase homes. Now the engine copy also has ETC_DIR, USR_ETC_DIR, TMP_DIR and VARTMP_DIR pointed into the work dir; a guard checks all 7 dir lines were rewritten (FAIL + exit 1 if an engine line changes); fake `getent passwd` lists only root + a "tester" whose home is inside the work dir (not under /home, so never erased); systemctl / flatpak / passwd are no-op fakes.
  2. **N checks the wipe really did not start:** RC 3 alone was not enough — a broken `--yes <any word>` ran the wipe and still exited 3 (non-root errors). Both refusals now also require no "Full Wipe started" in the output. N's dry-run also checks "SKIP     tester" (the fake home is skipped, never erased).
  3. **Empty ID guard:** if case H finds no ID, later cases use "missing" instead of acting on the quarantine folder itself.
  4. Header comment updated for the new fakes.
- Checked on Linux: `bash -n` OK, `shellcheck` clean (no findings). Run: 14/14 PASS, exit 0, < 1 s; no tmp.* left behind.
- Mutation tests (each must be caught): confirm ignores no-terminal → I + N fail; restore loses the mode → J fails; delete does nothing → K fails; ".." allowed in ID → L fails; ld.so.preload on the keep-list → M fails; full-wipe accepts any word after --yes → N fails; engine dir line renamed → guard FAIL. All caught (plus the 8a ones still caught).
- Next: Step 8c — tests.yml: run `bash tests/test-clean-sweep.sh .` in CI + real ClamAV EICAR test (apt install clamav, EICAR string, confirm FOUND). Then final review → tag v0.5.0.

## Step 8c — real ClamAV test + CI — 2026-10-25
Files changed: tests/test-clean-sweep.sh (skip() helper, case O, header), .github/workflows/tests.yml (two new steps at the end of test-ai-setup), plus this PROGRESS.md entry
What Rabbit Team / Cline did:
- EDIT 1: added `skip()` right after `fail()` — prints "SKIP: …" without counting a failure.
- EDIT 2: case O inserted as the LAST case, right before the failures summary (it replaces the fake clamscan when REAL_CLAMAV=1): harmless sample + our own md5 signature in $WORK/test.hdb (no EICAR anywhere), wrapper keeps only the engine's "-" options and points real clamscan at that signature file scanning only $WORK/scan; checks dry-run leaves the file, then scan exits 1, quarantines it with mode 0, quarantine.log has the original path + threat "ForgeOS.Test.Signature.UNOFFICIAL"; otherwise a skip line.
- EDIT 3: header comment now says "Job 3 Step 8c: cases A-O (scan, quarantine, reset plan, full-wipe safety, real ClamAV when REAL_CLAMAV=1)".
- EDIT 4: tests.yml — two steps at the end of test-ai-setup: run `bash tests/test-clean-sweep.sh .` with fake tools, then install clamav from Ubuntu repos and re-run with REAL_CLAMAV=1.
What I ran: nothing (per instruction).
STATUS: REVIEWED

### Claude review — Step 8c — 2026-10-25
- APPROVED, no fixes needed. All 4 code edits match the blueprint exactly; LF line endings; header + PROGRESS entry correct.
- Prototyped first with REAL ClamAV 1.5.4 (Ubuntu 22.04 debs, same version the CI runner installs): a custom md5 signature (`md5:size:ForgeOS.Test.Signature`) is reported as `ForgeOS.Test.Signature.UNOFFICIAL FOUND`, clamscan exits 1 and prints `<path>: moved to '<dest>'` — the format the engine parses. No EICAR string anywhere (Windows Defender on the dev PC).
- CI note: `apt-get install clamav` pulls clamav-freshclam, which ships `/etc/clamav/certs` — without it clamscan cannot load any database (checked: "Invalid certs directory"). `--no-install-recommends` still installs it (it is a Depends).
- Checked on Linux: `bash -n` OK, `shellcheck` clean. Fake tools: 14 PASS + "SKIP: O", exit 0. Real ClamAV (REAL_CLAMAV=1): 15/15 PASS, exit 0; no tmp.* left behind.
- Mutation tests with real ClamAV (each must fail O): never moves → O fails; threat name lost → O fails; no chmod 000 → O fails; threats not counted (exit 0) → O fails. All caught.
- Next: Step 8d — engine fix: real clamscan prints `<path> (real path: '<real>'): moved to '<dest>'` when a scanned path goes through a symlink; pass 2 must look up the threat by `<path>` and record `<real>` as the original location. Add case P (fake clamscan printing that form). Then final review → tag v0.5.0.

### Rabbit Team — Step 8d — 2026-10-25
- Engine: run_clamscan pass 2 now handles "<path> (real path: '<real>'): moved to" — threat looked up by <path>, quarantine.log records <real>.
- Tests: fake clamscan prints the real-path form when FAKE_REALPATH is set; new case P (symlinked folder) before case O.
ran: nothing (per instruction).
STATUS: READY FOR REVIEW

### Claude review — Step 8d — 2026-10-25
- APPROVED, no fixes needed. Engine and test match the prototype byte-for-byte (except the updated header line 2 — correct). LF line endings in all 3 files; PROGRESS entry correct.
- Confirmed with REAL ClamAV 1.5.4 through a symlinked folder: the FOUND line uses `<link path>`, while the move line is `<link path> (real path: '<real>'): moved to '<dest>'` — exactly the form the fix handles.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean. Fake tools: 15 PASS + "SKIP: O", exit 0. Real ClamAV (REAL_CLAMAV=1): 16/16 PASS, exit 0; no tmp.* left behind.
- Old engine (before 8d): P fails (orig = "<path> (real path: '…')", threat unknown, restore rc 3).
- Mutation tests (each must fail P): threat looked up by orig → caught; orig not replaced by real path → caught; key not reset to <path> → caught; regex broken → caught.
- Next: final review of Job 3 → tag v0.5.0.

### Rabbit Team — Step 8e — 2026-10-25
- Engine: passwd -e replaced by add_password_reminder (autostart reminder written as the user) in reset and full wipe; help text lists startup audit.
- GUI: reset + wipe confirm texts mention the new password.
- New /usr/libexec/forgeos-password-reminder (+ chmod in forgeos-setup.sh). Test case Q.
ran: nothing (per instruction).
STATUS: READY FOR REVIEW

### Claude review — Step 8e — 2026-10-25
- APPROVED. All edits match the blueprint (engine helper + 2 call sites + help text, GUI texts, setup.sh chmod, new reminder script, test case Q, header). 1 fix (Claude applied): the new file `files/system/usr/libexec/forgeos-password-reminder` came out CRLF (25 lines) → converted to LF.
- Why: `passwd -e` locked users out — the SDDM / KDE login screen cannot change an expired password. Now reset and full wipe write `~/.config/autostart/forgeos-password-reminder.desktop` AS the user (runuser, so a symlink in their home cannot redirect it). The reset's startup clean-up keeps `forgeos-*` entries, so the reminder survives.
- Reminder script checked with fake kdialog: Yes → removes its autostart entry and opens `systemsettings kcm_users`; No → entry stays, asks again next login; always exits 0.
- Checked on Linux: `bash -n` OK, `shellcheck -S warning` clean on all 5 scripts; all LF. Fake tools: 16 PASS + "SKIP: O", exit 0. Real ClamAV 1.5.4 (REAL_CLAMAV=1): 17/17 PASS, exit 0; no tmp.* left behind.
- Mutation tests (each must fail Q): reset back to passwd -e → caught; wipe back to passwd -e → caught; wrong Exec path → caught; plan text changed → caught; no [Desktop Entry] header → caught; chmod missing in setup.sh → caught; wrong autostart folder → caught. 7/7.
- Final review of Job 3 complete. Next: CI green → tag v0.5.0 → Job 5 (Undo Button) blueprint.
