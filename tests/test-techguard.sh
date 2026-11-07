#!/usr/bin/env bash
# Tests for Fake Tech Support Guard (Job 17), cases A-C: a remote-control app starts and is paused at once
# (Flatpak, a Windows program in Wine, one started from a terminal), normal programs are left alone, an app
# that is gone, the status / report lines, and the remote-app list.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-techguard.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/techguard-fakes.sh
. "$ROOT/tests/techguard-fakes.sh"
EVENTS="$WORK/state/forgeos/guard/events.log"

# A: nothing / normal programs -> nothing; AnyDesk (Flatpak) -> paused, window, critical note, warnings list
fresh
prog 10 firefox "$APP/app-org.mozilla.firefox-1.scope"
prog 11 kwin_wayland /user.slice/user-1000.slice/session-2.scope
prog 12 konsole "$APP/app-org.kde.konsole-3.scope"
OUT="$(tick)"
check A1 '[ -z "$OUT" ] && ! grep -q "^gui" <<< "$(calls)" && [ "$(st "len(s.get(\"alarms\", {}))")" = 0 ]'
AD="$APP/app-flatpak-com.anydesk.Anydesk-5.scope"
prog 20 AnyDesk "$AD" "$WORK/progs/anydesk"
prog 21 anydesk-helper "$AD" "$WORK/progs/anydesk" "" 20
OUT="$(tick)"; ID="$(alarm_id)"
check A2 'grep -q "^ALARM${T}$ID${T}AnyDesk${T}paused$" <<< "$OUT" && frozen "$AD" && [ "$(astate "$ID")" = paused ] && [ "$(st "s[\"alarms\"][\"$ID\"][\"how\"]")" = app ]'
check A3 'grep -q "^gui --alarm $ID$" <<< "$(calls)" && grep -q "^notify-send .*--urgency=critical STOP - is someone on the phone with you? AnyDesk wants to let someone control this PC" <<< "$(calls)"'
check A4 'grep -q "${T}techsupport${T}techguard${T}.*AnyDesk (a remote-control app) was paused" "$EVENTS" && [ "$(st "s[\"alarms\"][\"$ID\"][\"flatpak\"]")" = com.anydesk.Anydesk ]'
: > "$WORK/calls.log"; OUT="$(tick)"
check A5 '[ -z "$OUT" ] && ! grep -q "^gui" <<< "$(calls)" && [ "$(st "len(s[\"alarms\"])")" = 1 ]'

# A6: a Windows program in Wine (Bottles); A7: started from a terminal -> only that program is paused (SIGSTOP)
fresh
BT="$APP/app-com.usebottles.bottles-9.scope"
prog 30 UltraViewer_Des "$BT" "$WORK/progs/wine64-preloader" 'C:\Program Files\UltraViewer\UltraViewer_Desktop.exe'
OUT="$(tick)"; ID="$(alarm_id)"
check A6 'grep -q "${T}UltraViewer${T}paused$" <<< "$OUT" && frozen "$BT" && [ "$(st "s[\"alarms\"][\"$ID\"][\"app\"]")" = ultraviewer ]'
fresh
sleep 30 & SP=$!
KO="$APP/app-org.kde.konsole-4.scope"
prog 40 konsole "$KO"
prog "$SP" teamviewer "$KO" "$WORK/progs/teamviewer" "" 40
OUT="$(tick)"; ID="$(alarm_id)"
S="$(ps -o stat= -p "$SP" 2>/dev/null)"
check A7 'grep -q "${T}TeamViewer${T}paused$" <<< "$OUT" && ! frozen "$KO" && [ "$(st "s[\"alarms\"][\"$ID\"][\"how\"]")" = program ] && [[ "$S" == T* ]]'
kill -9 "$SP" 2>/dev/null; wait "$SP" 2>/dev/null

# A8: someone else's program is never touched
fresh
prog 50 AnyDesk "$APP/app-x-1.scope"
sed -i "s/^Uid:.*/Uid:${T}4321${T}4321${T}4321${T}4321/" "$WORK/proc/50/status"
OUT="$(tick)"
check A8 '[ -z "$OUT" ] && ! frozen "$APP/app-x-1.scope"'

# B: the app is gone -> its alarm says so (and a new start is a new alarm)
fresh
prog 20 AnyDesk "$AD"
tick >/dev/null; ID="$(alarm_id)"
gone 20; tick >/dev/null
check B1 '[ "$(astate "$ID")" = gone ]'
prog 22 AnyDesk "$APP/app-flatpak-com.anydesk.Anydesk-6.scope"
OUT="$(tick)"
check B2 '[ "$(grep -c "^ALARM" <<< "$OUT")" = 1 ] && [ "$(st "len(s[\"alarms\"])")" = 2 ] && [ "$(astate "$(alarm_id 1)")" = paused ]'

# C: status lines, report, exit codes (1 = an app waits for you, 3 = the guard is off)
OUT="$(TG status)"; RC=$?
check C1 '[ "$RC" -eq 1 ] && grep -qx "SERVICE${T}on" <<< "$OUT" && grep -qx "MONEY${T}open" <<< "$OUT" && grep -qx "INTERNET${T}on" <<< "$OUT" && grep -qx "SHARING${T}-" <<< "$OUT" && grep -q "^ALARM${T}$(alarm_id 1)${T}paused${T}.*${T}AnyDesk${T}" <<< "$OUT"'
OUT="$(TG report)"; RC=$?
check C2 '[ "$RC" -eq 1 ] && grep -q "is ON: it pauses any remote-control app" <<< "$OUT" && grep -q "AnyDesk - paused, waiting for you" <<< "$OUT" && grep -q "NEVER call you" <<< "$OUT"'
fresh; touch "$WORK/service-off"
OUT="$(TG report)"; RC=$?
check C3 '[ "$RC" -eq 3 ] && grep -q "is OFF" <<< "$OUT" && grep -q "Test the guard" <<< "$OUT"'
rm -f "$WORK/service-off"
TG nonsense >/dev/null; A=$?; TG end 12 >/dev/null; B=$?; TG status extra >/dev/null; C=$?
check C4 '[ "$A" -eq 3 ] && [ "$B" -eq 3 ] && [ "$C" -eq 3 ]'

# C5: the remote-app list - good lines, the scammers' favorites found, everyday programs never
APPS="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from techguardlib import apps
a = apps.load(); print(len(a), len({x[0] for x in a}))
yes = ['AnyDesk.exe', 'com.anydesk.Anydesk', 'TeamViewer', 'UltraViewer_Desktop.exe', 'ScreenConnect.ClientService.exe',
       'com.rustdesk.RustDesk', 'LogMeIn', 'GoTo Resolve', 'quickassist.exe', 'Supremo.exe', 'AeroAdmin.exe', 'krfb']
no = ['firefox', 'brave', 'kwin_wayland', 'konsole', 'dolphin', 'steam', 'discord', 'zoom', 'plasmashell', 'systemd',
      'lateralus', 'teams', 'thunderbird', 'obs', 'pipewire', 'xdg-desktop-portal-kde', 'kdeconnectd']
print(all(apps.which([n]) for n in yes), any(apps.which([n]) for n in no))" "$FORGEOS_TG_LIB")"
check C5 '[ "$APPS" = "26 26
True False" ] && [ "$(grep -cvE "^(#|$)" "$FORGEOS_TG_SHARE/remote-apps.txt")" = 26 ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Fake Tech Support Guard tests A-C passed."; else echo "$failures Fake Tech Support Guard test(s) failed."; fi
exit "$((failures > 0))"
