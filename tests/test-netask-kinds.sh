#!/usr/bin/env bash
# Tests for Ask Before Connecting (Job 24), case B: scam sites, remote-control apps, scripts,
# Windows programs (also in Bottles), Steam games, programs that already ended.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-netask-kinds.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'stop_service; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/netask-fakes.sh
. "$ROOT/tests/netask-fakes.sh" || exit 1
start_service || exit 1
MD5=0123456789abcdef0123456789abcdef
real /usr/bin/kdeconnectd /usr/bin/wine64-preloader; proc 101 -- /usr/bin/kdeconnectd; app kdeconnect "KDE Connect" /usr/bin/kdeconnectd
mkdir -p "$H/Apps"; proc 102 -- "$H/Apps/Tool.AppImage"; echo 0 > "$WORK/say/codes"
answer "$(conn 102 "$H/Apps/Tool.AppImage" $MD5)" > /dev/null

# B1: a known scam site = blocked, no question, one note (at most one per program every 10 minutes)
fresh; printf '127.0.0.1 localhost\n# >>> ForgeOS Always-On Guard: scam and virus websites blocked (made by forgeos-guard-hosts, do not edit) >>>\n0.0.0.0 evil-login.example\n# <<< ForgeOS Always-On Guard <<<\n' > "$WORK/hosts"
A="$(answer "$(conn 101 /usr/bin/kdeconnectd $MD5 cdn.evil-login.example)")"; sleep 1
B="$(answer "$(conn 101 /usr/bin/kdeconnectd $MD5 evil-login.example)")"; sleep 1
check B1 '[ "$A" = "deny once forgeos-netask-once" ] && [ "$B" = "deny once forgeos-netask-once" ] && [ "$(calls | grep -c -- "--passivepopup ForgeOS stopped KDE Connect from reaching a known scam website.")" = 1 ] && NA blocked 60 | grep -q "KDE Connect${T}cdn.evil-login.example${T}scam$"'
# B2: remote-control apps get the Fake Tech Support Guard question; RustDesk is the helper's app in Family Mode
fresh; mkdir -p "$H/anydesk"; proc 112 -- "$H/anydesk/AnyDesk"; echo 0 > "$WORK/say/codes"
A="$(answer "$(conn 112 "$H/anydesk/AnyDesk" $MD5)")"; Q="$(calls)"
proc 113 flatpak:com.rustdesk.RustDesk "$(flatpak_app com.rustdesk.RustDesk bin/rustdesk)" -- /app/bin/rustdesk; echo 1 > "$WORK/say/codes"
B="$(answer "$(conn 113 /app/bin/rustdesk $MD5)")"
mkdir -p "$H/.local/state/forgeos/family"; echo '{"on": true}' > "$H/.local/state/forgeos/family/saved.json"
proc 114 flatpak:com.rustdesk.RustDesk "$(flatpak_app com.rustdesk.RustDesk bin/rustdesk)" -- /app/bin/rustdesk; N1="$(calls | grep -c "^kdialog")"
C="$(answer "$(conn 114 /app/bin/rustdesk 11111111111111111111111111111111)")"
check B2 '[ "${A% *}" = "deny always" ] && grep -q -- "--warningyesno AnyDesk wants to use the internet. It is a remote-control app (AnyDesk)" <<< "$Q" && grep -q "Is someone you don.t know asking you" <<< "$Q" && [ "${B% *}" = "allow always" ] && [ "${C% *}" = "allow always" ] && [ "$(calls | grep -c "^kdialog")" = "$N1" ]'
# B3: scripts are known by the script, not by "python3": ForgeOS's own = yes (once), Downloads = red,
#      started with PYTHONPATH = not trusted, typed commands = "python (typed commands)"
fresh; real /usr/bin/python3.14 /usr/bin/python3; proc 115 -- /usr/bin/python3.14 /usr/bin/forgeos-example --x
A="$(answer "$(conn 115 /usr/bin/python3.14 "" example.com '"args": ["/usr/bin/python3.14", "/usr/bin/forgeos-example", "--x"]')")"
proc 116 -- /usr/bin/python3 evil.py; echo 0 > "$WORK/say/codes"
B="$(answer "$(conn 116 /usr/bin/python3 $MD5 example.com '"args": ["python3", "evil.py"], "cwd": "'"$H"'/Downloads"')")"
proc 117 env:PYTHONPATH -- /usr/bin/python3 /usr/bin/forgeos-example; echo 1 > "$WORK/say/codes"
C="$(answer "$(conn 117 /usr/bin/python3 $MD5 example.com '"args": ["/usr/bin/python3", "/usr/bin/forgeos-example"]')")"
proc 118 -- /usr/bin/python3 -c "print(1)"; echo 1 > "$WORK/say/codes"
D="$(answer "$(conn 118 /usr/bin/python3 $MD5 example.com '"args": ["/usr/bin/python3", "-c", "x"]')")"
check B3 '[ "$A" = "allow once forgeos-netask-once" ] && [ "$B" = "deny once forgeos-netask-once" ] && calls | grep -q -- "--warningyesnocancel Careful: a program in your Downloads folder wants the internet.${NL:-}" && calls | grep -q "evil.py (to reach" && [ "$C" = "deny once forgeos-netask-once" ] && [ "$(store script:/usr/bin/forgeos-example answer)" = block ] && [ "$D" = "deny once forgeos-netask-once" ] && [ "$(store cmd:python3 name)" = "python (typed commands)" ]'
# B4: a Windows program (also inside Bottles) is known by its .exe and asked once
fresh; proc 119 flatpak:com.usebottles.bottles -- /usr/bin/wine64-preloader 'C:\Program Files\Setup\setup.exe'; echo 0 > "$WORK/say/codes"
A="$(answer "$(conn 119 /usr/bin/wine64-preloader $MD5 example.com '"args": ["/usr/bin/wine64-preloader", "C:\\\\Program Files\\\\Setup\\\\setup.exe"]')")"
B="$(answer "$(conn 119 /usr/bin/wine64-preloader $MD5 example.com '"args": ["/usr/bin/wine64-preloader", "C:\\\\Program Files\\\\Setup\\\\setup.exe"]')")"
check B4 '[ "$A" = "allow once forgeos-netask-once" ] && [ "$B" = "allow once forgeos-netask-once" ] && calls | grep -q -- "--yesnocancel setup.exe wants to use the internet" && [ "$(calls | grep -c "^kdialog")" = 1 ] && [ "$(store "exe:|c:/program files/setup/setup.exe" answer)" = allow ]'
# B5: Steam and its games: never asked
fresh; S="$H/.local/share/Steam"; proc 120 -- "$S/steamapps/common/Game/game"
A="$(answer "$(conn 120 "$S/steamapps/common/Game/game" $MD5 example.com '"tree": [["'"$S"'/ubuntu12_32/steam", 50]]')")"
check B5 '[ "${A% *}" = "allow always" ] && ! calls | grep -q kdialog && [ "$(store "steam:$S/steamapps/common/Game/game" name)" = "A Steam game" ]'
# B6: the program already ended = no
fresh; A="$(answer "$(conn 999 "$H/Apps/Gone" $MD5)")"
check B6 '[ "$A" = "deny once forgeos-netask-once" ] && ! calls | grep -q kdialog'

echo
if [ "$failures" -eq 0 ]; then echo "All Ask Before Connecting tests B passed."; else echo "$failures test(s) failed."; cat "$WORK/service.log"; fi
exit "$((failures > 0))"
