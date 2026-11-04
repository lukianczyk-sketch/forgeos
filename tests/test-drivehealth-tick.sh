#!/usr/bin/env bash
# Tests for Drive Death Warning (Job 15), cases G-I: the danger warning (big window, or a critical note during
# games) every day until a fresh backup, then a weekly "replace it"; early signs go to Forge Helper and Ask
# Your PC; no backup at all = one note a month.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-drivehealth-tick.sh <repo-root>
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
tick() { : > "$WORK/calls.log"; DH tick; }
warned() { grep -c "^kdialog .*--warningyesno" "$WORK/calls.log"; }
noted() { grep -c "^notify-send" "$WORK/calls.log"; }

# G: danger: the big warning, Back up now opens the backup steps; once a day until a fresh backup
normal_pc; backup set 3
smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 passed=0 exit=8
DH system-check >/dev/null
echo 0 > "$WORK/kdialog-rc"; tick; RC=$?
check G1 '[ "$RC" -eq 2 ] && [ "$(warned)" = 1 ] && calls | grep -q "kdialog --title Drive Health --warningyesno Your drive may be failing: WDC WD40EZAX-22C8UB0\." && calls | grep -q "Why: The drive itself says it is failing\. --yes-label Back up now --no-label Remind me tomorrow$"'
check G2 'calls | grep -qx "gui --backup" && [ "$(stat -c %a "$WORK/state/forgeos/drivehealth.json")" = 600 ]'
echo 1 > "$WORK/kdialog-rc"; tick
check G3 '[ "$(warned)" = 0 ] && ! calls | grep -q "^gui"'
day 0.9; tick; A="$(warned)"; day 1; DH system-check >/dev/null; tick; B="$(warned)"
check G4 '[ "$A" = 1 ] && [ "$B" = 0 ] && ! calls | grep -q "^gui"'
day 1.8; echo "b true" > "$WORK/busctl-out"; echo go > "$WORK/notify-answer"; tick
check G5 '[ "$(warned)" = 0 ] && calls | grep -q "^notify-send .*--urgency=critical --action=go=Back up now .*Your drive may be failing" && calls | grep -qx "gui --backup"'
rm -f "$WORK/busctl-out" "$WORK/notify-answer"
day 2; backup set 0; tick; RC=$?
check G6 '[ "$RC" -eq 2 ] && [ "$(warned)" = 0 ] && calls | grep -q "^notify-send .*--urgency=normal --action=go=Show me .*Your files are backed up. WDC WD40EZAX-22C8UB0 may still fail"'
day 3; tick; A="$(noted)"; day 9.5; tick; B="$(noted)"
check G7 '[ "$A" = 0 ] && [ "$B" = 1 ]'

# H: early signs: no big warning, Forge Helper's quiet note instead; Ask Your PC's health check mentions it
normal_pc; rm -f "$REP" "$HIS" "$WORK/state/forgeos/drivehealth.json"; day 0
smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 bad=4
DH system-check >/dev/null; tick; RC=$?
check H1 '[ "$RC" -eq 1 ] && [ "$(warned)" = 0 ] && [ "$(noted)" = 0 ]'
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import checks
print(checks.check_drive())" "$ROOT/files/system/usr/lib/forgeos-helper")"
check H2 'grep -q "^(.drive., .Drive Health noticed early warning signs on WDC WD40EZAX-22C8UB0: The drive has 4 bad spots\. That is an early warning sign\. Your files are fine for now; a fresh backup keeps them safe\.., .open., .drivehealth., .Show me.)$" <<< "$OUT"'
OUT="$(bash -c '. "$1"; health_check' _ "$ROOT/files/system/usr/libexec/forgeos-askpc-lib" 2>/dev/null)"
check H3 'grep -qx "! A drive shows early warning signs (WDC WD40EZAX-22C8UB0). Open Drive Health." <<< "$OUT"'
normal_pc; DH system-check >/dev/null
OUT="$(bash -c '. "$1"; health_check; status_report' _ "$ROOT/files/system/usr/libexec/forgeos-askpc-lib" 2>/dev/null)"
check H4 'grep -qx "OK Drive health" <<< "$OUT" && grep -qx "Drive health (Drive Health app): good" <<< "$OUT"'
smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 passed=0; DH system-check >/dev/null
OUT="$(bash -c '. "$1"; health_check' _ "$ROOT/files/system/usr/libexec/forgeos-askpc-lib" 2>/dev/null)"
check H5 'grep -qx "! A drive may be failing (WDC WD40EZAX-22C8UB0). Back up your files today - open Drive Health." <<< "$OUT" && python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from helperlib import checks
assert checks.check_drive() is None" "$ROOT/files/system/usr/lib/forgeos-helper"'

# I: no backup set up at all: one quiet note a month, its button opens the backup steps; none without a report
normal_pc; rm -f "$WORK/state/forgeos/drivehealth.json"; backup none; DH system-check >/dev/null
echo go > "$WORK/notify-answer"; tick; RC=$?
check I1 '[ "$RC" -eq 0 ] && calls | grep -q "^notify-send .*--action=go=Set up a backup .*You have no backup yet" && calls | grep -qx "gui --backup"'
day 20; tick; A="$(noted)"; day 31; tick; B="$(noted)"
check I2 '[ "$A" = 0 ] && [ "$B" = 1 ]'
day 70; touch "$WORK/gamescope"; tick; A="$(noted)"; rm -f "$WORK/gamescope"; backup set 1; tick; B="$(noted)"
check I3 '[ "$A" = 0 ] && [ "$B" = 0 ]'
rm -f "$REP"; tick; RC=$?
check I4 '[ "$RC" -eq 3 ] && [ "$(noted)" = 0 ] && [ "$(warned)" = 0 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
