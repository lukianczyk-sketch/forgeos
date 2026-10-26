#!/usr/bin/env bash
# Tests for Will It Run? (Job 10), cases M-P: the private AI, the window, the daily anti-cheat list, menu entries, build setup, lists.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-willitrun-extras.sh <repo-root>
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
mkpe "$DL/setup.exe" 8664 2 20b 0 22
echo com.usebottles.bottles >> "$WORK/installed"

# M: the private AI guesses only for names on no list; its answer is marked as a guess
echo "model-b" > "$WORK/cfg/forgeos/ai-model"
export FAKE_TAGS='{"models":[{"name":"model-a"},{"name":"model-b"}]}'
FAKE_AI='{"answer":"It has a Linux version on Flathub."}' bash "$WR" check "Weird Tool 9" > "$WORK/out.txt"; RC=$?
OUT="$(cat "$WORK/out.txt")"
check M1 '[ "$RC" -eq 1 ] && grep -q "best guess" <<< "$OUT" && grep -q "It has a Linux version" <<< "$OUT" && grep -qx "VERDICT: maybe" <<< "$OUT"'
check M2 'jq -e ".model == \"model-b\" and .options.temperature == 0 and (.messages[1].content | contains(\"Weird Tool 9\")) and (.messages[0].content | contains(\"Weird\") | not)" "$WORK/body.json" >/dev/null'
rm -f "$WORK/body.json"
FAKE_AI='{"answer":"x"}' bash "$WR" check "Spotify" > /dev/null
check M3 '[ ! -e "$WORK/body.json" ]'
OUT="$(FAKE_AI="" bash "$WR" check "Weird Tool 9")"; RC=$?
check M4 '[ "$RC" -eq 1 ] && grep -q "not on my list" <<< "$OUT"'
unset FAKE_TAGS

# N: the window: shows the answer, runs the way only after the button is clicked
sed -i '/org.kde.krita/d' "$WORK/installed"; : > "$WORK/calls.log"; : > "$WORK/shown"
printf 'name\n' > "$WORK/menu"
FAKE_NAME="Photoshop" FAKE_YES=0 bash "$GUI" > /dev/null 2>&1
check N1 'grep -q "Install it (free)" "$WORK/shown" && grep -q "Krita" "$WORK/shown" && grep -q "flatpak install flathub org.kde.krita" "$WORK/calls.log"'
: > "$WORK/calls.log"; : > "$WORK/shown"
FAKE_YES=1 bash "$GUI" --file "$DL/setup.exe" > /dev/null 2>&1
check N2 'grep -q "Open it in Bottles" "$WORK/shown" && ! grep -q "flatpak run" "$WORK/calls.log"'
FAKE_YES=0 bash "$GUI" --file "$DL/setup.exe" > /dev/null 2>&1
check N3 'grep -q "flatpak run --file-forwarding com.usebottles.bottles" "$WORK/calls.log"'
mkpe "$DL/arm.exe" aa64 2 20b 0 22
: > "$WORK/shown"
bash "$GUI" --file "$DL/arm.exe" > /dev/null 2>&1
check N4 'grep -q -- "--sorry" "$WORK/shown" && grep -q "ARM" "$WORK/shown" && ! grep -q -- "--yesno" "$WORK/shown"'

# O: the daily anti-cheat list download (keeps the old list when a download is bad)
UPD="$ROOT/files/system/usr/libexec/forgeos-willitrun-update"
export FORGEOS_WIR_URL="https://example.invalid/games.json" FORGEOS_WIR_DIR="$WORK/upd"
jq -n '[range(150) | {name: ("Game " + tostring), status: "Supported", anticheats: ["Easy Anti-Cheat", "BattlEye"]}]
  + [{name: "Pipe|Game", status: "Broken", anticheats: []}, {name: "Odd", status: "Weird", anticheats: []}]' > "$WORK/games.json"
OUT="$(bash "$UPD" 2>&1)"; RC=$?
check O1 '[ "$RC" -eq 0 ] && [ "$(wc -l < "$WORK/upd/anticheat.list")" -eq 151 ] && grep -qx "Game 7|Supported|Easy Anti-Cheat, BattlEye" "$WORK/upd/anticheat.list"'
check O2 'grep -qx "Pipe Game|Broken|" "$WORK/upd/anticheat.list" && ! grep -q "Odd" "$WORK/upd/anticheat.list" && [ -z "$(find "$WORK/upd" -name ".download*")" ]'
jq -n '[{name: "Only", status: "Supported", anticheats: []}]' > "$WORK/games.json"
OUT="$(bash "$UPD" 2>&1)"; RC=$?
check O3 '[ "$RC" -eq 1 ] && [ "$(wc -l < "$WORK/upd/anticheat.list")" -eq 151 ]'
rm -f "$WORK/games.json"
OUT="$(bash "$UPD" 2>&1)"; RC=$?
check O4 '[ "$RC" -eq 1 ] && grep -q "old list is kept" <<< "$OUT" && [ "$(wc -l < "$WORK/upd/anticheat.list")" -eq 151 ]'

# P: menu entry, right-click entry, daily timer, build setup, CI, and the known-programs lists
U="$ROOT/files/system/usr"; D="$U/share/applications/forgeos-willitrun.desktop"
S="$U/share/kio/servicemenus/forgeos-willitrun.desktop"; SET="$ROOT/files/scripts/forgeos-setup.sh"
check P1 'grep -qx "Exec=/usr/bin/forgeos-willitrun-gui" "$D" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$D"; }'
check P2 'grep -qx "Exec=/usr/bin/forgeos-willitrun-gui --file %f" "$S" && grep -q "application/x-ms-dos-executable;" "$S" && grep -q "application/vnd.android.package-archive;" "$S"'
check P3 'grep -qx "Persistent=true" "$U/lib/systemd/system/forgeos-willitrun-update.timer" && grep -qx "ExecStart=/usr/libexec/forgeos-willitrun-update" "$U/lib/systemd/system/forgeos-willitrun-update.service"'
check P4 'grep -q "/usr/bin/forgeos-willitrun /usr/bin/forgeos-willitrun-gui /usr/libexec/forgeos-willitrun-update" "$SET" && grep -q "^systemctl enable forgeos-willitrun-update.timer" "$SET" && grep -q "^FORGEOS_WIR_DIR=/usr/share/forgeos/willitrun-base /usr/libexec/forgeos-willitrun-update" "$SET"'
check P5 '( for t in test-willitrun test-willitrun-games test-willitrun-open test-willitrun-extras test-willitrun-safety; do grep -q "bash tests/$t.sh ." "$ROOT/.github/workflows/tests.yml" || exit 1; done )'
bad="$(cat "$U"/share/forgeos/willitrun/*.txt | grep -v '^#' | awk -F ' ~ ' 'NF != 4 || $2 !~ /^(builtin|linux|swap|steam|heroic|lutris|web|no)$/ || $3 !~ /^(-|[A-Za-z0-9_-]+([.][A-Za-z0-9_-]+)+)$/ || $4 == ""')"
check P6 '[ -z "$bad" ] && [ "$(cat "$U"/share/forgeos/willitrun/*.txt | grep -vc "^#")" -ge 55 ]'
check P7 '( for f in "$U"/share/forgeos/willitrun/*.txt; do [ "$(wc -c < "$f")" -lt 6000 ] || exit 1; done )'

echo
if [ "$failures" -eq 0 ]; then echo "ALL WILL IT RUN? TESTS PASSED (M-P)"; else echo "$failures WILL IT RUN? TEST(S) FAILED (M-P)"; fi
[ "$failures" -eq 0 ]
