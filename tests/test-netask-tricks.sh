#!/usr/bin/env bash
# Tests for Ask Before Connecting (Job 24), case I: more tricks (fake wine, commands inside a trusted app,
# a fake app in your home), ForgeOS's script apps, undoing a Block, symlinked Steam, the after-game list.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-netask-tricks.sh <repo-root>
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
mkdir -p "$H/Downloads" "$H/Apps"
real /usr/bin/wine64-preloader; app com.brave.Browser Brave brave
asked() { calls | grep -c "^kdialog.*--\(yesnocancel\|warningyesnocancel\|warningyesno\)"; }
BR="$(flatpak_app com.brave.Browser brave/brave)"
RT="$WORK/root/var/lib/flatpak/runtime/org.kde.Platform/x86_64/6.9/active/files"; mkdir -p "$RT/bin"; : > "$RT/bin/bash"; : > "$RT/bin/python3.12"

# I1: a fake "wine" in Downloads does not borrow an allowed Windows program's answer (and is red)
fresh; proc 501 -- /usr/bin/wine64-preloader 'C:\Games\A\good.exe'; echo 0 > "$WORK/say/codes"
answer "$(conn 501 /usr/bin/wine64-preloader $MD5 example.com '"args": ["wine64-preloader", "C:\\Games\\A\\good.exe"]')" > /dev/null
proc 502 -- "$H/Downloads/wine64-preloader" 'C:\Games\A\good.exe'; echo 1 > "$WORK/say/codes"
A="$(answer "$(conn 502 "$H/Downloads/wine64-preloader" $MD5 example.com '"args": ["wine64-preloader", "C:\\Games\\A\\good.exe"]')")"
check I1 '[ "$(asked)" = 2 ] && [ "$A" = "allow once forgeos-netask-once" ] && calls | grep -q -- "--warningyesnocancel Careful: a program in your Downloads folder"'
# I2: Brave is trusted, but a shell run inside Brave's sandbox, or Brave started with LD_PRELOAD, is asked about
fresh; proc 503 flatpak:com.brave.Browser "$BR" -- /app/brave/brave; A="$(answer "$(conn 503 /app/brave/brave $MD5)")"
proc 504 flatpak:com.brave.Browser exe:"$RT/bin/bash" -- /usr/bin/bash -c x; echo 1 > "$WORK/say/codes"
B="$(answer "$(conn 504 /usr/bin/bash $MD5 example.com '"args": ["/usr/bin/bash", "-c", "x"]')")"
proc 505 flatpak:com.brave.Browser env:LD_PRELOAD "$BR" -- /app/brave/brave; echo 1 > "$WORK/say/codes"
C="$(answer "$(conn 505 /app/brave/brave $MD5)")"
check I2 '[ "${A% *}" = "allow always" ] && [ "$B" = "deny once forgeos-netask-once" ] && [ "$C" = "deny once forgeos-netask-once" ] && [ "$(asked)" = 2 ] && calls | grep -q "bash (a command inside Brave) wants" && calls | grep -q "Brave (started in an unusual way) wants"'
# I3: a fake app in your home pretending to be Brave never gets Brave's answer or name
fresh; U="$H/.local/share/flatpak/app/com.brave.Browser/current/active/files"; mkdir -p "$U"; : > "$U/evil"
proc 506 flatpak:com.brave.Browser exe:"$U/evil" -- /app/evil; echo 1 > "$WORK/say/codes"
A="$(answer "$(conn 506 /app/evil $MD5)")"
check I3 '[ "${A% *}" = "deny always" ] && [ "$(asked)" = 1 ] && [ "$(store flatpak-user:com.brave.Browser answer)" = block ] && [ "$(store flatpak:com.brave.Browser answer)" = allow ]'
# I4: ForgeOS's script apps (Bottles runs the runtime's python on its own /app script) are trusted too
fresh; real /var/lib/flatpak/app/com.usebottles.bottles/current/active/files/bin/bottles
proc 507 flatpak:com.usebottles.bottles exe:"$RT/bin/python3.12" -- /usr/bin/python3.12 /app/bin/bottles
A="$(answer "$(conn 507 /usr/bin/python3.12 $MD5 example.com '"args": ["/usr/bin/python3.12", "/app/bin/bottles"]')")"
check I4 '[ "$A" = "allow once forgeos-netask-once" ] && [ "$(asked)" = 0 ] && [ "$(store flatpak:com.usebottles.bottles answer)" = allow ]'
# I5: undoing a Block asks first (No = still blocked); "allow" on a red program changes nothing
fresh; proc 508 -- "$H/Apps/Bad"; echo 1 > "$WORK/say/codes"; answer "$(conn 508 "$H/Apps/Bad" $MD5)" > /dev/null
echo 1 > "$WORK/say/codes"; OUT="$(NA ask Bad)"; C1=$?; S1="$(store "path:$H/Apps/Bad" answer)"
echo 0 > "$WORK/say/codes"; NA ask Bad > /dev/null; S2="$(store "path:$H/Apps/Bad" answer)"
check I5 '[ "$C1" = 1 ] && [ "$OUT" = "Nothing changed. Bad stays blocked." ] && [ "$S1" = block ] && [ "$S2" = ask ] && calls | grep -q -- "--yesno Let Bad ask for the internet again?"'
# I6: a Steam folder that is a symlink (to Downloads, say) is not trusted
fresh; mkdir -p "$H/Downloads/fake/ubuntu12_32" "$H/.local/share"; ln -s "$H/Downloads/fake" "$H/.local/share/Steam"
proc 509 -- "$H/Downloads/fake/ubuntu12_32/steam"; echo 0 > "$WORK/say/codes"
A="$(answer "$(conn 509 "$H/Downloads/fake/ubuntu12_32/steam" $MD5)")"
check I6 '[ "${A% *}" = "deny always" ] && [ "$(asked)" = 1 ]'
# I7: an answer given while the after-game list is open is not overwritten when the list closes
fresh; touch "$WORK/gaming"; proc 510 -- "$H/Apps/Late"; answer "$(conn 510 "$H/Apps/Late" $MD5)" > /dev/null
python3 - "$WORK/var/apps-$ME.json" "path:$H/Apps/Late" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d[sys.argv[2]]["later"] = False; d[sys.argv[2]]["answer"] = "block"; json.dump(d, open(sys.argv[1], "w"))
PY
rm -f "$WORK/gaming"; sleep 2.5
check I7 '[ "$(store "path:$H/Apps/Late" answer)" = block ] && ! calls | grep -q -- "--checklist"'
# I8: a known app whose file changed (new fingerprint) is asked again
fresh; proc 102 -- "$H/Apps/Tool.AppImage"; echo 0 > "$WORK/say/codes"; answer "$(conn 102 "$H/Apps/Tool.AppImage" $MD5)" > /dev/null
fresh; echo 0 > "$WORK/say/codes"
A="$(answer "$(conn 102 "$H/Apps/Tool.AppImage" ffffffffffffffffffffffffffffffff)")"
check I8 '[ "${A% *}" = "allow always" ] && [ "$(calls | grep -c "^kdialog")" = 1 ] && [ "$(store "path:$H/Apps/Tool.AppImage" md5)" = ffffffffffffffffffffffffffffffff ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Ask Before Connecting tests I passed."; else echo "$failures test(s) failed."; cat "$WORK/service.log"; fi
exit "$((failures > 0))"
