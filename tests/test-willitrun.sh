#!/usr/bin/env bash
# Tests for Will It Run? (Job 10), cases A-D: file types, Windows programs, Android, Linux and Mac files.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-willitrun.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/willitrun-fakes.sh
. "$ROOT/tests/willitrun-fakes.sh"
DL="$HOME/Downloads"
run() { OUT="$(bash "$WR" check --no-ai "$@" 2>&1)"; RC=$?; }

# A: a normal 64-bit Windows installer runs in Bottles; Bottles not installed = offer to install it
mkpe "$DL/setup.exe" 8664 2 20b 0 22 "xx Inno Setup Setup Data xx"
run "$DL/setup.exe"
check A1 '[ "$RC" -eq 0 ] && grep -q "should run in Bottles" <<< "$OUT" && grep -q "installer (Inno Setup)" <<< "$OUT" && grep -qx "VERDICT: yes" <<< "$OUT"'
check A2 'grep -qx "WAY: flatpak com.usebottles.bottles" <<< "$OUT"'
echo com.usebottles.bottles >> "$WORK/installed"
run "$DL/setup.exe"
check A3 'grep -qx "WAY: bottles $DL/setup.exe" <<< "$OUT"'
mkdir -p "$WORK/games/Cubes/Cubes_Data" "$DL/Notes_Data"
mkpe "$WORK/games/Cubes/Cubes.exe" 8664 2 20b 0 22
run "$WORK/games/Cubes/Cubes.exe"
check A4 '[ "$RC" -eq 0 ] && grep -q "looks like a game" <<< "$OUT"'
run "$DL/setup.exe"
check A5 '! grep -q "looks like a game" <<< "$OUT"'

# B: what the program file says about itself: .NET, 32-bit, ARM, driver, library
mkpe "$DL/tool.exe" 14c 3 10b 1 2
run "$DL/tool.exe"
check B1 '[ "$RC" -eq 0 ] && grep -q "NET program" <<< "$OUT" && grep -q "32-bit" <<< "$OUT"'
mkpe "$DL/arm.exe" aa64 2 20b 0 22
run "$DL/arm.exe"
check B2 '[ "$RC" -eq 2 ] && grep -q "ARM" <<< "$OUT" && grep -qx "VERDICT: no" <<< "$OUT" && ! grep -q "^WAY:" <<< "$OUT"'
mkpe "$DL/printer.exe" 8664 1 20b 0 22
run "$DL/printer.exe"
check B3 '[ "$RC" -eq 2 ] && grep -q "Windows driver" <<< "$OUT"'
mkpe "$DL/part.dll" 8664 2 20b 0 2022
run "$DL/part.dll"
check B4 '[ "$RC" -eq 2 ] && grep -q "library" <<< "$OUT"'

# C: files that lie about what they are, and files that are not programs
printf 'just text' > "$DL/invoice.exe"
run "$DL/invoice.exe"
check C1 '[ "$RC" -eq 2 ] && grep -q "not what its name says" <<< "$OUT" && grep -q "Do not open it" <<< "$OUT"'
printf 'MZ' > "$DL/old.com"
run "$DL/old.com"
check C2 '[ "$RC" -eq 0 ] && grep -q "old DOS" <<< "$OUT" && grep -qx "WAY: flatpak io.github.dosbox-staging" <<< "$OUT"'
perl -e 'print "MZ", pack("x58"), pack("V", 64), pack("x400")' > "$DL/olddos.exe"
run "$DL/olddos.exe"
check C5 '[ "$RC" -eq 0 ] && grep -q "old DOS" <<< "$OUT"'
printf 'hello' > "$DL/notes.txt"
run "$DL/notes.txt"
check C3 '[ "$RC" -eq 1 ] && grep -q "does not look like a program" <<< "$OUT"'
printf 'Write-Host hi' > "$DL/fix.ps1"
run "$DL/fix.ps1"
check C4 '[ "$RC" -eq 2 ] && grep -q "PowerShell" <<< "$OUT"'

# D: Android apps, Linux apps, Mac programs, other Linux packages
perl -e 'print "PK", pack("C2", 3, 4), "android"' > "$DL/game.apk"
run "$DL/game.apk"
check D1 '[ "$RC" -eq 0 ] && grep -q "Android app" <<< "$OUT" && grep -qx "WAY: waydroid $DL/game.apk" <<< "$OUT"'
perl -e 'print pack("C4", 127, 69, 76, 70), "xxxx", "AI", pack("C", 2), "rest"' > "$DL/Tool.AppImage"
run "$DL/Tool.AppImage"
check D2 '[ "$RC" -eq 0 ] && grep -q "AppImage" <<< "$OUT" && grep -qx "WAY: gearlever $DL/Tool.AppImage" <<< "$OUT"'
perl -e 'print pack("C4", 127, 69, 76, 70), "plain linux"' > "$DL/mytool"
run "$DL/mytool"
check D3 '[ "$RC" -eq 0 ] && grep -q "Linux program" <<< "$OUT" && ! grep -q "^WAY:" <<< "$OUT"'
printf 'x' > "$DL/Photoshop.dmg"
run "$DL/Photoshop.dmg"
check D4 '[ "$RC" -eq 0 ] && grep -qx "VERDICT: swap" <<< "$OUT" && grep -q "Krita" <<< "$OUT"'
printf 'x' > "$DL/thing.dmg"
run "$DL/thing.dmg"
check D5 '[ "$RC" -eq 2 ] && grep -q "Apple Mac" <<< "$OUT"'
printf 'x' > "$DL/thing.deb"
run "$DL/thing.deb"
check D6 '[ "$RC" -eq 1 ] && grep -q "other Linux systems" <<< "$OUT"'

echo
if [ "$failures" -eq 0 ]; then echo "ALL WILL IT RUN? TESTS PASSED (A-D)"; else echo "$failures WILL IT RUN? TEST(S) FAILED (A-D)"; fi
[ "$failures" -eq 0 ]
