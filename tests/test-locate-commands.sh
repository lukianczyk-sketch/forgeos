#!/usr/bin/env bash
# Tests for Find My PC (Job 19), cases E8-F: ring / message / lock / shut down, Found it wipes, the relay's
# "too many", no internet (the strongest open Wi-Fi), and a rough place from the internet address.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-locate-commands.sh <repo-root>
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
W() { ROOTLOC watch --once; }
posts() { grep -c "^POST" "$WORK/relay.log" 2>/dev/null; }
kinds() { PY "print(' '.join(o.get('k', '?') + ('/' + o['c'] if o.get('c') else '') for o in got()))"; }

# set up and marked lost (as in test-locate-watch.sh), 6 hours later
pkexec "$FORGEOS_LOC_HELPER" setup > /dev/null; PY "phone('lost', $(MS))"; W > /dev/null; setnow 1800021000
# E8-E10: ring, message, lock, and lock + shut down (the answer goes to the phone before the PC turns off)
PY "phone('ring', $(MS 1800021000 1)); phone('message', $(MS 1800021000 2), text='Reward! Call 555-0101')"; OUT="$(W)"
check E8 'grep -q "COMMAND${T}ring${T}Ringing for 2 minutes." <<< "$OUT" && grep -q "COMMAND${T}message${T}Message shown: Reward! Call 555-0101" <<< "$OUT" && [ "$(python3 -c "import json,sys; print(\" \".join(a[\"kind\"] for a in json.load(open(sys.argv[1]))[\"list\"]))" "$WORK/run/alert.json")" = "lost ring message" ] && [ "$(stat -c %a "$WORK/run/alert.json")" = 644 ]'
PY "phone('lock', $(MS 1800021000 3))"; W > /dev/null
check E9 'grep -qx "loginctl lock-sessions" <<< "$(calls)" && [ "$(kinds | awk "{print \$NF}")" = "ack/lock" ]'
PY "phone('shutdown', $(MS 1800021000 4)); phone('ring', $(MS 1800021000 5))"; OUT="$(W)"
check E10 '[ "$OUT" = "COMMAND${T}shutdown${T}Locked and shutting down. The disk lock now keeps every file safe." ] && grep -qx "systemctl poweroff" <<< "$(calls)" && [ "$(kinds | awk "{print \$NF}")" = "ack/shutdown" ]'

# F: Found it - lost mode off, money websites open, the reports wiped from the PC, the joined Wi-Fi forgotten
python3 - "$WORK/var/state.json" <<'PY2'
import json, sys
s = json.load(open(sys.argv[1])); s["joined"] = True; json.dump(s, open(sys.argv[1], "w"))
PY2
PY "phone('found', $(MS 1800021000 6))"; W > /dev/null
check F1 '[ "$(st "s.get(\"lost\", 0)")" = 0 ] && [ ! -e "$WORK/var/trail.json" ] && grep -qx "techguard root-money unlock" <<< "$(calls)" && grep -qx "nmcli connection delete ForgeOS-FindMyPC" <<< "$(calls)" && grep -q "\"kind\": \"found\"" "$WORK/run/alert.json" && grep -qx "LOST${T}no${T}-" <<< "$(LOC status)"'
# the relay says "too many": wait 30 minutes; no internet while lost: try the strongest open Wi-Fi
touch "$WORK/busy"; setnow 1800022000; W > /dev/null; B1="$(grep -c "^POLL" "$WORK/relay.log")"; setnow 1800022600; W > /dev/null
check F2 '[ "$(st "int(s[\"backoff_until\"])")" = 1800023800 ] && [ "$(grep -c "^POLL" "$WORK/relay.log")" = "$B1" ]'
rm -f "$WORK/busy"; setnow 1800024000; PY "phone('lost', $(MS 1800024000 1))"; W > /dev/null
setnow 1800024700; touch "$WORK/down" "$WORK/join-ok"; W > /dev/null
check F3 '[ "$(st "int(s.get(\"lost\", 0))")" = 1800024000 ] && [ ! -e "$WORK/down" ] && [ "$(st "int(s[\"next_report\"])")" = 1800025300 ] && grep -qx "nmcli device wifi connect Free Cafe Wi-Fi name ForgeOS-FindMyPC" <<< "$(calls)" && [ "$(st "s.get(\"joined\")")" = True ]'
# one Wi-Fi network only: the place comes from the internet address (rough)
sed -i 2,3d "$WORK/wifi.txt"; setnow 1800030000; W > /dev/null
check F4 '[ "$(PY "r = [o for o in got() if o[\"k\"] == \"where\"][-1]; print(r[\"src\"], r[\"lat\"], r[\"lon\"], r[\"acc\"])")" = "ip 35.1322 -118.449 10000" ]'

# F5: a phone clock 10 minutes ahead is told so (nothing done); F6: the window's "check now" = 15 fast minutes
setnow 1800040000; PY "phone('ring', $(MS 1800040600))"; W > /dev/null
check F5 '[ "$(PY "print([o for o in got() if o[\"k\"] == \"ack\"][-1][\"text\"])")" = "Not done: your phone${Q}s clock is ahead. Set it to automatic date and time." ] && ! grep -q "ring" <<< "$(st "s[\"last_cmd\"]")"'
touch -d @1800040100 "$WORK/user/1000/forgeos-locate-poke"; setnow 1800040200; W > /dev/null
check F6 '[ "$(st "int(s[\"fast_until\"])")" = 1800041100 ] && [ "$(st "int(s[\"poke\"])")" = 1800040100 ]'
# F7: money websites already locked before lost mode stay locked after Found it
PY "phone('found', $(MS 1800040200 1))"; W > /dev/null
echo "# >>> ForgeOS Fake Tech Support Guard: money websites locked while someone can see this screen >>>" > "$WORK/hosts"
: > "$WORK/calls.log"; PY "phone('lost', $(MS 1800040200 2)); phone('found', $(MS 1800040200 3))"; W > /dev/null
check F7 'grep -qx "techguard root-money lock" <<< "$(calls)" && ! grep -q "root-money unlock" <<< "$(calls)" && ! grep -q "\"lost\"\|\"message\"" "$WORK/run/alert.json"'
# F8: a broken half emoji in a message is dropped; the command runs once and the watcher keeps going
python3 -B -c "
import sys, json, urllib.request; sys.path.insert(0, sys.argv[1])
from locatelib.seal import seal, topic
key = json.load(open(sys.argv[2]))['key']; body = seal(key, 'cmd', {'c': 'message', 't': 1800040200004, 'text': 'Call me \ud83d'})
urllib.request.urlopen(urllib.request.Request(sys.argv[3] + '/' + topic(key, 'cmd'), body.encode())).read()" "$FORGEOS_LOC_LIB" "$WORK/var/key.json" "$RELAY"
OUT1="$(W 2>&1)"; RC=$?; OUT2="$(W 2>&1)"
check F8 '[ "$RC" = 0 ] && [ "$OUT1" = "COMMAND${T}message${T}Message shown: Call me" ] && [ -z "$OUT2" ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Find My PC tests E8-F passed."; else echo "$failures Find My PC test(s) failed."; fi
exit "$((failures > 0))"
