#!/usr/bin/env bash
# Tests for Why Is It Slow? (Job 20), cases F-I: background jobs, start-up, internet vs. PC, a restart that is
# due, and a hidden program (Clean Sweep), worst first.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-slow-more.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/slow-fakes.sh
. "$ROOT/tests/slow-fakes.sh"
auto() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n%s' "$3" "$2" "${4:-}" > "$1"; }

# F: background jobs - Find Anything (a Python program) can be paused; a quiet update check is not reported
prog 5001 comm=python3 cpu=60 "cmdline=/usr/bin/python3 -B /usr/bin/forgeos-find index"
prog 5002 comm=fossilize_replay cpu=90
OUT="$(SL check)"
check F1 '[ "$(grep -c "^PROBLEM${T}background${T}" <<< "$OUT")" = 2 ] && grep -qx "PROBLEM${T}background${T}yellow${T}Find Anything is reading your files so it can find them later.${T}pause find${T}Pause it for now" <<< "$OUT"'
check F2 'grep -q "^PROBLEM${T}background${T}yellow${T}Steam is getting a game ready to play" <<< "$OUT" && ! grep -q "^PROBLEM${T}busy${T}.*Forgeos-find" <<< "$OUT"'
normal_pc; prog 5003 comm=flatpak cpu=2
OUT="$(SL check)"
check F3 'grep -qx "OK${T}background${T}No big jobs running in the background." <<< "$OUT"'

# G: slow start-up lists the programs that start with the PC (desktop parts are never listed)
normal_pc
echo "Startup finished in 9.0s (firmware) + 1min 12.4s (userspace) = 1min 41.4s" > "$WORK/boot"
mkdir -p "$WORK/config/autostart"
auto "$WORK/xdg-autostart/org.kde.plasmashell.desktop" plasmashell "Plasma"
auto "$WORK/xdg-autostart/discord.desktop" discord "Discord"
auto "$WORK/xdg-autostart/kaccess.desktop" kaccess "Accessibility"
auto "$WORK/config/autostart/steam.desktop" steam "Steam"
auto "$WORK/config/autostart/zoom.desktop" zoom "Zoom" "Hidden=true"$'\n'
OUT="$(SL check)"
check G1 '[ "$(line startup)" = "PROBLEM${T}startup${T}yellow${T}Starting the desktop and programs takes about 72 seconds. Programs that start with it: Discord, Steam. Switching off the ones you don'"'"'t need makes it faster.${T}startup${T}Choose what starts" ]'
OUT="$(SL startup)"
check G2 '[ "$OUT" = "APP${T}discord${T}Discord${T}on"$'"'"'\n'"'"'"APP${T}steam${T}Steam${T}on"$'"'"'\n'"'"'"APP${T}zoom${T}Zoom${T}off" ]'
echo "Startup finished in 9.0s (firmware) + 20.4s (userspace) = 29.4s" > "$WORK/boot"
for n in a b c d e f; do auto "$WORK/config/autostart/$n.desktop" "$n" "App $n"; done
OUT="$(SL check)"
check G3 'line startup | grep -q "${T}yellow${T}8 programs start with the PC. Programs that start with it: App a, App b, App c, App d, App e."'

# H: internet vs. PC
normal_pc; touch "$WORK/net-noroute"
OUT="$(SL check)"
check H1 '[ "$(line internet)" = "PROBLEM${T}internet${T}red${T}This PC is not connected to the internet.${T}internet${T}Restart the internet" ] && ! grep -q "^ping" "$WORK/calls.log"'
normal_pc; echo "no:90:Neighbor"$'\n'"yes:25:HomeWiFi" > "$WORK/wifi"
OUT="$(SL check)"
check H2 'line internet | grep -q "${T}yellow${T}Your PC is fine. The Wi-Fi signal is weak (25 of 100) - move closer to the router or restart the router.${T}-${T}-$"'
normal_pc; printf '3 packets transmitted, 2 received, 33%% packet loss\nrtt min/avg/max/mdev = 3.0/80.0/150.0/40.0 ms\n' > "$WORK/net-192.168.1.1"
OUT="$(SL check)"
check H3 'line internet | grep -q "${T}Your PC is fine. The connection to your router is poor - restart the router (unplug it for 30 seconds).${T}"'
normal_pc; printf '3 packets transmitted, 0 received, 100%% packet loss\n' > "$WORK/net-9.9.9.9"
OUT="$(SL check)"
check H4 'line internet | grep -q "${T}Your PC and your router are fine. The internet itself is slow right now - that is your internet company."'
normal_pc; FORGEOS_SLOW_LOOKUP=no-such-name.invalid OUT="$(SL check)"
check H5 'line internet | grep -q "Finding websites by name is slow. Restarting the router usually fixes it.${T}internet${T}Restart the internet$"'

# I: a restart that is due (on for weeks, an update waiting), a hidden program first of all
normal_pc; mk uptime "$WORK/proc" 23
OUT="$(SL check)"
check I1 '[ "$(line restart)" = "PROBLEM${T}restart${T}yellow${T}Your PC has been on for 23 days. A restart clears out old clutter.${T}restart${T}Restart now" ]'
echo '{"deployments": [{"booted": false}, {"booted": true}]}' > "$WORK/ostree"
OUT="$(SL check)"
check I2 'line restart | grep -q "${T}Your PC has been on for 23 days. An update is waiting for a restart. A restart"'
normal_pc; mk temp "$WORK/sys" coretemp 92
prog 6001 comm=kworkerds cpu=190 exe=/tmp/.x/kworkerds
OUT="$(SL check)"
check I3 '[ "$(sed -n 1p <<< "$OUT")" = "PROBLEM${T}hidden${T}red${T}Something hidden is using the computer'"'"'s power: \"Kworkerds\" runs from /tmp/.x/kworkerds. That is a trick some viruses use. Clean Sweep checks it and locks it away if it is bad.${T}cleansweep${T}Run Clean Sweep" ] && ! grep -q "^PROBLEM${T}busy${T}" <<< "$OUT"'
check I4 '[ "$(cut -f 2 <<< "$OUT" | grep -v -x -e memory -e disk -e drive -e power -e background -e startup -e internet -e restart -e busy | tr "\n" " ")" = "hidden heat " ]'
normal_pc; prog 6002 comm=miner cpu=120 "exe=$HOME/.config/.cache/miner (deleted)"
prog 6003 comm=wine64 cpu=100 "exe=$HOME/.wine/drive_c/game.exe"
OUT="$(SL check)"
check I5 'line hidden | grep -q "runs from .*/home/.config/.cache/miner - a file that was deleted." && line busy | grep -q "^PROBLEM${T}busy${T}yellow${T}Wine64 is using"'

echo
if [ "$failures" -eq 0 ]; then echo "All Why Is It Slow? tests F-I passed."; else echo "$failures Why Is It Slow? test(s) failed."; fi
exit "$((failures > 0))"
