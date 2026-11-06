#!/usr/bin/env bash
# Tests for Ransomware Tripwire (Job 16), case M: the REAL watcher with the kernel's fanotify + inotify and
# real programs. Needs root (GitHub's runner has password-free sudo); skipped otherwise. The internet and
# snapper are still fakes. M0 safety files, M1 "Test the tripwire" end to end, M2-M3 a real scrambling program
# is stopped (SIGSTOP), M4 a real program writing to a safety file, M5 a safety file deleted by hand: a quiet note.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-tripwire-kernel.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
if [ "$(id -u)" = 0 ]; then SUDO=(env); elif sudo -n true 2>/dev/null; then SUDO=(sudo -n env); else
  echo "SKIP M (needs root or password-free sudo for fanotify)"; exit 0; fi
WORK="$(mktemp -d)"
trap '"${SUDO[@]}" kill "${WATCHER:-0}" 2>/dev/null; kill -9 "${BAD:-0}" "${BAD2:-0}" 2>/dev/null; "${SUDO[@]}" rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/tripwire-fakes.sh
. "$ROOT/tests/tripwire-fakes.sh"
export FORGEOS_TW_PROC=/proc FORGEOS_TW_CGROUP=/sys/fs/cgroup
wait_for() { for _ in $(seq 1 80); do eval "$1" && return 0; sleep 0.25; done; return 1; }
ids() { ls "$WORK/var/incidents" 2>/dev/null | sed 's/\.json$//'; }
kind_of() { for i in $(ids); do [ "$(py "$i" "i[\"kind\"]")" = "$1" ] && echo "$i"; done | tail -n 1; }

mapfile -t TWENV < <(env | grep "^FORGEOS_TW_[A-Z_]*=" | grep -v "^FORGEOS_TW_UID=")  # the watcher runs as root
"${SUDO[@]}" PATH="$PATH" HOME="$H" WORK="$WORK" PYTHONDONTWRITEBYTECODE=1 "${TWENV[@]}" python3 -B "$ENGINE" watch --for 60 > "$WORK/watch.log" 2>&1 &
WATCHER=$!
wait_for '[ -f "$WORK/var/status.json" ] && grep -q "\"on\"" "$WORK/var/status.json" && [ -f "$H/Documents/000 Bank statements.pdf" ]'
check M0 'grep -q "is watching" "$WORK/watch.log" && [ "$(stat -c %u "$H/Videos/zzz Tax return 2026.docx")" = "$ME" ]'

OUT="$(FORGEOS_TW_ROOT=0 python3 -B "$ENGINE" test)"; RC=$?
echo "  $OUT"
check M1 '[ "$RC" -eq 0 ] && grep -q "^PASS${T}Caught the pretend attacker after [0-9]* test files" <<< "$OUT" && [ ! -d "$H/Documents/ForgeOS tripwire test" ] && ! calls | grep -q "nmcli networking off"'

for i in $(seq 1 30); do letter "$H/Pictures/letter $i.txt" "$i"; done
python3 -c '
import os, sys, time
d = sys.argv[1]
for n in sorted(os.listdir(d)):
    if n.startswith("letter "):
        open(os.path.join(d, n + ".locked"), "wb").write(os.urandom(4096)); os.remove(os.path.join(d, n)); time.sleep(0.02)
time.sleep(60)' "$H/Pictures" &
BAD=$!
wait_for '[ -n "$(kind_of attack)" ]'; ID="$(kind_of attack)"
check M2 '[ -n "$ID" ] && [ "$(py "$ID" "i[\"pid\"], i[\"frozen\"]")" = "$BAD program" ] && [ "$(ps -o stat= -p "$BAD" | cut -c1)" = T ] && calls | grep -qx "nmcli networking off"'
check M3 '[ "$(ls "$H/Pictures" | grep -c "^letter .*\.txt$")" -ge 5 ] && [ "$(py "$ID" "len(i[\"files\"])")" -ge 20 ]'
kill -9 "$BAD"; wait "$BAD" 2>/dev/null

python3 -c 'import sys, time; open(sys.argv[1], "ab").write(b"x"); time.sleep(60)' "$H/Music/000 Bank statements.pdf" &
BAD2=$!
wait_for '[ "$(ids | wc -l)" -ge 3 ]'
check M4 'grep -q "safety files" <<< "$(py "$(ids | tail -n 1)" "i[\"reason\"]")" && [ "$(ps -o stat= -p "$BAD2" | cut -c1)" = T ]'
kill -9 "$BAD2"; wait "$BAD2" 2>/dev/null
sleep 1; rm -f "$H/Desktop/zzz Tax return 2026.docx"
wait_for '[ -n "$(kind_of bait)" ]'
check M5 '[ -n "$(kind_of bait)" ] && wait_for "[ -f \"$H/Desktop/zzz Tax return 2026.docx\" ]"'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; cat "$WORK/watch.log" "$WORK/calls.log"; ps -o pid,stat,cmd -p "$BAD" "$BAD2"; exit 1; fi
