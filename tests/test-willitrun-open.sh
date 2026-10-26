#!/usr/bin/env bash
# Tests for Will It Run? (Job 10), cases I-L: opening the way to run it (Bottles, Flathub, Waydroid, Gear Lever, Steam).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-willitrun-open.sh <repo-root>
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
GUI="$ROOT/files/system/usr/bin/forgeos-willitrun-gui"
op() { : > "$WORK/calls.log"; OUT="$(bash "$WR" open "$@" 2>&1)"; RC=$?; }
mkpe "$DL/setup.exe" 8664 2 20b 0 22
mkpe "$WORK/games/Rust/Game.exe" 8664 2 20b 0 22
perl -e 'print "PK", pack("C2", 3, 4), "android"' > "$DL/game.apk"

# I: Bottles sees only the program's own file or folder, never the whole home folder
op bottles "$DL/setup.exe"
check I1 '[ "$RC" -eq 1 ] && grep -q "not installed" <<< "$OUT"'
echo com.usebottles.bottles >> "$WORK/installed"
op bottles "$DL/setup.exe"
check I2 '[ "$RC" -eq 0 ] && grep -qx "setsid -f flatpak run --file-forwarding com.usebottles.bottles -e @@ $DL/setup.exe @@" "$WORK/calls.log"'
mkdir -p "$HOME/Games/Old"
mkpe "$HOME/Games/Old/old.exe" 14c 2 10b 0 2
op bottles "$HOME/Games/Old/old.exe"
check I3 'grep -qx "setsid -f flatpak run --filesystem=$HOME/Games/Old com.usebottles.bottles -e $HOME/Games/Old/old.exe" "$WORK/calls.log"'
op bottles "$WORK/games/Rust/Game.exe"
check I4 'grep -q "file-forwarding" "$WORK/calls.log"'
op bottles "$DL/gone.exe"
check I5 '[ "$RC" -eq 3 ] && grep -q "gone" <<< "$OUT" && ! grep -q "flatpak run" "$WORK/calls.log"'

# J: only apps on the checked lists are installed or opened
op flatpak org.kde.krita
check J1 '[ "$RC" -eq 0 ] && grep -qx "setsid -f konsole --hold -e flatpak install flathub org.kde.krita" "$WORK/calls.log"'
op flatpak com.evil.App
check J2 '[ "$RC" -eq 2 ] && ! grep -q konsole "$WORK/calls.log"'
op open org.kde.krita
check J3 '[ "$RC" -eq 1 ] && ! grep -q "flatpak run" "$WORK/calls.log"'
echo org.kde.krita >> "$WORK/installed"
op open org.kde.krita
check J4 '[ "$RC" -eq 0 ] && grep -qx "setsid -f flatpak run org.kde.krita" "$WORK/calls.log"'
op flatpak io.github.dosbox-staging
check J5 '[ "$RC" -eq 0 ] && grep -q "flatpak install flathub io.github.dosbox-staging" "$WORK/calls.log"'

# K: Android apps: set up Waydroid first, start it if needed, then install
op waydroid "$DL/game.apk"
check K1 '[ "$RC" -eq 1 ] && grep -qx "setsid -f konsole --hold -e ujust setup-waydroid" "$WORK/calls.log" && ! grep -q "app install" "$WORK/calls.log"'
: > "$WORK/waydroid.cfg"
op waydroid "$DL/game.apk"
check K2 '[ "$RC" -eq 0 ] && grep -q "show-full-ui" "$WORK/calls.log" && grep -qx "waydroid app install $DL/game.apk" "$WORK/calls.log"'
FAKE_WAYDROID=RUNNING op waydroid "$DL/game.apk"
check K3 '[ "$RC" -eq 0 ] && ! grep -q "show-full-ui" "$WORK/calls.log"'
FAKE_WAYDROID=RUNNING FAKE_WAYDROID_ERR=1 op waydroid "$DL/game.apk"
check K4 '[ "$RC" -eq 1 ] && grep -q "could not install" <<< "$OUT"'

# L: Gear Lever, Steam, unknown ways
perl -e 'print pack("C4", 127, 69, 76, 70), "xxxxAI", pack("C", 2)' > "$DL/Tool.AppImage"
op gearlever "$DL/Tool.AppImage"
check L1 '[ "$RC" -eq 0 ] && grep -qx "setsid -f flatpak run --file-forwarding it.mijorus.gearlever @@ $DL/Tool.AppImage @@" "$WORK/calls.log"'
op steam
check L2 '[ "$RC" -eq 0 ] && grep -qx "setsid -f steam" "$WORK/calls.log"'
op format-disk /
check L3 '[ "$RC" -eq 3 ] && [ ! -s "$WORK/calls.log" ]'

echo
if [ "$failures" -eq 0 ]; then echo "ALL WILL IT RUN? TESTS PASSED (I-L)"; else echo "$failures WILL IT RUN? TEST(S) FAILED (I-L)"; fi
[ "$failures" -eq 0 ]
