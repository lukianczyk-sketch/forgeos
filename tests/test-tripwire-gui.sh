#!/usr/bin/env bash
# Tests for Ransomware Tripwire (Job 16), cases K-L: your session's alert (critical note, big window,
# Always-On Guard's warnings list, shown once) and the window's buttons with a fake kdialog.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-tripwire-gui.sh <repo-root>
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
caught() {
  rm -rf "$WORK/homes/.snapshots"; for i in $(seq 1 22); do letter "$H/Documents/letter $i.txt" "$i"; done; snap 3 1
  prog 4242 invoice.exe "$APP/app-wine-4242.scope" "$H/Downloads/invoice.exe"; attack 4242 "$H/Documents" 20; replay >/dev/null
}
answers() { printf '%s\n' "$@" > "$WORK/kd-answers"; }
G() { FORGEOS_TW_ROOT=0 bash "$GUI" "$@"; }
CG="$WORK/cg$APP/app-wine-4242.scope"
events() { cat "$WORK/state/forgeos/guard/events.log" 2>/dev/null; }

# K: the alert in your session: a critical note + the big window + Always-On Guard's list, once
fresh; caught; ID="$(inc)"
OUT="$(TW alert-watch --once)"
check K1 '[ "$OUT" = "SHOWN${T}$ID" ] && calls | grep -q "^notify-send --app-name=Ransomware Tripwire --icon=security-low --urgency=critical A program was scrambling your files ForgeOS stopped invoice.exe and cut the internet" && calls | grep -qx "gui --incident $ID"'
check K2 'events | grep -q "${T}ransomware${T}tripwire${T}$H/Downloads/invoice.exe${T}It scrambled 20 files in 10 seconds.${T}$ID${T}"'
OUT="$(TW alert-watch --once)"
check K3 '[ -z "$OUT" ] && [ "$(calls | grep -c "^gui --incident")" = 1 ]'
fresh; : > "$WORK/feed"; replay >/dev/null; rm "$H/Music/000 Bank statements.pdf"; gone 0 "$H/Music/000 Bank statements.pdf"; replay >/dev/null
TW alert-watch --once >/dev/null
check K4 'calls | grep -q "^notify-send .*--urgency=normal A safety file was removed" && ! calls | grep -q "^gui "'
fresh; caught; ID="$(inc)"; FORGEOS_TW_UID=4321 TW alert-watch --once >/dev/null
check K5 '! calls | grep -q "^notify-send" && ! calls | grep -q "^gui "'

# L1: the big window: Put my files back -> remove it too -> turn the internet back on
fresh; caught; ID="$(inc)"
answers restore "" "" "" "" ""; G --incident "$ID"
check L1 '[ "$(ls "$H/Documents" | grep -c "^letter .*\.txt$")" = 22 ] && [ "$(cat "$CG/cgroup.kill")" = 1 ] && [ "$(cat "$WORK/net-state")" = enabled ] && [ ! -s "$WORK/kd-answers" ]'
check L2 'calls | grep -q "^kdialog --title Ransomware Tripwire - program stopped --menu <h2><font color=\"#c00000\">STOP - a program was scrambling your files</font></h2>.*Program: <b>invoice.exe</b>.*Files it touched: 20.*restore Put my files back (recommended)"'
check L3 'calls | grep -q "^kdialog --title Ransomware Tripwire --msgbox Done. 20 file(s) came back from the copy of [0-9-]* [0-9:]*.<br>20 scrambled copies were locked away in Always-On Guard."'
# L4: Decide later: it stays frozen, the internet stays off
fresh; caught; ID="$(inc)"; answers later ""; G --incident "$ID"
check L4 '[ "$(cat "$CG/cgroup.freeze")" = 1 ] && [ "$(py "$ID" "i[\"state\"]")" = frozen ] && [ "$(cat "$WORK/net-state")" = disabled ]'
# L5: It's mine (yes) -> unfrozen and trusted; keep the internet off
answers mine "" "" rc1; G --incident "$ID"
check L5 '[ "$(cat "$CG/cgroup.freeze")" = 0 ] && [ "$(py "$ID" "i[\"state\"]")" = released ] && [ "$(cat "$WORK/net-state")" = disabled ]'
# L6: the main window lists the frozen program and the internet button; L7: a handled one is not shown again
fresh; caught; ID="$(inc)"; answers rc1; G
check L6 'calls | grep -q "^kdialog --title Ransomware Tripwire --menu ON - watching your folders.*i:$ID Still frozen: invoice.exe .* net Turn the internet back on test Test the tripwire explain How does it work?$"'
TW remove "$ID" >/dev/null; answers ""; G --incident "$ID"
check L7 'calls | grep -q "^kdialog --title Ransomware Tripwire --msgbox This program was already handled (removed)."'
G --bogus >/dev/null 2>&1; R1=$?
check L8 '[ "$R1" -eq 3 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
