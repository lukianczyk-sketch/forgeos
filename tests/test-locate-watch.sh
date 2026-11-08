#!/usr/bin/env bash
# Tests for Find My PC (Job 19), cases D-E: the root watcher. Normal days it sends nothing; only commands that
# open with the key, are new and less than 13 hours old count; lost mode reports (Wi-Fi place, bell, photo).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-locate-watch.sh <repo-root>
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

# D: normal days - not set up = no relay at all; set up = it only looks (nothing sent); bad commands do nothing
W > /dev/null
check D1 '[ ! -e "$WORK/relay.log" ] && grep -q "\"setup\": false" "$WORK/var/status.json"'
pkexec "$FORGEOS_LOC_HELPER" setup > /dev/null; W > /dev/null; W > /dev/null
check D2 '[ "$(grep -c "^POLL" "$WORK/relay.log")" = 2 ] && [ "$(posts)" = 0 ] && ! grep -q "^nmcli\|^who\|^ffmpeg" <<< "$(calls)"'
setnow 1800000060; PY "phone('ping', $(MS 1800000050))"; OUT="$(W)"
check D3 '[ "$OUT" = "COMMAND${T}ping${T}Your PC heard you." ] && [ "$(kinds)" = "ack/ping" ] && grep -q "^HEARD${T}Jan 15, .*${T}ping$" <<< "$(LOC status)" && ! grep -q "^nmcli" <<< "$(calls)"'
# the same command again, an older one, one from 14 hours ago, a stranger's key, a report played back as a command
PY "phone('ping', $(MS 1800000050)); phone('ring', $(MS 1800000040)); phone('ring', $(MS 1799949600))"
python3 -B -c "
import sys, urllib.request, json; sys.path.insert(0, sys.argv[1])
from locatelib.seal import seal, new_key, topic
key = json.load(open(sys.argv[2]))['key']; post = lambda t: urllib.request.urlopen(urllib.request.Request(sys.argv[3] + '/' + topic(key, 'cmd'), t.encode())).read()
post(seal(new_key(), 'cmd', {'c': 'lost', 't': 1800000055000})); post(seal(key, 'rep', {'c': 'lost', 't': 1800000056000})); post('lost please')" "$FORGEOS_LOC_LIB" "$WORK/var/key.json" "$RELAY"
OUT="$(W)"
check D4 '[ -z "$OUT" ] && [ "$(kinds)" = "ack/ping" ] && ! grep -q "kind" "$WORK/run/alert.json" && [ "$(st "s.get(\"lost\", 0)")" = 0 ] && [ "$(st "s[\"since\"]")" = "m0008" ]'

# E: lost - money websites locked, a report (Wi-Fi place), the bell, a photo only when it is on; then every 10 min
PY "phone('lost', $(MS 1800000060 1))"; OUT="$(W)"
check E1 '[ "$OUT" = "COMMAND${T}lost${T}Lost mode is ON. Money websites are locked." ] && [ "$(kinds)" = "ack/ping ack/lost where" ] && grep -qx "techguard root-money lock" <<< "$(calls)" && grep -q "\"kind\": \"lost\"" "$WORK/run/alert.json"'
REP="$(PY "r = [o for o in got() if o['k'] == 'where'][0]; print(r['lat'], r['lon'], r['acc'], r['src'], r['city'], r['wifi'], r['seen'], r['bat'], r['chg'], r['users'], r['ip'])")"
check E2 '[ "$REP" = "35.132201 -118.448997 42 wifi Tehachapi, California, US Home Net 3 57 False [${Q}robert${Q}] 203.0.113.9" ]' 
check E3 'grep -q "\"macAddress\": \"aa:bb:cc:00:11:22\", \"signalStrength\": -60" "$WORK/geo.log" && grep -q "\"considerIp\": false" "$WORK/geo.log" && [ "$(PY "print(got(\"bell\", None))")" = "[${Q}Your PC checked in. Open Find My PC on your phone to see where.${Q}]" ] && ! grep -q "^ffmpeg" <<< "$(calls)"'
setnow 1800000300; W > /dev/null; N1="$(kinds | wc -w)"; setnow 1800000661; W > /dev/null; N2="$(kinds | wc -w)"
check E4 '[ "$N1" = 3 ] && [ "$N2" = 4 ] && [ "$(PY "print(len(got(\"bell\", None)))")" = 1 ] && [ "$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))))" "$WORK/var/trail.json")" = 2 ] && [ "$(stat -c %a "$WORK/var/trail.json")" = 600 ]'
setnow 1800007300; W > /dev/null; setnow 1800008000; W > /dev/null; N3="$(kinds | wc -w)"; setnow 1800008501; W > /dev/null; N4="$(kinds | wc -w)"
check E5 '[ "$N3" = 5 ] && [ "$N4" = 6 ] && [ "$(PY "print(len(got(\"bell\", None)))")" = 2 ]'
# photo on: pieces that the phone puts back together into the same JPEG; a photo too big is not sent
pkexec "$FORGEOS_LOC_HELPER" photo on > /dev/null; setnow 1800010000; W > /dev/null
PH="$(PY "
import base64; p = sorted((o for o in got() if o['k'] == 'photo'), key=lambda o: o['i'])
d = base64.b64decode(''.join(o['d'] for o in p)); print(len(p), p[0]['n'], len(d), d[:2] == b'\xff\xd8')")"
check E6 '[ "$PH" = "3 3 5004 True" ] && grep -q "^ffmpeg .* -i /dev/video0 " <<< "$(calls)" && [ ! -e "$WORK/run/photo.jpg" ]'
setnow 1800021000; PHOTO_BYTES=20000 W > /dev/null
check E7 '[ "$(PY "print(len([o for o in got() if o[\"k\"] == \"photo\"]))")" = 3 ] && [ "$(st "int(s[\"next_photo\"])")" = 1800031800 ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Find My PC tests D-E passed."; else echo "$failures Find My PC test(s) failed."; fi
exit "$((failures > 0))"
