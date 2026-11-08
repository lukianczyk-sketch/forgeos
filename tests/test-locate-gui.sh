#!/usr/bin/env bash
# Tests for Find My PC (Job 19), cases H-I: the window - set up (photo question, PC password, the QR code and
# the serial number), the test with the phone, photo on/off, turn off, and what the main menu shows.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-locate-gui.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/locate-fakes.sh
. "$ROOT/tests/locate-fakes.sh"
trap 'stop_relay; rm -rf "$WORK"' EXIT
fresh; start_relay
export FORGEOS_LOC_WAIT=2 FORGEOS_LOC_SLEEP=0
G() { bash "$GUI" "$@"; }
answers() { printf '%s\n' "$@" > "$WORK/kd-answers"; : > "$WORK/shown"; }

# H: the main menu before setup, then set up with photos, the QR code, the serial number and the test
answers rc1; G
check H1 'grep -q "Find My PC: <b>not set up yet</b>" "$WORK/shown" && grep -q " setup Set up Find My PC (2 minutes, needs your phone) how How it works close Close$" "$WORK/shown"'
# "Yes, take photos", the QR code (OK), "Test it", "tap Test" (the phone answers), "It works" (OK)
cat > "$WORK/kd-hook" <<HOOK
ROOT="$ROOT"; WORK="$WORK"; . "$ROOT/tests/locate-fakes.sh"; PY "phone('ping', \$(MS))" && ROOTLOC watch --once > /dev/null
HOOK
answers "" "" "" "" "" ""; G --setup; RC=$?
check H2 '[ "$RC" = 0 ] && grep -qx "pkexec $FORGEOS_LOC_HELPER setup --photo" <<< "$(calls)" && grep -qx "PHOTO${T}on" <<< "$(LOC status)"'
check H3 'grep -q "<h2>Scan this with your phone.s camera</h2><img src=\"/tmp/.*/qr.png\">" "$WORK/shown" && grep -q "^qrencode -t PNG -s 6 -m 2 -o /tmp/.*/qr.png$" <<< "$(calls)" && ! grep -q "#k=" "$WORK/calls.log" && grep -q "serial number (for the police if it is stolen): <b>PF3XK9QZ</b>" "$WORK/shown" && grep -q "subscribe to <b>$RELAY/fmp" "$WORK/shown"'
check H4 'grep -q "<h2>It works!</h2>Your PC heard your phone at Jan 15, " "$WORK/shown" && [ ! -e "$WORK/kd-hook" ]'
# the test when the phone does not answer; setup refused (no PC password); no qrencode = the link as text
answers "" ""; G --test
check H5 'grep -q "Your PC did not hear your phone yet." "$WORK/shown"'
# no qrencode: the link is shown from a file (never on a command line)
mv "$WORK/bin/qrencode" "$WORK/qrencode.off"; answers link "" "" rc1; G; mv "$WORK/qrencode.off" "$WORK/bin/qrencode"
check H5b 'grep -q "Type the link (shown next) into your phone.s browser." "$WORK/shown" && grep -q "^--title Find My PC --textbox /tmp/.*/link.txt 700 160$" "$WORK/shown"'
touch "$WORK/pkexec-no"; answers "" rc1; G --setup; rm -f "$WORK/pkexec-no"
check H6 'grep -q "Find My PC was not set up (the PC password was not given)." "$WORK/shown" && grep -qx "PHOTO${T}on" <<< "$(LOC status)"'

# I: the main menu once set up: link again, photo off, lost, turn off
answers link "" photo "" rc1; G
check I1 'grep -q "Find My PC: <b>on</b> (set up Jan 15, " "$WORK/shown" && grep -q " link Show my phone link again test Test it with my phone photo Webcam photo while lost: ON (turn off) again Set up again (a new link - the old one stops working) off Turn Find My PC off how How it works close Close$" "$WORK/shown" && grep -qx "pkexec $FORGEOS_LOC_HELPER link" <<< "$(calls)" && grep -q "msgbox Webcam photo while lost: off.$" "$WORK/shown" && grep -qx "PHOTO${T}off" <<< "$(LOC status)"'
PY "phone('lost', $(MS 1800000000 900))"; ROOTLOC watch --once > /dev/null; touch "$WORK/svc-down"
answers rc1; G
check I2 'grep -q "<b>This PC is marked LOST</b> (since Jan 15, .*). Reports sent: 1.<br>Tap \"Found it\" on your phone" "$WORK/shown" && grep -q "<b>The Find My PC service is not running - restart the PC.</b>" "$WORK/shown"'
rm -f "$WORK/svc-down"; answers off rc1 rc1; G
check I3 '[ -e "$WORK/var/key.json" ] && ! grep -qx "pkexec $FORGEOS_LOC_HELPER off" <<< "$(calls)"'
answers off "" "" rc1; G
check I4 'grep -qx "pkexec $FORGEOS_LOC_HELPER off" <<< "$(calls)" && grep -q "msgbox Find My PC is off. Your phone link no longer works.$" "$WORK/shown" && [ ! -e "$WORK/var/key.json" ] && grep -qx "techguard root-money unlock" <<< "$(calls)"'
check I5 'G --nonsense 2>&1 | grep -q "^usage: forgeos-locate-gui" && PATH="/usr/bin:/bin" bash "$GUI" 2>&1 | grep -q "kdialog is needed"'

echo
if [ "$failures" -eq 0 ]; then echo "All Find My PC tests H-I passed."; else echo "$failures Find My PC test(s) failed."; fi
exit "$((failures > 0))"
