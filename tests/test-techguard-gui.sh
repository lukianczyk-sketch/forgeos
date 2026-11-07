#!/usr/bin/env bash
# Tests for Fake Tech Support Guard (Job 17), cases K-L: the window - the big STOP window (kick them out with
# the checklist and last steps, I set this up myself, the helper, Family Mode), the download warning, the main
# menu, and "Test the guard" with a real pretend remote app (the sleep program named AnyDesk).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-techguard-gui.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/techguard-fakes.sh
. "$ROOT/tests/techguard-fakes.sh"
export FORGEOS_TG_SCREENS="$ROOT/files/system/usr/libexec/forgeos-techguard-screens"
fake forgeos-cleansweep-gui 'exit 0'
AD="$APP/app-flatpak-com.anydesk.Anydesk-5.scope"
W() { printf '%s\n' "$@" > "$WORK/kd-answers"; }  # the answers, in order ("" = OK / Yes, rc1 = Cancel / No)
G() { : > "$WORK/shown"; bash "$GUI" "$@"; }
shown() { cat "$WORK/shown"; }

# K1: STOP window -> Kick them out -> done, nothing left behind, last steps, no Clean Sweep, internet back on
fresh
prog 20 AnyDesk "$AD"; tick >/dev/null; ID="$(alarm_id)"
W kick "" "" "" rc1 "" ""
G --alarm "$ID"
check K1 'killed "$AD" && [ "$(cat "$WORK/net-state")" = on ] && grep -q "STOP - is someone on the phone with you?" <<< "$(shown)" && grep -q "<b>AnyDesk</b> lets a person far away see and control" <<< "$(shown)" && grep -q "I set this up myself" <<< "$(shown)" && ! grep -q "asked me to" <<< "$(shown)"'
check K2 'grep -q "Done - everyone is out.</h2>Closed: AnyDesk" <<< "$(shown)" && grep -q "Nothing new was left behind" <<< "$(shown)" && grep -q "call your bank NOW" <<< "$(shown)" && ! grep -q "forgeos-cleansweep-gui" <<< "$(calls)" && grep -q "The internet is back on." <<< "$(shown)"'
# K3: I set this up myself -> asked first, PC password, runs again
fresh
prog 20 AnyDesk "$AD"; tick >/dev/null; ID="$(alarm_id)"
W mine "" ""
G --alarm "$ID"
check K3 '! frozen "$AD" && [ "$(astate "$ID")" = allowed ] && grep -q "Never type the PC password for a caller" <<< "$(shown)" && grep -q "trusted from now on" <<< "$(shown)"'
# K4: with Call for help running the helper is offered; Family Mode: no "it's mine"; later = stays paused
fresh
mkdir -p "$WORK/config/forgeos"; echo "name=Brianna" > "$WORK/config/forgeos/family.conf"; touch "$WORK/call-on"
prog 20 AnyDesk "$AD"; tick >/dev/null; ID="$(alarm_id)"
mkdir -p "$WORK/state/forgeos/family"; echo '{"on": true}' > "$WORK/state/forgeos/family/saved.json"
W later ""
G --alarm "$ID"
check K4 'grep -q "helper Brianna asked me to - we are on the phone now" <<< "$(shown)" && ! grep -q "I set this up myself" <<< "$(shown)" && frozen "$AD" && grep -q "It stays paused" <<< "$(shown)"'
prog 21 UltraViewer "$APP/app-uv-1.scope"; tick >/dev/null; ID="$(alarm_id 1)"
W ""
G --alarm "$ID"
check K5 'grep -q "Family Mode closed UltraViewer" <<< "$(shown)" && grep -q "hang up - it is a scam" <<< "$(shown)"'
# K6: a remote app was downloaded -> Lock it away
fresh
touch "$H/Downloads/AnyDesk.exe"
W "" ""
G --download "$H/Downloads/AnyDesk.exe"
check K6 '[ ! -e "$H/Downloads/AnyDesk.exe" ] && grep -q "You just downloaded <b>AnyDesk.exe</b>, a remote-control app" <<< "$(shown)" && grep -q "Locked away" <<< "$(shown)"'

# L1: main menu - a paused app, someone sees the screen (money locked), internet cut
fresh
prog 20 AnyDesk "$AD"; tick >/dev/null
share us.zoom.Zoom "Zoom Meeting" 0; tick >/dev/null
TG kick >/dev/null; prog 22 AnyDesk "$APP/app-flatpak-com.anydesk.Anydesk-9.scope"; tick >/dev/null
W rc1
G
check L1 'grep -q "Someone can see this screen now: us.zoom.Zoom" <<< "$(shown)" && grep -q "Still paused: AnyDesk" <<< "$(shown)" && grep -q "share I.m sharing my screen on purpose" <<< "$(shown)" && grep -q "net Turn the internet back on" <<< "$(shown)" && grep -q "The internet is OFF since you kicked them out" <<< "$(shown)"'
# L2: Test the guard - a REAL pretend remote app (sleep named AnyDesk) is caught, paused and ended
fresh
OUT="$(FORGEOS_TG_PROC=/proc TG test)"; RC=$?
check L2 '[ "$RC" -eq 0 ] && grep -q "^PASS${T}Caught the pretend remote app .* seconds after it started and paused it.$" <<< "$OUT" && [ ! -e "$WORK/run/forgeos-techguard-test" ] && ! pgrep -f "forgeos-techguard-test/AnyDesk" >/dev/null'
W test "" rc1
FORGEOS_TG_PROC=/proc G
check L3 'grep -q "Caught the pretend remote app" <<< "$(shown)" && grep -q "Test the guard" <<< "$(shown)"'
# L4: the guard is off -> Turn the guard on; wrong use
fresh; touch "$WORK/service-off"
W on "" rc1
G
rm -f "$WORK/service-off"
bash "$GUI" --alarm >/dev/null 2>&1; A=$?; bash "$GUI" --what >/dev/null 2>&1; B=$?
check L4 'grep -qx "systemctl --user enable --now forgeos-techguard.service" <<< "$(calls)" && grep -q "OFF</b> - press" <<< "$(shown)" && [ "$A" -eq 3 ] && [ "$B" -eq 3 ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Fake Tech Support Guard tests K-L passed."; else echo "$failures Fake Tech Support Guard test(s) failed."; fi
exit "$((failures > 0))"
