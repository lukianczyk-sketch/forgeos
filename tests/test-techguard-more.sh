#!/usr/bin/env bash
# Tests for Fake Tech Support Guard (Job 17), cases D-F: "I set this up myself" (PC password, trusted from
# then on, only that exact program), Family Mode and the helper's Call for help, remote-app downloads.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-techguard-more.sh <repo-root>
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
TRUST="$WORK/var/trusted.json"

# D: I set this up myself -> root trusts it (fingerprint); the same program runs on later; a changed one doesn't
fresh
prog 20 AnyDesk "$AD" "$WORK/progs/anydesk"
tick >/dev/null; ID="$(alarm_id)"
OUT="$(TG allow "$ID")"; RC=$?
check D1 '[ "$RC" -eq 0 ] && grep -q "AnyDesk runs again and is trusted" <<< "$OUT" && ! frozen "$AD" && [ "$(astate "$ID")" = allowed ] && grep -q "\"sha256\": \"$(sha256sum "$WORK/progs/anydesk" | cut -d " " -f 1)\"" "$TRUST"'
gone 20; prog 23 AnyDesk "$APP/app-flatpak-com.anydesk.Anydesk-7.scope" "$WORK/progs/anydesk"
: > "$WORK/calls.log"; tick >/dev/null
check D2 '[ "$(astate "$(alarm_id 1)")" = allowed ] && ! frozen "$APP/app-flatpak-com.anydesk.Anydesk-7.scope" && ! grep -q "^gui" <<< "$(calls)"'
gone 23; echo "changed" >> "$WORK/progs/anydesk"; prog 24 AnyDesk "$APP/app-flatpak-com.anydesk.Anydesk-8.scope" "$WORK/progs/anydesk"
tick >/dev/null
check D3 '[ "$(astate "$(alarm_id 2)")" = paused ] && frozen "$APP/app-flatpak-com.anydesk.Anydesk-8.scope"'
# D4: Wine runs every Windows program: only that exact command line is trusted
fresh
W1="$APP/app-com.usebottles.bottles-1.scope"; W2="$APP/app-com.usebottles.bottles-2.scope"
prog 30 AnyDesk.exe "$W1" "$WORK/progs/wine64" 'C:\AnyDesk\AnyDesk.exe'
tick >/dev/null; TG allow "$(alarm_id)" >/dev/null
gone 30; prog 31 AnyDesk.exe "$W2" "$WORK/progs/wine64" 'D:\Downloads\AnyDesk.exe'
tick >/dev/null
check D4 '! frozen "$W1" && frozen "$W2" && grep -q "AnyDesk.exe --x" "$TRUST"'
# D5: no password -> it stays paused; D6: root only trusts the caller's own program
fresh
prog 20 AnyDesk "$AD"; tick >/dev/null; ID="$(alarm_id)"
touch "$WORK/pkexec-no"; OUT="$(TG allow "$ID")"; RC=$?; rm -f "$WORK/pkexec-no"
check D5 '[ "$RC" -eq 1 ] && grep -q "stays paused" <<< "$OUT" && frozen "$AD" && [ "$(astate "$ID")" = paused ] && [ ! -e "$TRUST" ]'
OUT="$(PK_UID=4321 TG allow "$ID")"; RC=$?
check D6 '[ "$RC" -eq 1 ] && frozen "$AD" && [ ! -e "$TRUST" ]'

# E: Family Mode closes any remote app (no "it's mine"); the helper's Call for help (RustDesk) runs on
fresh
prog 20 AnyDesk "$AD"; tick >/dev/null; ID="$(alarm_id)"
mkdir -p "$WORK/state/forgeos/family"; echo '{"on": true}' > "$WORK/state/forgeos/family/saved.json"
OUT="$(TG allow "$ID")"; RC=$?
check E1 '[ "$RC" -eq 3 ] && grep -q "Family Mode is on" <<< "$OUT" && frozen "$AD"'
prog 25 UltraViewer "$APP/app-uv-2.scope"
: > "$WORK/calls.log"; tick >/dev/null; ID2="$(alarm_id 1)"
check E2 '[ "$(astate "$ID2")" = ended-family ] && killed "$APP/app-uv-2.scope" && grep -q "^gui --alarm $ID2$" <<< "$(calls)" && grep -q "Family Mode closed UltraViewer" <<< "$(calls)"'
fresh
mkdir -p "$WORK/config/forgeos"; printf 'name=Brianna\nphone=6615550123\n' > "$WORK/config/forgeos/family.conf"
touch "$WORK/call-on"
RD="$APP/app-flatpak-com.rustdesk.RustDesk-3.scope"
prog 40 rustdesk "$RD"; : > "$WORK/calls.log"; tick >/dev/null
check E3 '[ "$(astate "$(alarm_id)")" = helper ] && ! frozen "$RD" && ! grep -q "^gui" <<< "$(calls)"'
prog 20 AnyDesk "$AD"; tick >/dev/null; ID="$(alarm_id 1)"
OUT="$(TG status)"
check E4 'grep -qx "HELPERCALL${T}Brianna" <<< "$OUT" && frozen "$AD"'
OUT="$(TG helper "$ID")"; RC=$?
check E5 '[ "$RC" -eq 0 ] && grep -q "AnyDesk runs again for Brianna" <<< "$OUT" && ! frozen "$AD" && [ "$(astate "$ID")" = helper ]'
rm -f "$WORK/call-on"; gone 40; gone 20
prog 41 rustdesk "$APP/app-flatpak-com.rustdesk.RustDesk-4.scope"; tick >/dev/null; ID="$(alarm_id 2)"
OUT="$(TG helper "$ID")"; RC=$?
check E6 '[ "$(astate "$ID")" = paused ] && [ "$RC" -eq 3 ] && grep -q "Call for help is not running" <<< "$OUT"'

# F: downloads - files there before are left alone; a new remote app file -> warning; Lock it away
fresh
D="$H/Downloads"
rm -f "$D"/*; touch "$D/AnyDesk old.exe" "$D/letter.pdf"
: > "$WORK/calls.log"; tick >/dev/null
check F1 '! grep -q "^gui --download" <<< "$(calls)"'
touch "$D/TeamViewer_Setup_x64.exe.crdownload"; tick >/dev/null
check F2 '! grep -q "^gui --download" <<< "$(calls)"'
mv "$D/TeamViewer_Setup_x64.exe.crdownload" "$D/TeamViewer_Setup_x64.exe"; tick >/dev/null; tick >/dev/null
check F3 '[ "$(grep -c "^gui --download $D/TeamViewer_Setup_x64.exe$" <<< "$(calls)")" = 1 ] && grep -q "TeamViewer (a remote-control app) was downloaded" "$WORK/state/forgeos/guard/events.log"'
OUT="$(TG lock-file "$D/TeamViewer_Setup_x64.exe")"; RC=$?
check F4 '[ "$RC" -eq 0 ] && [ ! -e "$D/TeamViewer_Setup_x64.exe" ] && [ -n "$(find "$WORK/data/forgeos/guard/quarantine" -name TeamViewer_Setup_x64.exe)" ]'
touch "$H/Documents/AnyDesk.exe"
TG lock-file "$D/letter.pdf" >/dev/null; A=$?; TG lock-file "$H/Documents/AnyDesk.exe" >/dev/null; B=$?
check F5 '[ "$A" -eq 3 ] && [ "$B" -eq 3 ] && [ -e "$D/letter.pdf" ] && [ -e "$H/Documents/AnyDesk.exe" ]'
tick >/dev/null  # seen gone: the same file downloaded again is warned about again
touch "$D/TeamViewer_Setup_x64.exe"; : > "$WORK/calls.log"; tick >/dev/null
check F6 'grep -q "^gui --download $D/TeamViewer_Setup_x64.exe$" <<< "$(calls)"'

echo
if [ "$failures" -eq 0 ]; then echo "All Fake Tech Support Guard tests D-F passed."; else echo "$failures Fake Tech Support Guard test(s) failed."; fi
exit "$((failures > 0))"
