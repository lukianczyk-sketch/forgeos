#!/usr/bin/env bash
# Tests for Find My PC (Job 19), cases A-C: the lock between the PC and the phone (AES-256-GCM, topics, the
# phone link), setting up through the root helper (always the PC password), and the status / report lines.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-locate.sh <repo-root>
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

# A: the lock - opens only with the right key, the right direction and nothing changed
A="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from locatelib.seal import new_key, good_key, seal, unseal, topic, phone_link
k, other = new_key(), new_key()
s = seal(k, 'cmd', {'c': 'ring', 't': 5})
bad = s[:-3] + ('A' if s[-3] != 'A' else 'B') + s[-2:]
print(good_key(k), good_key('short'), unseal(k, 'cmd', s) == {'c': 'ring', 't': 5}, unseal(other, 'cmd', s), unseal(k, 'rep', s), unseal(k, 'cmd', bad), unseal(k, 'cmd', 'hello'))
t = [topic(k, n) for n in ('cmd', 'rep', 'bell')]
print(len(set(t)), all(len(x) == 24 and x.startswith('fmp') for x in t), topic(k, 'cmd') == topic(k, 'cmd'), topic(other, 'cmd') != t[0], s.startswith('FMP1.'), seal(k, 'cmd', {'a': 1}) != seal(k, 'cmd', {'a': 1}))
print(phone_link('https://x.github.io/forgeos/find/', k) == 'https://x.github.io/forgeos/find/#k=' + k, phone_link('https://p/', k, 'https://my.relay/').endswith('#k=' + k + '&r=https://my.relay'))" "$FORGEOS_LOC_LIB")"
check A1 '[ "$(sed -n 1p <<< "$A")" = "True False True None None None None" ]'
check A2 '[ "$(sed -n 2p <<< "$A")" = "3 True True True True True" ] && [ "$(sed -n 3p <<< "$A")" = "True True" ]'

# B: setting up - only through the root helper (pkexec always asks for the PC password)
OUT="$(LOC status)"; RC=$?
check B1 '[ "$RC" = 1 ] && grep -qx "SETUP${T}no" <<< "$OUT" && grep -qx "SERVICE${T}running" <<< "$OUT" && grep -qx "LOST${T}no${T}-" <<< "$OUT"'
B2="$(LOC root setup 2>&1)"; RB=$?; B3="$(bash "$FORGEOS_LOC_HELPER" setup --now 2>&1)"; RH=$?
check B2 '[ "$RB" = 3 ] && grep -q "needs the PC password" <<< "$B2" && [ "$RH" = 3 ] && grep -q "^usage: forgeos-locate-root" <<< "$B3" && [ ! -e "$WORK/var/key.json" ]'
OUT="$(pkexec "$FORGEOS_LOC_HELPER" setup)"; RC=$?
KEY="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['key'])" "$WORK/var/key.json")"
check B3 '[ "$RC" = 0 ] && grep -qx "LINK${T}https://lukianczyk-sketch.github.io/forgeos/find/#k=$KEY&r=$RELAY" <<< "$OUT" && grep -qx "SERIAL${T}PF3XK9QZ" <<< "$OUT" && grep -q "^BELL${T}$RELAY/fmp" <<< "$OUT"'
check B4 '[ "$(stat -c %a "$WORK/var/key.json")" = 600 ] && [ "$(stat -c %a "$WORK/var/state.json")" = 600 ] && [ "$(stat -c %a "$WORK/var/status.json")" = 644 ] && ! grep -q "$KEY" "$WORK/var/status.json" && grep -qx "systemctl stop forgeos-locate.service" <<< "$(calls)" && grep -qx "systemctl start forgeos-locate.service" <<< "$(calls)"'
check B5 '[ "$(st "s[\"since\"]")" = 1800000000 ] && [ "$(st "int(s[\"fast_until\"])")" = 1800000900 ] && grep -qx "PHOTO${T}off" <<< "$(LOC status)" && grep -qx "SETUP${T}yes" <<< "$(LOC status)"'
L1="$(pkexec "$FORGEOS_LOC_HELPER" link | sed -n 1p)"; pkexec "$FORGEOS_LOC_HELPER" photo on > "$WORK/p1"
check B6 '[ "$L1" = "LINK${T}https://lukianczyk-sketch.github.io/forgeos/find/#k=$KEY&r=$RELAY" ] && grep -qx "Webcam photo while lost: on." "$WORK/p1" && grep -qx "PHOTO${T}on" <<< "$(LOC status)"'
pkexec "$FORGEOS_LOC_HELPER" setup --photo > /dev/null
KEY2="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['key'])" "$WORK/var/key.json")"
check B7 '[ "$KEY2" != "$KEY" ] && grep -qx "PHOTO${T}on" <<< "$(LOC status)"'
touch "$WORK/pkexec-no"; pkexec "$FORGEOS_LOC_HELPER" off > /dev/null; RC=$?; rm -f "$WORK/pkexec-no"
check B8 '[ "$RC" = 126 ] && [ -e "$WORK/var/key.json" ]'
OUT="$(pkexec "$FORGEOS_LOC_HELPER" off)"; L2="$(pkexec "$FORGEOS_LOC_HELPER" link)"; RC=$?
check B9 '[ "$OUT" = "Find My PC is off. Your phone link no longer works." ] && [ ! -e "$WORK/var/key.json" ] && [ ! -e "$WORK/var/state.json" ] && grep -qx "SETUP${T}no" <<< "$(LOC status)" && [ "$RC" = 1 ] && [ "$L2" = "Find My PC is not set up yet." ]'
check B10 'LOC nonsense 2>&1 >/dev/null | grep -q "^usage: forgeos-locate" && LOC watch 2>&1 | grep -q "Only the Find My PC service" && [ "$(LOC serial)" = PF3XK9QZ ]'

# C: the report (Forge Helper) - not set up, normal, lost, and a stopped service
REP="$(LOC report)"; RC=$?
check C1 '[ "$RC" = 1 ] && grep -q "Find My PC is not set up yet" <<< "$REP"'
pkexec "$FORGEOS_LOC_HELPER" setup > /dev/null
REP="$(LOC report)"; RC=$?
check C2 '[ "$RC" = 0 ] && grep -q "^Find My PC is set up (since Jan 15, " <<< "$REP" && grep -q "only looks for a message from your phone and sends nothing" <<< "$REP" && grep -q "Webcam photo while lost: off." <<< "$REP" && grep -q "tap \"Mark as lost\"" <<< "$REP"'
python3 - "$WORK/var/state.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); s["lost"] = 1800000000; json.dump(s, open(sys.argv[1], "w"))
PY
ROOTLOC watch --once > /dev/null; touch "$WORK/svc-down"
REP="$(LOC report)"; OUT="$(LOC status)"
check C3 'grep -q "This PC is marked LOST since Jan 15, " <<< "$REP" && grep -q "WARNING: the Find My PC service is not running" <<< "$REP" && grep -q "^LOST${T}yes${T}Jan 15, " <<< "$OUT" && grep -qx "SERVICE${T}stopped" <<< "$OUT" && ! grep -q "tap \"Mark as lost\"" <<< "$REP"'

echo
if [ "$failures" -eq 0 ]; then echo "All Find My PC tests A-C passed."; else echo "$failures Find My PC test(s) failed."; fi
exit "$((failures > 0))"
