#!/usr/bin/env bash
# Tests for Drive Death Warning (Job 15), cases A-B: a healthy PC (report, history, status lines, plain words)
# and early signs (watch: bad spots, "getting worse", worn out, spare space, too hot, read errors).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-drivehealth.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/drivehealth-fakes.sh
. "$ROOT/tests/drivehealth-fakes.sh"
reasons() { DH status | grep "^REASON${T}" | cut -f 3; }

# A: a healthy desktop: report everyone can read (no serial numbers), private history, status, plain words
normal_pc
OUT="$(DH system-check --timer)"; RC=$?
check A1 '[ "$RC" -eq 0 ] && [ "$OUT" = "Checked 2 drive(s): good." ] && [ "$(stat -c %a "$REP")" = 644 ] && [ "$(stat -c %a "$HIS")" = 600 ] && ! grep -q SECRET "$REP" "$HIS"'
OUT="$(DH status)"; RC=$?
check A2 '[ "$RC" -eq 0 ] && grep -q "^CHECKED${T}[0-9]*${T}good$" <<< "$OUT" && grep -q "^DRIVE${T}[0-9a-f]\{12\}${T}good${T}Samsung SSD 990 PRO 1TB${T}NVMe SSD${T}1 TB${T}3${T}2${T}41${T}/dev/nvme0n1${T}no$" <<< "$OUT"'
check A3 'grep -q "^DRIVE${T}.*${T}good${T}WDC WD40EZAX-22C8UB0${T}hard drive${T}4 TB${T}-${T}3${T}35${T}/dev/sda${T}no$" <<< "$OUT" && grep -qx "BACKUP${T}none" <<< "$OUT" && ! grep -q "^REASON" <<< "$OUT"'
OUT="$(DH report)"; RC=$?
check A4 '[ "$RC" -eq 0 ] && grep -qx "Samsung SSD 990 PRO 1TB (NVMe SSD, 1 TB): Good. About 3% worn out, 2 years of use, 41 degrees C." <<< "$OUT" && grep -qx "WDC WD40EZAX-22C8UB0 (hard drive, 4 TB): Good. 3 years of use, 35 degrees C." <<< "$OUT"'
check A5 'grep -q "^No backup is set up yet. Drives can die without any warning" <<< "$OUT" && grep -qx "Some drives die with no warning at all, so keep your backup fresh." <<< "$OUT"'
check A6 'calls | grep -qx "smartctl -j -a /dev/nvme0n1" && calls | grep -qx "smartctl -j -a -l devstat /dev/sda" && ! calls | grep -q "smartctl.* -d sat"'
check A7 '[ "$(py "len(h[\"drives\"][r[\"drives\"][1][\"key\"]])")" = 1 ] && [ "$(py "r[\"danger_since\"]")" = 0 ] && [ "$(py "r[\"version\"]")" = 1 ]'
DH bogus >/dev/null 2>&1; R1=$?; DH status now >/dev/null 2>&1; R2=$?; FORGEOS_DH_ROOT=0 DH system-check >/dev/null 2>&1; R3=$?
check A8 '[ "$R1$R2$R3" = 333 ]'

# B: early signs = watch: bad spots, getting worse, worn out, low spare space, too hot, past problem, read error
normal_pc; rm -f "$REP" "$HIS"
smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 hours=26300 temp=35 bad=3
DH system-check >/dev/null; RC=$?
check B1 '[ "$RC" -eq 1 ] && [ "$(reasons)" = "The drive has 3 bad spots. That is an early warning sign." ] && DH status | grep -q "^DRIVE${T}.*${T}watch${T}WDC"'
day 1; smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 hours=26324 temp=35 bad=5
DH system-check >/dev/null
check B2 '[ "$(reasons)" = "Getting worse: 2 new bad spots since the last check." ] && DH report | grep -qx "WDC WD40EZAX-22C8UB0 (hard drive, 4 TB): WATCH - early signs. 3 years of use, 35 degrees C."'
day 2; DH system-check >/dev/null
check B3 '[ "$(reasons)" = "The drive has 5 bad spots. That is an early warning sign." ]'
normal_pc; rm -f "$REP" "$HIS"; day 0
smart nvme0n1 kind=nvme "model=Samsung SSD 990 PRO 1TB" serial=S6Z1NJ0SECRET worn=93 spare=18 temp=80 crit=2
DH system-check >/dev/null; RC=$?
check B4 '[ "$RC" -eq 1 ] && [ "$(reasons | tr "\n" "|")" = "The drive is about 93% worn out.|The drive'"'"'s spare space is running low.|The drive is running too hot (80 degrees C).|" ]'
normal_pc; rm -f "$REP" "$HIS"
smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 temp=56 past=Seek_Error_Rate
DH system-check >/dev/null
check B5 '[ "$(reasons | tr "\n" "|")" = "The drive is running too hot (56 degrees C).|The drive had a problem in the past (Seek Error Rate).|" ]'
normal_pc; rm -f "$REP" "$HIS"
DH system-check >/dev/null; day 1; btrfs_errs /dev/nvme0n1p3 2 0
DH system-check >/dev/null; RC=$?
check B6 '[ "$RC" -eq 1 ] && [ "$(reasons)" = "ForgeOS found a read error on this drive this week (it was handled)." ] && DH status | grep -q "^DRIVE${T}.*${T}watch${T}Samsung"'
day 10; DH system-check >/dev/null; RC=$?
check B7 '[ "$RC" -eq 0 ] && [ -z "$(reasons)" ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
