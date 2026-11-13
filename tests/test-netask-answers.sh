#!/usr/bin/env bash
# Tests for Ask Before Connecting (Job 24), case D: Today's counts from OpenSnitch's Pings,
# "Something stopped working?", turning it off, at most 5 confirm questions a minute, the service down.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-netask-answers.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'stop_service; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/netask-fakes.sh
. "$ROOT/tests/netask-fakes.sh" || exit 1
start_service || exit 1
MD5=0123456789abcdef0123456789abcdef
mkdir -p "$H/Apps" "$H/Downloads"
proc 201 -- "$H/Apps/Game Helper"; echo 0 > "$WORK/say/codes"; answer "$(conn 201 "$H/Apps/Game Helper" $MD5)" > /dev/null
# D1: Today's counts come from OpenSnitch's Pings (each event once, by the app's name); no web addresses kept
fresh; ping '{"events": [{"uid": '"$ME"', "path": "'"$H"'/Apps/Chat", "host": "chat.example", "nano": 5}, {"uid": '"$ME"', "path": "'"$H"'/Apps/Chat", "host": "chat.example", "nano": 6}, {"uid": '"$ME"', "path": "/usr/bin/curl", "host": "x.example", "nano": 7}]}' > /dev/null
ping '{"events": [{"uid": '"$ME"', "path": "'"$H"'/Apps/Chat", "host": "chat.example", "nano": 6}, {"uid": '"$ME"', "path": "'"$H"'/Apps/Bad", "host": "bad.example", "nano": 8, "action": "deny", "rule": "500-forgeos-netask-u1-bad-12345678"}]}' > /dev/null
OUT="$(NA today)"
check D1 'grep -qx "TODAY${T}Chat${T}2" <<< "$OUT" && grep -qx "TODAY${T}curl${T}1" <<< "$OUT" && ! grep -q "chat.example" "$WORK/var/log-$ME.json" && grep -q "bad.example" "$WORK/var/log-$ME.json" && grep -q "^2 apps went online today.$" <<< "$OUT"'
# D2: "Something stopped working?" = what was blocked in the last hour; report for Forge Helper
OUT="$(NA blocked 60)"; R="$(NA report)"
check D2 'grep -q "^BLOCKED${T}path:$H/Apps/Bad${T}[0-9]*${T}Bad${T}bad.example${T}you blocked it$" <<< "$OUT" && grep -qx "Ask Before Connecting is on." <<< "$R" && grep -q "^Online today: Chat (2), curl (1).$" <<< "$R" && grep -q "^Your apps: [0-9]* allowed, [0-9]* blocked, [0-9]* ask each time.$" <<< "$R"'
# D3: turning it off asks first (it is safer on) and then stops OpenSnitch; on needs no question
fresh; echo 1 > "$WORK/say/codes"; OUT="$(NA off)"; C1=$?
echo 0 > "$WORK/say/codes"; OUT2="$(NA off)"; OUT3="$(NA on)"
check D3 '[ "$C1" = 1 ] && grep -q "still on" <<< "$OUT" && [ "$OUT2" = "Ask Before Connecting is off." ] && [ "$OUT3" = "Ask Before Connecting is on." ] && calls | grep -qx "systemctl disable --now opensnitch.service" && calls | grep -qx "systemctl enable --now opensnitch.service" && [ "$(calls | grep -c -- "--yesno Turn off Ask Before Connecting?")" = 2 ]'
# D4: at most 5 confirm questions a minute (a program can't flood the screen with them)
stop_service; FORGEOS_NETASK_CONFIRMS=5 start_service; fresh; for _ in 1 2 3 4 5 6; do echo 1 >> "$WORK/say/codes"; done
for _ in 1 2 3 4 5 6; do NA allow "Game Helper" > /dev/null; done
check D4 '[ "$(calls | grep -c -- "--yesno Allow")" -le 5 ]'
# D5: more than 3 questions in a minute: the rest are blocked for now and wait for the one quiet list
stop_service; FORGEOS_NETASK_MOST_ASKS=3 start_service; fresh
for n in 1 2 3 4; do proc "21$n" -- "$H/Apps/Flood$n"; echo 1 >> "$WORK/say/codes"; done
for n in 1 2 3 4; do answer "$(conn "21$n" "$H/Apps/Flood$n" $MD5)" > "$WORK/a$n"; done
check D5 '[ "$(calls | grep -c -- "--yesnocancel Flood")" = 3 ] && [ "$(cat "$WORK/a4")" = "deny once forgeos-netask-once" ] && [ "$(store "path:$H/Apps/Flood4" later)" = True ]'
stop_service; start_service
# D6: the service is not running -> exit 2 with plain words; wrong use = 3; unknown app = 1
stop_service; OUT="$(NA status)"; C1=$?
NA nonsense >/dev/null 2>&1; C2=$?; NA lockdown maybe >/dev/null 2>&1; C3=$?
start_service; NA allow "Nobody Here" > /dev/null; C4=$?
check D6 '[ "$C1" = 2 ] && grep -q "is not running right now (the PC still blocks programs it does not know)" <<< "$OUT" && [ "$C2" = 3 ] && [ "$C3" = 3 ] && [ "$C4" = 1 ]'
# D7: a broken request never crashes the service
OUT="$(python3 - "$FORGEOS_NETASK_REQ" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.sendall(b"not json\n"); print(s.recv(999).decode().strip())
PY
)"
check D7 'grep -q "\"ok\": false" <<< "$OUT" && NA status > /dev/null'

echo
if [ "$failures" -eq 0 ]; then echo "All Ask Before Connecting tests D passed."; else echo "$failures test(s) failed."; cat "$WORK/service.log"; fi
exit "$((failures > 0))"
