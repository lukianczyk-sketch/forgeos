#!/usr/bin/env bash
# Tests for Ransomware Tripwire (Job 16), cases A-C: safety (bait) files, the scrambled-file judge,
# a fast attack (frozen, internet cut, snapshot, saved story) and normal work that must NOT set it off.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-tripwire.sh <repo-root>
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
judge() { python3 -B -c "import sys; sys.path.insert(0, sys.argv[1]); from tripwirelib import scramble as s; print(s.judge(sys.argv[2], s.read_head(sys.argv[3])) or 'normal')" "$FORGEOS_TW_LIB" "$1" "$2"; }

# A: the watcher puts 2 hidden safety files in each of the 6 folders; status and report say so
fresh; : > "$WORK/feed"; OUT="$(replay)"
check A1 '[ "$(ls "$H"/*/"000 Bank statements.pdf" "$H"/*/"zzz Tax return 2026.docx" | wc -l)" = 12 ] && grep -qx "000 Bank statements.pdf" "$H/Pictures/.hidden" && grep -qx "zzz Tax return 2026.docx" "$H/Music/.hidden" && [ "$(stat -c %a "$H/Desktop/000 Bank statements.pdf")" = 644 ]'
check A2 'head -c 5 "$H/Documents/000 Bank statements.pdf" | grep -q "^%PDF-" && [ "$(head -c 4 "$H/Videos/zzz Tax return 2026.docx" | od -An -c | tr -d " ")" = "PK003004" ] && [ "$(stat -c %Y "$H/Downloads/000 Bank statements.pdf")" = 1705334400 ]'
OUT="$(TW status)"; RC=$?
check A3 '[ "$RC" -eq 0 ] && grep -qx "SERVICE${T}on" <<< "$OUT" && grep -qx "BAIT${T}ok 12" <<< "$OUT" && grep -qx "SNAPSHOT${T}none" <<< "$OUT" && grep -qx "INTERNET${T}normal" <<< "$OUT" && ! grep -q "^INCIDENT" <<< "$OUT"'
OUT="$(TW report)"
check A4 'grep -q "^Ransomware Tripwire is ON" <<< "$OUT" && grep -qx "Its hidden safety files are all in place (12)." <<< "$OUT" && grep -q "Test the tripwire" <<< "$OUT"'
echo "keep me" > "$H/Music/.hidden"; rm "$H/Music/000 Bank statements.pdf"; : > "$WORK/feed"; replay >/dev/null
check A5 '[ -f "$H/Music/000 Bank statements.pdf" ] && [ "$(cat "$H/Music/.hidden" | paste -sd ,)" = "keep me,000 Bank statements.pdf,zzz Tax return 2026.docx" ]'
TW bogus >/dev/null 2>&1; R1=$?; FORGEOS_TW_ROOT=0 TW watch >/dev/null 2>&1; R2=$?; TW restore ../x >/dev/null 2>&1; R3=$?
check A6 '[ "$R1$R2$R3" = 333 ]'

# B: the judge: scrambled noise, real photos and zips, a fake ".jpg", plain text, tiny files, ransom notes
noise "$WORK/a.locked"; noise "$WORK/b.jpg"; { printf '\xff\xd8\xff\xe0'; head -c 8000 /dev/urandom; } > "$WORK/c.jpg"
{ printf 'PK\003\004'; head -c 8000 /dev/urandom; } > "$WORK/d.zip"; letter "$WORK/e.txt" 1; noise "$WORK/f.bin" 600
check B1 '[ "$(judge a.locked "$WORK/a.locked")" = scrambled ] && [ "$(judge b.jpg "$WORK/b.jpg")" = scrambled ] && [ "$(judge c.jpg "$WORK/c.jpg")" = normal ] && [ "$(judge d.zip "$WORK/d.zip")" = normal ]'
check B2 '[ "$(judge e.txt "$WORK/e.txt")" = normal ] && [ "$(judge f.bin "$WORK/f.bin")" = normal ] && [ "$(judge "x.zip.crdownload" "$WORK/d.zip")" = normal ] && [ "$(judge "HOW_TO_DECRYPT.txt" "$WORK/e.txt")" = note ] && [ "$(judge "README-RESTORE-FILES.html" "$WORK/e.txt")" = note ] && [ "$(judge "Recipes.txt" "$WORK/e.txt")" = normal ]'

# C: a fast attack: 25 letters scrambled 0.1 s apart by a Windows program in its own app scope
fresh; for i in $(seq 1 25); do letter "$H/Documents/letter $i.txt" "$i"; done
prog 4242 invoice.exe "$APP/app-wine-4242.scope" "$H/Downloads/invoice.exe"
attack 4242 "$H/Documents" 25; OUT="$(replay)"; ID="$(inc)"
check C1 '[ "$(tail -n 1 <<< "$OUT")" = "INCIDENT${T}$ID" ] && [ "$(py "$ID" "i[\"kind\"], i[\"state\"], i[\"frozen\"], i[\"program\"], len(i[\"files\"])")" = "attack frozen app invoice.exe 20" ] && grep -q "^TRIPWIRE attack: invoice.exe" <<< "$OUT"'
check C2 '[ "$(cat "$WORK/cg$APP/app-wine-4242.scope/cgroup.freeze")" = 1 ] && [ "$(py "$ID" "i[\"reason\"]")" = "It scrambled 20 files in 10 seconds." ] && [ "$(py "$ID" "i[\"exe\"]")" = "$H/Downloads/invoice.exe" ]'
check C3 'calls | grep -qx "nmcli networking off" && [ "$(cat "$WORK/run/net-cut")" = enabled ] && calls | grep -q "^snapper -c root create -c number -p -d Ransomware Tripwire" && [ "$(py "$ID" "i[\"snapshot\"], i[\"internet\"]")" = "77 cut" ]'
check C4 '[ "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))[\"id\"])" "$WORK/run/alert-$ME")" = "$ID" ] && [ "$(stat -c %a "$WORK/var/incidents/$ID.json")" = 640 ] && [ "$(py "$ID" "i[\"uid\"]")" = "$ME" ]'
OUT="$(TW status)"; RC=$?
check C5 '[ "$RC" -eq 1 ] && grep -qx "INTERNET${T}cut" <<< "$OUT" && grep -q "^INCIDENT${T}$ID${T}attack${T}frozen${T}.*${T}invoice.exe${T}20${T}no${T}It scrambled 20 files in 10 seconds.$" <<< "$OUT"'
check C6 'grep -q "stopped invoice.exe - It scrambled 20 files in 10 seconds. (still frozen, waiting for you)" <<< "$(TW report)" && grep -q "The internet is still OFF" <<< "$(TW report)"'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
