#!/usr/bin/env bash
# Tests for Family Mode (Job 13), cases A-D: the helper, on (big text, guards, icons), Bigger,
# off (everything back exactly, only our desktop icons go).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-family.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/family-fakes.sh
. "$ROOT/tests/family-fakes.sh"
K="$WORK/kcfg"; SAVED="$WORK/state/forgeos/family/saved.json"; D="$HOME/Desktop"
key() { cat "$K/$1" 2>/dev/null; }
mode() { stat -c %a "$1"; }

# A: the helper - wrong number, wrong ID, no name, then right; cleaned; private; show; clear
O1="$(F helper set --name Brianna --phone "call me" 2>&1)"; R1=$?
O2="$(F helper set --name Brianna --rustdesk-id 12ab56 2>&1)"; R2=$?
O3="$(F helper set --name "  " 2>&1)"; R3=$?
F helper set --name Brianna --phone 12345 >/dev/null 2>&1; R6=$?
O4="$(F helper set --name "Bri<b>anna" --phone "+1 (661) 555-0123" --rustdesk-id "987 654 321" --me "$(printf 'Robert\nSmith')" 2>&1)"; R4=$?
check A1 '[ "$R1$R2$R3$R4$R6" = 11101 ] && grep -q "mobile number doesn.t look right" <<< "$O1" && grep -q "6 to 12 digits" <<< "$O2" && grep -q "type your helper.s name" <<< "$O3"'
check A2 '[ "$O4" = "Your helper is Bri b anna." ] && [ "$(mode "$WORK/cfg/forgeos/family.conf")" = 600 ] && [ "$(F helper show)" = "$(printf "name\tBri b anna\nphone\t+16615550123\nrustdesk_id\t987654321\nme\tRobert Smith")" ]'
F helper clear >/dev/null; F helper show >/dev/null; R5=$?
F helper set --name Brianna --phone 661-555-0123 --rustdesk-id 987654321 --me Robert >/dev/null
check A3 '[ "$R5" -eq 2 ] && grep -qx "name=Brianna" "$WORK/cfg/forgeos/family.conf"'

# B: on (Big) - fonts from Plasma defaults and one own font, pointer, taskbar, signals, icons, guards
mkdir -p "$K/kdeglobals/General"; echo "Inter,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" > "$K/kdeglobals/General/font"
echo "== $HOME/Desktop/notes.desktop" > "$D/notes.desktop"
BEFORE="$(snap)"
OUT="$(F on --size big)"; RC=$?
check B1 '[ "$RC" -eq 0 ] && grep -q "^Family Mode is ON. Text size: Big.$" <<< "$OUT" && [ "$(key kdeglobals/General/font)" = "Inter,15,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" ] && [ "$(key kdeglobals/General/menuFont)" = "Noto Sans,14,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" ] && [ "$(key kdeglobals/General/smallestReadableFont)" = "Noto Sans,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" ] && [ "$(key kdeglobals/WM/activeFont)" = "Noto Sans,14,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" ]'
check B2 '[ "$(key kcminputrc/Mouse/cursorSize)" = 48 ] && [ "$(paste -sd, "$WORK/panels")" = "1:56,7:60" ] && grep -q "^dbus-send --session --type=signal /KDEPlatformTheme org.kde.KDEPlatformTheme.refreshFonts$" "$WORK/calls.log" && grep -q "^dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:5 int32:0$" "$WORK/calls.log" && grep -q "^kwriteconfig6 --file kdeglobals --group General --key font --notify Inter,15" "$WORK/calls.log"'
check B3 '(for f in callhelp scamshield askpc; do p="$D/forgeos-family-forgeos-$f.desktop"; [ -x "$p" ] && sed -n 2p "$p" | grep -qx "X-ForgeOS-Family=true" || exit 1; done) && grep -qx "Name=Is this a scam?" "$D/forgeos-family-forgeos-scamshield.desktop" && grep -qx "Exec=/usr/libexec/forgeos-family-call" "$D/forgeos-family-forgeos-callhelp.desktop"'
check B4 'grep -qx "  Turned on now: GhostFinder - warns you if a tracker is following you" <<< "$OUT" && grep -q "^  OFF - ask your helper to turn it on (needs a password): Undo Button" <<< "$OUT" && grep -qx forgeos-ghost-watch.timer "$WORK/enabled" && [ "$(mode "$SAVED")" = 600 ]'
check B5 '[ "$(head -n 4 <<< "$(F status)" | paste -sd,)" = "STATUS${T}on,SIZE${T}big,HELPER${T}Brianna,RUSTDESK${T}locked" ] && grep -q "^GUARD${T}needs-password${T}Undo Button" <<< "$(F status)"'

# C: on again keeps the first saved originals; Bigger counts from them; Big again; size while off
F on >/dev/null; F size bigger >/dev/null
check C1 'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d[\"look\"][\"fonts\"][\"General/font\"].startswith(\"Inter,11,\") and d[\"look\"][\"panels\"]=={\"1\":44,\"7\":60} and d[\"size\"]==\"bigger\"" "$SAVED"'
check C2 '[ "$(key kdeglobals/General/font)" = "Inter,20,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" ] && [ "$(key kcminputrc/Mouse/cursorSize)" = 64 ] && [ "$(paste -sd, "$WORK/panels")" = "1:68,7:68" ]'
F size big >/dev/null
check C3 '[ "$(key kdeglobals/General/font)" = "Inter,15,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" ] && [ "$(paste -sd, "$WORK/panels")" = "1:56,7:60" ]'

# D: off - everything back byte for byte; only our icons go; guards stay on; off again is fine
cp "$D/forgeos-family-forgeos-askpc.desktop" "$WORK/askpc.ours"
OUT="$(F off)"; RC=$?
check D1 '[ "$RC" -eq 0 ] && [ "$(snap)" = "$BEFORE" ] && [ ! -e "$SAVED" ] && [ ! -e "$WORK/rd/RustDesk2.toml" ] && grep -q "safety guards stay on" <<< "$OUT"'
check D2 '[ "$(ls "$D")" = notes.desktop ] && grep -qx forgeos-ghost-watch.timer "$WORK/enabled" && [ "$(F off)" = "Family Mode is already off." ] && grep -q "^STATUS${T}off$" <<< "$(F status)"'
grep -v X-ForgeOS-Family "$WORK/askpc.ours" > "$D/forgeos-family-forgeos-askpc.desktop"
F on >/dev/null; F off >/dev/null
check D3 '[ -e "$D/forgeos-family-forgeos-askpc.desktop" ] && [ ! -e "$D/forgeos-family-forgeos-callhelp.desktop" ]'
rm -f "$D/forgeos-family-forgeos-askpc.desktop"

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1
