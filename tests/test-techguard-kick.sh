#!/usr/bin/env bash
# Tests for Fake Tech Support Guard (Job 17), cases I-J: Kick them out (every remote app - paused, trusted or
# the helper's - and every screen sharing ends, the internet is cut, browsers close), the internet back on,
# and the checklist of what a stranger may have left behind.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-techguard-kick.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/techguard-fakes.sh
. "$ROOT/tests/techguard-fakes.sh"
AD="$APP/app-flatpak-com.anydesk.Anydesk-5.scope"
TV="$APP/app-teamviewer-2.scope"
RD="$APP/app-flatpak-com.rustdesk.RustDesk-3.scope"
BR="$APP/app-flatpak-com.brave.Browser-4.scope"
ZM="$APP/app-us.zoom.Zoom-6.scope"

# I: everyone out - a paused AnyDesk, a trusted TeamViewer, the helper's RustDesk, a Zoom showing the screen,
# the Brave browser; the internet is cut; nothing else is touched
fresh
mkdir -p "$WORK/config/forgeos"; echo "name=Brianna" > "$WORK/config/forgeos/family.conf"; touch "$WORK/call-on"
prog 20 AnyDesk "$AD"; prog 30 rustdesk "$RD"
tick >/dev/null; A1="$(alarm_id)"
prog 40 TeamViewer "$TV" "$WORK/progs/teamviewer"; tick >/dev/null; A3="$(alarm_id 2)"
TG allow "$A3" >/dev/null
prog 50 zoom "$ZM"; prog 60 brave "$BR"; prog 70 dolphin "$APP/app-org.kde.dolphin-8.scope"
share us.zoom.Zoom "Zoom Meeting" 50
: > "$WORK/calls.log"
OUT="$(TG kick)"; RC=$?
check I1 '[ "$RC" -eq 0 ] && killed "$AD" && killed "$TV" && killed "$RD" && killed "$ZM" && killed "$BR" && ! killed "$APP/app-org.kde.dolphin-8.scope"'
check I2 'grep -qx "KICKED${T}AnyDesk" <<< "$OUT" && grep -qx "KICKED${T}TeamViewer" <<< "$OUT" && grep -qx "KICKED${T}RustDesk" <<< "$OUT" && grep -qx "SCREEN${T}Zoom Meeting" <<< "$OUT" && grep -qx "INTERNET${T}cut" <<< "$OUT" && grep -qx "BROWSERS${T}1" <<< "$OUT"'
check I3 'grep -qx "forgeos-family call-end" <<< "$(calls)" && [ "$(cat "$WORK/net-state")" = off ] && [ "$(astate "$A1")" = kicked ] && [ "$(astate "$A3")" = kicked ]'
OUT="$(TG status)"; RC=$?
check I4 '[ "$RC" -eq 1 ] && grep -qx "INTERNET${T}cut" <<< "$OUT"'
OUT="$(TG net-on)"; RC=$?
check I5 '[ "$RC" -eq 0 ] && [ "$(cat "$WORK/net-state")" = on ] && grep -qx "INTERNET${T}on" <<< "$(TG status)"'
# I6: the internet can't be cut -> said so (exit 1); I7: escape closes only the browsers
fresh; touch "$WORK/nmcli-fails"; prog 20 AnyDesk "$AD"
OUT="$(TG kick)"; RC=$?; rm -f "$WORK/nmcli-fails"
check I6 '[ "$RC" -eq 1 ] && grep -qx "INTERNET${T}failed" <<< "$OUT" && killed "$AD"'
fresh; prog 60 brave "$BR"; prog 61 firefox "$APP/app-org.mozilla.firefox-9.scope" "$WORK/progs/firefox"; prog 62 AnyDesk "$AD"
OUT="$(TG escape)"
check I7 '[ "$OUT" = "BROWSERS${T}2" ] && killed "$BR" && killed "$APP/app-org.mozilla.firefox-9.scope" && ! killed "$AD" && [ ! -e "$WORK/net-state" ]'

# I8: an app that could not be paused (shown as such) is not reported again every 2 s; Kick ends it
fresh; prog 3999990 AnyDesk "$AD"; rm -f "$WORK/cg$AD/cgroup.freeze"; mkdir "$WORK/cg$AD/cgroup.freeze"  # no such program: SIGSTOP fails
tick >/dev/null; tick >/dev/null; ID="$(alarm_id)"
check I8 '[ "$(astate "$ID")" = running ] && [ "$(st "len(s[\"alarms\"])")" = 1 ] && [ "$(grep -c "^gui --alarm" <<< "$(calls)")" = 1 ] && TG kick >/dev/null && killed "$AD"'

# J: what they may have left behind - remote apps installed, remote app files, NEW autostart / background /
# program entries (old ones not listed); remove one; only items on the list can be removed
fresh
printf 'org.mozilla.firefox\ncom.anydesk.Anydesk\n' > "$WORK/flatpaks"
touch "$H/Downloads/UltraViewer_setup.exe" "$H/anydesk-7.1.0-amd64.tar.gz" "$H/Downloads/photo.jpg"
mkdir -p "$WORK/config/autostart" "$WORK/config/systemd/user" "$WORK/data/applications"
touch "$WORK/config/autostart/support-agent.desktop" "$WORK/config/systemd/user/helper.service" "$WORK/data/applications/remote.desktop"
touch -d "3 days ago" "$WORK/config/autostart/old-thing.desktop"
OUT="$(TG checklist)"
check J1 'grep -qx "ITEM${T}flatpak${T}com.anydesk.Anydesk${T}Remote-control app: com.anydesk.Anydesk" <<< "$OUT" && grep -q "^ITEM${T}file${T}$H/Downloads/UltraViewer_setup.exe${T}Remote-control app file (UltraViewer)" <<< "$OUT" && grep -q "^ITEM${T}file${T}$H/anydesk-7.1.0-amd64.tar.gz${T}Remote-control app file (AnyDesk)" <<< "$OUT"'
check J2 'grep -q "starts by itself when you log in: support-agent.desktop" <<< "$OUT" && grep -q "runs by itself in the background: helper.service" <<< "$OUT" && grep -q "New program in the last day: remote.desktop" <<< "$OUT" && ! grep -q "old-thing\|photo.jpg\|firefox" <<< "$OUT" && [ "$(wc -l <<< "$OUT")" = 6 ]'
OUT="$(TG remove file "$WORK/config/autostart/support-agent.desktop")"; RC=$?
check J3 '[ "$RC" -eq 0 ] && [ ! -e "$WORK/config/autostart/support-agent.desktop" ] && [ -n "$(find "$WORK/data/forgeos/guard/quarantine" -name support-agent.desktop)" ]'
touch "$WORK/flatpak-user-fails"; : > "$WORK/calls.log"
OUT="$(TG remove flatpak com.anydesk.Anydesk)"; RC=$?
check J4 '[ "$RC" -eq 0 ] && grep -qx "flatpak uninstall --system -y --noninteractive com.anydesk.Anydesk" <<< "$(calls)"'
TG remove file "$H/Downloads/photo.jpg" >/dev/null; A=$?; TG remove flatpak org.mozilla.firefox >/dev/null; B=$?
TG remove file "$WORK/config/autostart/old-thing.desktop" >/dev/null; C=$?
check J5 '[ "$A" -eq 1 ] && [ "$B" -eq 1 ] && [ "$C" -eq 1 ] && [ -e "$H/Downloads/photo.jpg" ] && [ -e "$WORK/config/autostart/old-thing.desktop" ] && ! grep -q "uninstall.*firefox" <<< "$(calls)"'

echo
if [ "$failures" -eq 0 ]; then echo "All Fake Tech Support Guard tests I-J passed."; else echo "$failures Fake Tech Support Guard test(s) failed."; fi
exit "$((failures > 0))"
