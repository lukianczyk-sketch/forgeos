#!/usr/bin/env bash
# Tests for Drive Death Warning (Job 15), case C: danger - the drive says it is failing, failed self-test,
# bad spots growing fast, many bad spots, damaged files; when the danger started is remembered.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-drivehealth-danger.sh <repo-root>
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

# C: danger: the drive says it is failing, failed self-test, bad spots growing fast, many bad spots, damaged files
normal_pc; rm -f "$REP" "$HIS"; day 0
smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 passed=0 failed=Raw_Read_Error_Rate exit=8
DH system-check >/dev/null; RC=$?
check C1 '[ "$RC" -eq 2 ] && [ "$(reasons)" = "The drive itself says it is failing (Raw Read Error Rate)." ] && DH report | grep -q "^A drive may be failing. Back up your files today"'
SINCE="$(py "r[\"danger_since\"]")"; day 1; DH system-check >/dev/null
check C2 '[ "$SINCE" != 0 ] && [ "$(py "r[\"danger_since\"]")" = "$SINCE" ] && DH report | grep -q "WDC.*: DANGER - this drive may be failing\."'
normal_pc; day 2; DH system-check >/dev/null
check C3 '[ "$(py "r[\"danger_since\"]")" = 0 ] && [ "$(py "r[\"level\"]")" = good ]'
smart nvme0n1 kind=nvme "model=Samsung SSD 990 PRO 1TB" serial=S6Z1NJ0SECRET crit=4 selftest=fail
DH system-check >/dev/null; RC=$?
check C4 '[ "$RC" -eq 2 ] && [ "$(reasons | tr "\n" "|")" = "The drive itself says it is failing.|The drive failed its own self-test.|" ]'
normal_pc; rm -f "$REP" "$HIS"; day 0
smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 bad=2; DH system-check >/dev/null
day 4; smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 bad=8; DH system-check >/dev/null
day 6; smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 bad=14; DH system-check >/dev/null; RC=$?
check C5 '[ "$RC" -eq 2 ] && [ "$(reasons)" = "Bad spots on the drive are growing fast (12 new this week)." ]'
normal_pc; rm -f "$REP" "$HIS"
smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 bad=150; DH system-check >/dev/null; RC=$?
check C6 '[ "$RC" -eq 2 ] && [ "$(reasons)" = "The drive has many bad spots (150)." ]'
normal_pc; rm -f "$REP" "$HIS"; btrfs_errs /dev/nvme0n1p3 0 4 3
DH system-check >/dev/null; RC=$?
check C7 '[ "$RC" -eq 2 ] && [ "$(reasons)" = "Some of your files on this drive were damaged and could not be repaired." ] && DH status | grep -q "^DRIVE${T}.*${T}danger${T}Samsung"'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
