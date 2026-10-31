#!/usr/bin/env bash
# Tests for Always-On Guard (Job 13b), cases A-B: check files by hand with real ClamAV: clamscan, then the
# always-ready clamd (and back to clamscan when it is stopped).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-guard.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'stop_clamd; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/guard-fakes.sh
. "$ROOT/tests/guard-fakes.sh"
D="$HOME/Downloads"
command -v clamscan >/dev/null 2>&1 || { echo "FAIL clamscan is needed (apt-get install clamav)"; exit 1; }

# A: clamscan (no always-ready checker): clean, virus (locked away), fake double ending, too big, gone
echo "hello" > "$D/letter.txt"; virus "$D/photo.jpg"; echo "MZ" > "$D/invoice.pdf.exe"; truncate -s 401M "$D/huge.iso"
OUT="$(G scan "$D/letter.txt" "$D/photo.jpg" "$D/invoice.pdf.exe" "$D/huge.iso" "$D/gone.txt")"; RC=$?
QID="$(grep "^VIRUS" <<< "$OUT" | cut -f 4)"
check A1 '[ "$RC" -eq 1 ] && grep -qx "CLEAN${T}$D/letter.txt" <<< "$OUT" && grep -q "^VIRUS${T}$D/photo.jpg${T}ForgeOS.Test.Eicar.UNOFFICIAL${T}" <<< "$OUT"'
check A2 '[ ! -e "$D/photo.jpg" ] && [ "$(stat -c %a "$QD/$QID")" = 0 ] && [ "$(stat -c %a "$(dirname "$QD/$QID")")" = 700 ] && grep -q "^20.*${T}$D/photo.jpg${T}[0-9a-f]\{64\}${T}ForgeOS.Test.Eicar" "$QD/quarantine.log"'
check A3 'grep -q "^RISKY${T}$D/invoice.pdf.exe${T}fake double ending: it looks like a PDF file but it is a program (.exe)$" <<< "$OUT" && grep -qx "UNCHECKED${T}$D/huge.iso" <<< "$OUT" && grep -qx "UNCHECKED${T}$D/gone.txt" <<< "$OUT"'
check A4 'grep -q "^clamscan " "$WORK/calls.log" && ! grep -q "^clamdscan" "$WORK/calls.log" && ! grep -q huge.iso "$WORK/calls.log" && grep -q "${T}virus${T}scan${T}$D/photo.jpg${T}ForgeOS.Test.Eicar.UNOFFICIAL${T}$QID${T}" "$EV"'
echo hi > "$D/a.txt"; G scan "$D/a.txt" >/dev/null; R0=$?; G scan "$D/invoice.pdf.exe" >/dev/null; R2=$?; G scan "$D/gone.txt" >/dev/null; R3=$?
echo "Sub Auto" > "$D/budget.xlsm"; echo x > "$D/run.js"
check A5 '[ "$R0$R2$R3" = 023 ] && grep -q "macros can run hidden programs" <<< "$(G scan "$D/budget.xlsm")" && grep -q "Windows program or script (.js)" <<< "$(G scan "$D/run.js")"'
rm -f "$D/huge.iso"

# B: the always-ready checker (real clamd): used when running; a stopped one (old socket) falls back to clamscan
if start_clamd; then
  : > "$WORK/calls.log"; virus "$D/song.mp3"; echo fine > "$D/notes.txt"
  OUT="$(G scan "$D/song.mp3" "$D/notes.txt")"; RC=$?
  check B1 '[ "$RC" -eq 1 ] && grep -q "^VIRUS${T}$D/song.mp3${T}ForgeOS.Test.Eicar.UNOFFICIAL${T}" <<< "$OUT" && grep -qx "CLEAN${T}$D/notes.txt" <<< "$OUT" && [ "$(grep -c "^clamdscan --config-file=$WORK/cl/clamd.conf --stream --no-summary" "$WORK/calls.log")" = 2 ] && ! grep -q "^clamscan" "$WORK/calls.log"'
  check B2 'grep -qx "GUARD${T}downloads${T}on${T}fast" <<< "$(G status)"'
  kill -STOP "$(cat "$WORK/cl/run/clamd.pid")"; kill "$(cat "$WORK/cl/run/clamd.pid")"; kill -CONT "$(cat "$WORK/cl/run/clamd.pid")"; sleep 1
  [ -S "$WORK/cl/run/clamd.sock" ] || { python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$WORK/cl/run/clamd.sock"; }
  : > "$WORK/calls.log"; virus "$D/movie.mp4"
  OUT="$(G scan "$D/movie.mp4")"; RC=$?
  check B3 '[ "$RC" -eq 1 ] && grep -q "^VIRUS${T}$D/movie.mp4${T}ForgeOS.Test.Eicar" <<< "$OUT" && grep -q "^clamdscan" "$WORK/calls.log" && grep -q "^clamscan" "$WORK/calls.log"'
  rm -f "$WORK/cl/run/clamd.sock"
else
  echo "SKIP B1-B3 (clamd + clamdscan are not installed: apt-get install clamav-daemon clamdscan)"
fi
check B4 'grep -qx "GUARD${T}downloads${T}on${T}low-memory" <<< "$(G status)"'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
