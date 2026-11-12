#!/usr/bin/env bash
# Tests for Plain-English Errors (Job 23), case A: the built-in library passes its own check (every example finds
# its entry, fixes are on the checked list), known errors get the right card, fake "virus" errors are called a
# scam BEFORE the library, catch-alls lose to exact errors, and nothing is understood = said honestly.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-errors.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/errors-fakes.sh
. "$ROOT/tests/errors-fakes.sh"
key() { ER explain "$1" | grep "^CARD$T" | cut -f2 | cut -d/ -f1; }

# A1: the library: about 150 errors, every example finds its own entry, all fixes on the checked list
OUT="$(ER check)"; CODE=$?
N="$(grep -o "^[0-9]*" <<< "$OUT")"
check A1 '[ "$CODE" = 0 ] && [ "$N" -ge 135 ] && grep -q "all good.$" <<< "$OUT"'
# A2: a known error -> the whole card: what happened / is it serious / what to do / the rule / Fix it
fresh; OUT="$(ER explain "The application was unable to start correctly (0xc000007b). Click OK to close the application.")"; CODE=$?
check A2 '[ "$CODE" = 0 ] && [ "$(sed -n 1p <<< "$OUT")" = "A Windows program could not start" ] && grep -q "^What happened: This Windows program is missing a part" <<< "$OUT" && grep -qx "Is it serious? Not serious." <<< "$OUT" && grep -q "^What to do: " <<< "$OUT" && grep -qx "Real errors never show a phone number and never ask for money." <<< "$OUT" && grep -qx "CARD${T}win-0xc000007b${T}green${T}A Windows program could not start" <<< "$OUT" && grep -qx "FIX${T}open:willitrun${T}Open Will It Run?" <<< "$OUT"'
# A3: the right entry for real errors from many places
check A3 '[ "$(key "This site cant be reached. DNS_PROBE_FINISHED_NXDOMAIN")" = web-nxdomain ] && [ "$(key "Error: Connection activation failed: Secrets were required, but not provided.")" = wifi-password ] && [ "$(key "cp: error writing x: No space left on device")" = disk-full ] && [ "$(key "Printer HP stopped: Filter failed")" = print-filter-failed ] && [ "$(key "Easy Anti-Cheat is not installed")" = game-anticheat ] && [ "$(key "Segmentation fault (core dumped)")" = segfault ]'
# A4: a catch-all loses to an exact error (not private + DATE_INVALID = the clock card, not the fake-site card)
check A4 '[ "$(key "Your connection is not private. NET::ERR_CERT_DATE_INVALID")" = cert-date ] && [ "$(key "Your connection is not private")" = cert-generic ] && [ "$(key "Permission denied")" = permission-denied ]'
# A5: a fake "virus" error with a phone number = red scam card, even with real error words in it
OUT="$(ER explain "Windows Defender Security Alert: your PC is infected (error 0x80070005). Call Microsoft Support 1-888-555-0199 immediately")"
check A5 'grep -qxE "CARD${T}scam-fake-error/[0-9a-f]{10}${T}red${T}This is a scam, not a real error" <<< "$OUT" && grep -qx "Is it serious? Serious. Act now." <<< "$OUT" && grep -q "it shows a phone number to call" <<< "$OUT" && grep -qx "FIX${T}techguard:escape${T}Close all web browsers now (the scary page too)" <<< "$OUT"'
# A6: gift cards + "license expired" = scam; a printer support number alone is not; a real error is not
check A6 '[ "$(key "Your Windows license has expired. Pay with gift cards to unlock")" = scam-fake-error ] && [ "$(key "Printer out of paper. Service: 661-555-1234")" = print-paper ] && [ "$(key "ERR_CONNECTION_TIMED_OUT")" = web-timeout ]'
# A7: not understood and no AI -> said honestly, exit 1, nothing written down
fresh; OUT="$(ER explain "zzzz qqqq")"; CODE=$?
check A7 '[ "$CODE" = 1 ] && grep -q "^I could not read an error there" <<< "$OUT" && [ ! -s "$HIST" ]'
# A8: wrong use = 3
ER explain >/dev/null 2>&1; C1=$?; ER fix open:slow >/dev/null 2>&1; C2=$?; ER nonsense >/dev/null 2>&1; C3=$?
check A8 '[ "$C1" = 3 ] && [ "$C2" = 3 ] && [ "$C3" = 3 ]'
# A9: a broken library file is reported, not a crash
mkdir -p "$WORK/s1/library" "$WORK/s2/library"; cp "$FORGEOS_ERRORS_SHARE"/library/*.txt "$WORK/s1/library/"
printf '\nid: x\nwhat: nope\n' >> "$WORK/s1/library/01-windows-programs.txt"
OUT="$(FORGEOS_ERRORS_SHARE="$WORK/s1" ER check 2>&1)"; CODE=$?
printf 'id: bad\nmatch: zzz\nlevel: purple\ntitle: t\nsay: s\ndo: call 800-555-1234\nfix: open:nope\nexample: nothing here\n' > "$WORK/s2/library/a.txt"
OUT2="$(FORGEOS_ERRORS_SHARE="$WORK/s2" ER check 2>&1)"; CODE2=$?
check A9 '[ "$CODE" = 1 ] && grep -q "bad line" <<< "$OUT" && [ "$CODE2" = 1 ] && grep -q "level must be" <<< "$OUT2" && grep -q "fix not on the checked list" <<< "$OUT2" && grep -q "phone number or a command" <<< "$OUT2" && grep -q "example finds nothing" <<< "$OUT2"'

echo
if [ "$failures" -eq 0 ]; then echo "All Plain-English Errors tests A passed."; else echo "$failures test(s) failed."; fi
exit "$((failures > 0))"
