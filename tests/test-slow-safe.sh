#!/usr/bin/env bash
# Tests for Why Is It Slow? (Job 20), case N: real-world traps - Flatpak apps (bwrap first), a hidden program
# inside another app, names that try to add fake lines, KDE parts with cut names, Proton games, shared
# memory (Pss), start-up entries that never run on KDE, a broken history line, AMD's Tctl, self-updated apps.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-slow-safe.sh <repo-root>
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
FP=/user.slice/user-1000.slice/user@1000.service/app.slice/app-flatpak-com.brave.Browser-12345.scope

# N1: a Flatpak app - bwrap comes first, but the app is reported and Close goes to the app, not bwrap
app com.brave.Browser Brave
prog 2000 comm=bwrap cpu=0 rss=2 cgroup="$FP"; prog 2001 comm=bwrap cpu=0 rss=2 cgroup="$FP"
prog 2003 comm=brave cpu=250 rss=900 cgroup="$FP"
OUT="$(SL check)"
check N1 'line busy | grep -q "${T}Brave is using most of the computer.s power. Closing it.*${T}close 2003 com.brave.Browser${T}Close Brave$"'
# N2: a hidden program inside Konsole's group gets the warning; Konsole is not blamed
normal_pc; KS=/user.slice/app.slice/app-org.kde.konsole-0123456789abcdef0123456789abcdef.scope
prog 3000 comm=konsole cpu=1 cgroup="$KS"; prog 3005 comm=kworkerds cpu=300 exe=/tmp/.x/kworkerds cgroup="$KS"
OUT="$(SL check)"
check N2 'line hidden | grep -q "\"Kworkerds\" runs from /tmp/.x/kworkerds" && ! grep -q "Konsole\|konsole" <<< "$(line busy)"'
# N3: a program path with a new line and tabs can't add a line or a button
normal_pc; prog 3100 comm=evil cpu=300 exe=$'/tmp/x/a\nPROBLEM\tbusy\tred\tFake\trestart\tClick me'
OUT="$(SL check)"
check N3 '[ "$(grep -c "^PROBLEM" <<< "$OUT")" = 1 ] && [ "$(line hidden | awk -F "$T" "{print NF}")" = 6 ] && ! grep -q "Click me$" <<< "$OUT"'
# N4: KDE parts with names the kernel cut to 15 letters, and anything in the KDE session's group, are never blamed
normal_pc; prog 3200 comm=kactivitymanage cpu=150 rss=3000; prog 3201 comm=org_kde_powerde cpu=120
prog 3202 comm=helperd cpu=110 cgroup=/user.slice/user@1000.service/session.slice/plasma-foo.service
OUT="$(SL check)"
check N4 '! grep -q "^PROBLEM${T}busy" <<< "$OUT"'
# N5: a Proton game with a cut name is a game
normal_pc; prog 3300 comm=Cyberpunk2077.e cpu=190 "cmdline=Z:\\games\\Cyberpunk2077.exe"
OUT="$(SL check)"
check N5 'line busy | grep -q "That is normal while a game is running.${T}-${T}-$"'
# N6: memory counts each app's fair share (Pss), not the same memory again for every child process
normal_pc; mk mem "$WORK/proc" 8 0.3; mk pressure "$WORK/proc" memory 25.00 18.00 12.00
for p in 4001 4002 4003; do prog "$p" comm=chrome cpu=1 rss=2000; printf 'Rss: 2048000 kB\nPss: 300000 kB\n' > "$WORK/proc/$p/smaps_rollup"; done
OUT="$(SL check)"
check N6 'line memory | grep -q "Chrome is using 879 MB\." && line memory | grep -q "${T}close 4001 chrome${T}"'
# N7: start-up entries that never run on KDE are not listed; "switch on" really switches on
normal_pc; mkdir -p "$WORK/config/autostart"
printf '[Desktop Entry]\nName=Tracker\nOnlyShowIn=GNOME;\n' > "$WORK/xdg-autostart/tracker.desktop"
printf '[Desktop Entry]\nName=Gtk dirs\nNotShowIn=KDE;\n' > "$WORK/xdg-autostart/gtkdirs.desktop"
printf '[Desktop Entry]\nName=Gone\nTryExec=no-such-program-here\n' > "$WORK/xdg-autostart/gone.desktop"
printf '[Desktop Entry]\nName=Discord\nX-GNOME-Autostart-enabled=false\n' > "$WORK/config/autostart/discord.desktop"
OUT="$(SL startup)"; OUT2="$(SL fix startup-on discord)"
check N7 '[ "$OUT" = "APP${T}discord${T}Discord${T}off" ] && [ "$OUT2" = "Discord will start with the PC again." ] && [ "$(SL startup)" = "APP${T}discord${T}Discord${T}on" ]'
# N8: a broken history line is skipped; an idle rpm-ostreed is not an update; odd download names are left alone
normal_pc; mkdir -p "${HIST%/*}"; echo "{\"t\": $(date +%s), \"mem\": 50}" > "$HIST"
prog 3400 comm=rpm-ostreed uid=0 cpu=0
mkdir -p "$HOME/Downloads"; head -c 5000 /dev/zero > "$HOME/Downloads/foo"$'\n'"bar.iso"; touch -d "200 days ago" "$HOME/Downloads/foo"$'\n'"bar.iso"
OUT="$(SL earlier 30)"; OUT2="$(SL check)"; OUT3="$(FORGEOS_SLOW_BIG=4000 SL space)"
check N8 '[ "$OUT" = "Nothing was slowing the PC in the last 30 minutes." ] && ! grep -q "update" <<< "$OUT2" && ! grep -q "^BIG" <<< "$OUT3"'
# N9: AMD's Tctl reads high on purpose - the real sensor is used; AppImages and self-updated apps are fine
normal_pc; D="$WORK/sys/class/hwmon/hwmon0"
echo 97000 > "$D/temp1_input"; echo Tctl > "$D/temp1_label"; echo 77000 > "$D/temp3_input"; echo Tccd1 > "$D/temp3_label"
prog 3500 comm=obsidian cpu=120 exe=/tmp/.mount_ObsidiX/obsidian; prog 3501 comm=steamwebhelper cpu=10 "exe=$HOME/.local/share/Steam/x (deleted)"
OUT="$(SL check)"
check N9 '! grep -q "^PROBLEM${T}heat" <<< "$OUT" && ! grep -q "^PROBLEM${T}hidden" <<< "$OUT" && line busy | grep -q "Obsidian is using"'

echo
if [ "$failures" -eq 0 ]; then echo "All Why Is It Slow? tests N passed."; else echo "$failures Why Is It Slow? test(s) failed."; fi
exit "$((failures > 0))"
