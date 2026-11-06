#!/usr/bin/env bash
# Tests for Ransomware Tripwire (Job 16), cases D-E4: normal work never sets it off (photo imports, editing,
# backups, hidden and game folders); slow attacks, ransom notes and a program writing to a bait file do.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-tripwire-more.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/tripwire-fakes.sh
. "$ROOT/tests/tripwire-fakes.sh"
none() { [ -z "$(inc)" ] && ! calls | grep -q "nmcli networking off"; }
photo() { { printf '\xff\xd8\xff\xe0'; head -c 20000 /dev/urandom; } > "$1"; }

# D: normal work: 60 photos imported in 6 s, 30 letters edited, a backup program, hidden and game folders
fresh; prog 500 dolphin "$APP/app-org.kde.dolphin-500.scope"
for i in $(seq 1 60); do photo "$H/Pictures/IMG_$i.jpg"; write "0.$i" 500 "$H/Pictures/IMG_$i.jpg"; done
replay >/dev/null
check D1 'none'
prog 501 kwrite "$APP/app-org.kde.kwrite-501.scope"
for i in $(seq 1 30); do letter "$H/Documents/note $i.txt" "$i"; write "0.$i" 501 "$H/Documents/note $i.txt"; done
replay >/dev/null
check D2 'none'
prog 502 borg "$APP/app-pika-502.scope" /usr/bin/borg
for i in $(seq 1 40); do noise "$H/Documents/chunk $i"; write "0.$i" 502 "$H/Documents/chunk $i"; done
replay >/dev/null
check D3 'none'
prog 503 cache-thing "$APP/app-thing-503.scope"; mkdir -p "$H/Documents/.cache" "$H/Documents/Games/save" "$H/.local/x"
for i in $(seq 1 30); do noise "$H/Documents/.cache/c$i"; write "0.$i" 503 "$H/Documents/.cache/c$i"; done
for i in $(seq 1 30); do noise "$H/Documents/Games/save/s$i"; write "0.$i" 503 "$H/Documents/Games/save/s$i"; done
for i in $(seq 1 30); do noise "$H/.local/x/l$i"; write "0.$i" 503 "$H/.local/x/l$i"; done
replay >/dev/null
check D4 'none'
for i in $(seq 1 19); do noise "$H/Documents/odd $i.dat"; write "0.$i" 503 "$H/Documents/odd $i.dat"; done
replay >/dev/null
check D5 'none'

# E1: a slow attack (one file every 3 seconds) is caught after 150 files in 10 minutes
fresh; prog 600 slow.exe "$APP/app-wine-600.scope"
for i in $(seq 1 160); do letter "$H/Documents/letter $i.txt" "$i"; done
attack 600 "$H/Documents" 160 3 > /dev/null; replay >/dev/null; ID="$(inc)"
check E1 '[ -n "$ID" ] && [ "$(py "$ID" "i[\"reason\"]")" = "It scrambled 150 files in the last 10 minutes." ] && [ "$(py "$ID" "len(i[\"files\"])")" = 150 ]'
# E2: a ransom note plus 5 scrambled files
fresh; prog 601 bad.exe "$APP/app-wine-601.scope"
for i in $(seq 1 6); do letter "$H/Desktop/letter $i.txt" "$i"; done
letter "$H/Desktop/HOW_TO_DECRYPT_FILES.txt" x; write 0 601 "$H/Desktop/HOW_TO_DECRYPT_FILES.txt"
attack 601 "$H/Desktop" 6 1; replay >/dev/null; ID="$(inc)"
check E2 '[ "$(py "$ID" "i[\"reason\"]")" = "It left a ransom note (HOW_TO_DECRYPT_FILES.txt) and scrambled 5 files." ]'
# E3: a program writes to a safety file: caught at once
fresh; : > "$WORK/feed"; replay >/dev/null; prog 602 sneaky "$APP/app-sneaky-602.scope"
noise "$H/Music/zzz Tax return 2026.docx"; write 0 602 "$H/Music/zzz Tax return 2026.docx"; replay >/dev/null; ID="$(inc)"
check E3 '[ "$(py "$ID" "i[\"reason\"]")" = "It changed one of ForgeOS'"'"'s safety files (a file nobody should ever touch)." ] && [ "$(cat "$WORK/cg$APP/app-sneaky-602.scope/cgroup.freeze")" = 1 ]'
check E4 'grep -q "Please leave it alone" "$H/Music/zzz Tax return 2026.docx"'
echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
