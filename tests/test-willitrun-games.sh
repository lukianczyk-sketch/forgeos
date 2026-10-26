#!/usr/bin/env bash
# Tests for Will It Run? (Job 10), cases E-H: anti-cheat, the anti-cheat list, known programs, unknown names.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-willitrun-games.sh <repo-root>
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
mkpe "$DL/setup.exe" 8664 2 20b 0 22 "xx Inno Setup Setup Data xx"
echo com.usebottles.bottles >> "$WORK/installed"
printf 'hello' > "$DL/notes.txt"

# E: anti-cheat found next to the game or inside it
mkpe "$WORK/games/Shooter/Shooter.exe" 8664 2 20b 0 22
run "$WORK/games/Shooter/Shooter.exe"
check E1 '[ "$RC" -eq 1 ] && grep -q "Easy Anti-Cheat" <<< "$OUT" && grep -qx "VERDICT: maybe" <<< "$OUT" && grep -q "^WAY: bottles " <<< "$OUT"'
mkdir -p "$WORK/games/Tactic"
mkpe "$WORK/games/Tactic/Tactic.exe" 8664 2 20b 0 22
: > "$WORK/games/Tactic/VGK.SYS"
run "$WORK/games/Tactic/Tactic.exe"
check E2 '[ "$RC" -eq 2 ] && grep -q "Vanguard" <<< "$OUT" && grep -q "heart of Windows" <<< "$OUT"'
mkpe "$DL/lonely.exe" 8664 2 20b 0 22 "....xhunter1...."
run "$DL/lonely.exe"
check E3 '[ "$RC" -eq 2 ] && grep -q "XIGNCODE3" <<< "$OUT"'
# a Downloads folder is never searched: a stray anti-cheat file there does not count
mkdir -p "$DL/EasyAntiCheat"
run "$DL/setup.exe"
check E4 '[ "$RC" -eq 0 ] && ! grep -q "anti-cheat" <<< "$OUT"'

# F: the anti-cheat list knows the game (by file name or by folder name)
mkpe "$WORK/games/Rust/RustClient.exe" 8664 2 20b 0 22
run "$WORK/games/Rust/RustClient.exe"
check F1 '[ "$RC" -eq 2 ] && grep -q "blocks Linux on purpose" <<< "$OUT" && grep -q "Are We Anti-Cheat Yet" <<< "$OUT"'
run "Halo: The Master Chief Collection"
check F2 '[ "$RC" -eq 0 ] && grep -q "turned on Linux support" <<< "$OUT"'
run "pubg"
check F3 '[ "$RC" -eq 2 ] && grep -q "PUBG: Battlegrounds uses BattlEye" <<< "$OUT"'
FORGEOS_WIR_DIR="$WORK/none" FORGEOS_WIR_BASE="$WORK/wir" run "Elden Ring"
check F4 '[ "$RC" -eq 0 ] && grep -q "has not promised" <<< "$OUT"'

# G: known programs by name: Linux version, free swap, built in, launcher, will not run
run "Spotify"
check G1 '[ "$RC" -eq 0 ] && grep -q "own Linux version" <<< "$OUT" && grep -qx "WAY: flatpak com.spotify.Client" <<< "$OUT"'
echo com.spotify.Client >> "$WORK/installed"
run "SpotifySetup"
check G2 'grep -qx "WAY: open com.spotify.Client" <<< "$OUT"'
run "MSTeamsSetup"
check G3 '[ "$RC" -eq 0 ] && grep -qx "VERDICT: swap" <<< "$OUT" && grep -q "teams_for_linux" <<< "$OUT"'
run "SteamSetup"
check G4 '[ "$RC" -eq 0 ] && grep -qx "WAY: steam" <<< "$OUT"'
run "Install VALORANT"
check G5 '[ "$RC" -eq 2 ] && grep -q "Vanguard" <<< "$OUT"'
run "WinRAR"
check G6 '[ "$RC" -eq 0 ] && grep -q "Extract" <<< "$OUT" && ! grep -q "^WAY:" <<< "$OUT"'
run "WhatsApp"
check G7 '[ "$RC" -eq 0 ] && grep -qx "VERDICT: swap" <<< "$OUT" && grep -q "web.whatsapp.com" <<< "$OUT"'
mkdir -p "$WORK/apps/Microsoft Office"
mkpe "$WORK/apps/Microsoft Office/setup.exe" 8664 2 20b 0 22
run "$WORK/apps/Microsoft Office/setup.exe"
check G8 '[ "$RC" -eq 0 ] && grep -q "ONLYOFFICE" <<< "$OUT"'

# H: unknown names, empty input, missing files
run "Some Unknown Tool 3000"
check H1 '[ "$RC" -eq 1 ] && grep -q "not on my list" <<< "$OUT" && grep -qx "VERDICT: maybe" <<< "$OUT"'
OUT="$(bash "$WR" check "   " 2>&1)"; RC=$?
check H2 '[ "$RC" -eq 3 ]'
OUT="$(bash "$WR" 2>&1)"; RC=$?
check H3 '[ "$RC" -eq 3 ] && grep -q usage <<< "$OUT"'
chmod 000 "$DL/notes.txt"
run "$DL/notes.txt"
if [ -r "$DL/notes.txt" ]; then pass "H4 (skipped: running as root)"; else check H4 '[ "$RC" -eq 3 ] && grep -q "Cannot read" <<< "$OUT"'; fi
chmod 644 "$DL/notes.txt"

echo
if [ "$failures" -eq 0 ]; then echo "ALL WILL IT RUN? TESTS PASSED (E-H)"; else echo "$failures WILL IT RUN? TEST(S) FAILED (E-H)"; fi
[ "$failures" -eq 0 ]
