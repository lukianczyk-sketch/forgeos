#!/usr/bin/env bash
# Tests for Family Mode (Job 13), cases L-N: Call for help from the engine - no helper, no internet,
# RustDesk locked + opened + its ID, the 2-hour end, the text through the phone, ending the help.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-family-call.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/family-fakes.sh
. "$ROOT/tests/family-fakes.sh"
LOG="$WORK/state/forgeos/family/calls.log"
wait_run() { for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/running" ] && return 0; sleep 0.2; done; return 1; }

# L: no helper; no internet; then a real call (no phone number yet)
F call > "$WORK/out" 2>&1; R1=$?
F helper set --name Brianna --rustdesk-id 987654321 --me Robert >/dev/null
FAKE_NET=none F call > "$WORK/out2" 2>&1; R2=$?
check L1 '[ "$R1$R2" = 24 ] && grep -q "No helper is set up yet" "$WORK/out" && grep -q "not on the internet" "$WORK/out2" && ! grep -q "flatpak run" "$WORK/calls.log" 2>/dev/null'
OUT="$(F call)"; RC=$?
check L2 '[ "$RC" -eq 0 ] && [ "$OUT" = "$(printf "HELPER\tBrianna\nID\t123 456 789\nTEXT\tno-phone")" ] && wait_run'
check L3 'grep -q "^systemd-run --user --on-active=2h --unit=forgeos-family-call-end --collect --description=ForgeOS: end Call for help after 2 hours /usr/bin/forgeos-family call-end$" "$WORK/calls.log" && grep -q "^systemctl --user stop forgeos-family-call-end.timer$" "$WORK/calls.log" && grep -q "call: helper Brianna, ID 123 456 789$" "$LOG"'
check L4 'grep -qx "approve-mode = '"'"'click'"'"'" "$WORK/rd/RustDesk2.toml" && grep -qx "id-whitelist = '"'"'987654321'"'"'" "$WORK/rd/RustDesk2.toml" && grep -q "^STATUS${T}off$" <<< "$(F status)"'
# Family Mode off after a call alone: RustDesk's settings go back too (there were none)
F call-end >/dev/null; F off >/dev/null
check L5 '[ ! -e "$WORK/rd/RustDesk2.toml" ] && [ ! -e "$WORK/state/forgeos/family/saved.json" ]'

# M: the ID shows up late (RustDesk still starting); never shows up -> said so, no 2-hour timer
F helper set --name Brianna --phone 661-555-0123 --me Robert >/dev/null
printf '%s\n' "" "Error: not ready" "555666777" > "$WORK/ids"; : > "$WORK/running"
OUT="$(F call)"; RC=$?
check M1 '[ "$RC" -eq 0 ] && grep -qx "ID${T}555 666 777" <<< "$OUT" && grep -qx "PHONE${T}6615550123" <<< "$OUT" && grep -qx "TEXT${T}no-device" <<< "$OUT"'
echo "not ready" > "$WORK/ids"; : > "$WORK/calls.log"
OUT="$(F call)"; RC=$?
check M2 '[ "$RC" -eq 1 ] && grep -q "its ID did not show up" <<< "$OUT" && ! grep -q "^systemd-run" "$WORK/calls.log" && grep -q "call: no ID" "$LOG"'

# N: the text through the paired phone; it fails; no phone here; ending the help (and when it won't close)
echo 123456789 > "$WORK/ids"; echo phone1 > "$WORK/devices"
OUT="$(F call)"
check N1 'grep -qx "TEXT${T}ready" <<< "$OUT"'
OUT="$(F text "123 456 789")"; RC=$?
check N2 '[ "$RC" -eq 0 ] && [ "$OUT" = "Text sent to Brianna." ] && grep -q "^kdeconnect-cli -d phone1 --send-sms Robert needs help with the computer. Open RustDesk and connect to ID 123 456 789. (Sent by ForgeOS Call for help.) --destination 6615550123$" "$WORK/calls.log"'
OUT="$(FAKE_SMS_RC=1 F text 123456789)"; R1=$?
: > "$WORK/devices"; F text 123456789 >/dev/null; R2=$?
check N3 '[ "$R1$R2" = 11 ] && grep -q "Call Brianna and read the number out loud" <<< "$OUT" && grep -q "text to Brianna: failed" "$LOG"'
wait_run; : > "$WORK/calls.log"
OUT="$(F call-end)"; RC=$?
check N4 '[ "$RC" -eq 0 ] && [ "$OUT" = "RustDesk is closed." ] && [ ! -s "$WORK/running" ] && grep -q "^notify-send --app-name=Family Mode --icon=help-contents Call for help The help is over." "$WORK/calls.log" && grep -q "^systemctl --user stop forgeos-family-call-end.timer$" "$WORK/calls.log"'
echo com.rustdesk.RustDesk > "$WORK/running"
OUT="$(FAKE_NO_KILL=1 F call-end)"; RC=$?
check N5 '[ "$RC" -eq 1 ] && [ "$OUT" = "RustDesk would not close." ] && grep -q "Restart the PC to be sure" "$WORK/calls.log"'

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1
