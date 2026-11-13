#!/usr/bin/env bash
# Tests for Ask Before Connecting (Job 24), case H: tricks a bad program could try (the system loader, a /usr
# helper, a fake app id, a copy of /usr/bin/x, fake Steam, a swapped file, another setup.exe, a borrowed name,
# allowing a remote-control app from the window), and your Block beating ForgeOS's own apps.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-netask-safety.sh <repo-root>
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
mkdir -p "$H/Downloads" "$H/bin" "$H/.steam/x/ubuntu12_32"
real /usr/bin/wine64-preloader /usr/lib64/ld-linux-x86-64.so.2 /usr/bin/python3 /usr/lib64/python3.14/cProfile.py /usr/bin/kdeconnectd
asked() { calls | grep -c "^kdialog.*--\(yesnocancel\|warningyesnocancel\|warningyesno\)"; }

# H1: the system loader running a Downloads file is NOT a ForgeOS program: red question
fresh; proc 401 -- /usr/lib64/ld-linux-x86-64.so.2 "$H/Downloads/evil"; echo 1 > "$WORK/say/codes"
A="$(answer "$(conn 401 /usr/lib64/ld-linux-x86-64.so.2 $MD5 example.com '"args": ["/usr/lib64/ld-linux-x86-64.so.2", "'"$H"'/Downloads/evil"]')")"
check H1 '[ "$A" = "allow once forgeos-netask-once" ] && calls | grep -q -- "--warningyesnocancel Careful: a program in your Downloads folder"'
# H2: a /usr python script told to run a Downloads file is not trusted either (only ForgeOS's own scripts are)
fresh; proc 402 -- /usr/bin/python3 /usr/lib64/python3.14/cProfile.py "$H/Downloads/evil.py"; echo 0 > "$WORK/say/codes"
A="$(answer "$(conn 402 /usr/bin/python3 $MD5 example.com '"args": ["/usr/bin/python3", "/usr/lib64/python3.14/cProfile.py", "'"$H"'/Downloads/evil.py"]')")"
check H2 '[ "$A" = "deny once forgeos-netask-once" ] && [ "$(asked)" = 1 ]'
# H3: a fake Flatpak app id (its file is not inside the installed app) and a copy that only looks like /usr/bin/x
fresh; proc 403 flatpak:com.brave.Browser exe:"$H/Downloads/evil" -- /app/brave/brave; echo 1 > "$WORK/say/codes"
A="$(answer "$(conn 403 /app/brave/brave $MD5)")"
proc 404 exe:"$H/bin/evil" -- /usr/bin/kdeconnectd; echo 1 > "$WORK/say/codes"
B="$(answer "$(conn 404 /usr/bin/kdeconnectd 22222222222222222222222222222222)")"
check H3 '[ "${A% *}" = "deny always" ] && [ "${B% *}" = "deny always" ] && [ "$(asked)" = 2 ] && [ -z "$(store flatpak:com.brave.Browser kind)" ]'
# H4: your Block beats ForgeOS's own apps; the allow rule file is deleted and a block rule written (OpenSnitch sees it)
fresh; app com.brave.Browser Brave brave; proc 405 flatpak:com.brave.Browser "$(flatpak_app com.brave.Browser brave/brave)" -- /app/brave/brave
answer "$(conn 405 /app/brave/brave $MD5)" > /dev/null; R1="$(ls "$WORK/rules")"
OUT="$(NA block Brave)"; R2="$(ls "$WORK/rules")"; A="$(answer "$(conn 405 /app/brave/brave $MD5)")"
check H4 'grep -q "u$ME-allow-brave-" <<< "$R1" && grep -q "u$ME-block-brave-" <<< "$R2" && ! grep -q "u$ME-allow-brave-" <<< "$R2" && [ "${A% *}" = "deny always" ] && [ "$(store flatpak:com.brave.Browser answer)" = block ] && [ ! -L "$WORK/rules/$(grep block-brave <<< "$R2")" ]'
# H5: a program whose file was swapped while you played does not keep its old Allow
fresh; proc 406 -- "$H/Apps/Tool"; mkdir -p "$H/Apps"; echo 0 > "$WORK/say/codes"; answer "$(conn 406 "$H/Apps/Tool" $MD5)" > /dev/null
touch "$WORK/gaming"; A="$(answer "$(conn 406 "$H/Apps/Tool" 33333333333333333333333333333333)")"; rm -f "$WORK/gaming"
echo none > "$WORK/say/check"; echo 1 > "$WORK/say/codes"; B="$(answer "$(conn 406 "$H/Apps/Tool" 33333333333333333333333333333333)")"
check H5 '[ "$A" = "deny once forgeos-netask-once" ] && [ "${B% *}" = "deny always" ] && calls | grep -q -- "--yesnocancel Tool wants"'
# H6: a fake Steam in a folder you can write to is not Steam
fresh; proc 407 -- "$H/.steam/x/ubuntu12_32/steam"; echo 1 > "$WORK/say/codes"
A="$(answer "$(conn 407 "$H/.steam/x/ubuntu12_32/steam" $MD5)")"
check H6 '[ "${A% *}" = "deny always" ] && [ "$(asked)" = 1 ]'
# H7: Windows programs are known by their whole place: another setup.exe is asked again; Z:\...\Downloads = red
fresh; proc 408 -- /usr/bin/wine64-preloader 'C:\Games\A\setup.exe'; echo 0 > "$WORK/say/codes"
answer "$(conn 408 /usr/bin/wine64-preloader $MD5 example.com '"args": ["wine64-preloader", "C:\\Games\\A\\setup.exe"]')" > /dev/null
proc 409 -- /usr/bin/wine64-preloader 'Z:\x\Downloads\setup.exe'; echo 1 > "$WORK/say/codes"
A="$(answer "$(conn 409 /usr/bin/wine64-preloader $MD5 example.com '"args": ["wine64-preloader", "Z:'"${H//\//\\\\}"'\\Downloads\\setup.exe"]')")"
check H7 '[ "$A" = "allow once forgeos-netask-once" ] && [ "$(asked)" = 2 ] && calls | grep -q -- "--warningyesnocancel Careful: a program in your Downloads folder"'
# H8: a program outside /usr never borrows an app's menu name; the question shows where its file is
fresh; app steam Steam steam; proc 410 -- "$H/bin/steam"; echo 1 > "$WORK/say/codes"
answer "$(conn 410 "$H/bin/steam" $MD5)" > /dev/null
check H8 'calls | grep -q -- "--yesnocancel steam wants to use the internet" && calls | grep -qx "From: ~/bin/steam"'
# H9: a remote-control app can't be allowed from the window (it gets the Fake Tech Support Guard question)
fresh; mkdir -p "$H/anydesk"; proc 411 -- "$H/anydesk/AnyDesk"; echo 0 > "$WORK/say/codes"; answer "$(conn 411 "$H/anydesk/AnyDesk" $MD5)" > /dev/null
OUT="$(NA allow AnyDesk)"; C1=$?
check H9 '[ "$C1" = 1 ] && grep -q "is a remote-control app, so it can.t be allowed for good from here. Nothing changed." <<< "$OUT" && ! calls | grep -q -- "--yesno Allow AnyDesk"'

echo
if [ "$failures" -eq 0 ]; then echo "All Ask Before Connecting tests H passed."; else echo "$failures test(s) failed."; cat "$WORK/service.log"; fi
exit "$((failures > 0))"
