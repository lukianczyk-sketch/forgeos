#!/usr/bin/env bash
# Tests for Ask Before Connecting (Job 24), case A: what the service answers OpenSnitch for each kind of program.
# A pretend OpenSnitch daemon asks over the real UI protocol; the real question script runs with a pretend kdialog.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-netask.sh <repo-root>
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

# A1: the protocol: Subscribe gives the daemon's config back, the Notifications stream stays open
check A1 '[ "$(daemon subscribe)" = "ForgeOS Ask Before Connecting 7 {\"DefaultAction\": \"deny\"}" ] && [ "$(daemon notify)" = open ]'
# A2: a program that came with ForgeOS (/usr) is allowed with no question, kept as a rule on path + MD5 + person
fresh; real /usr/bin/kdeconnectd; proc 101 -- /usr/bin/kdeconnectd; app kdeconnect "KDE Connect" /usr/bin/kdeconnectd
OUT="$(ask "$(conn 101 /usr/bin/kdeconnectd $MD5)")"
check A2 'grep -qE "^allow always 500-forgeos-netask-u$ME-allow-kde-connect-[0-9a-f]{8}$" <<< "$OUT" && grep -q "\"operand\": \"process.path\", \"data\": \"/usr/bin/kdeconnectd\"" <<< "$OUT" && grep -q "\"operand\": \"process.hash.md5\", \"data\": \"$MD5\"" <<< "$OUT" && grep -q "\"operand\": \"user.id\", \"data\": \"$ME\"" <<< "$OUT" && ! calls | grep -q kdialog && [ "$(store path:/usr/bin/kdeconnectd kind)" = system ]'
# A3: a new app -> the question; Allow = allowed for good, asked only once
fresh; mkdir -p "$H/Apps"; proc 102 -- "$H/Apps/Tool.AppImage"; echo 0 > "$WORK/say/codes"
A="$(answer "$(conn 102 "$H/Apps/Tool.AppImage" $MD5 updates.tool.org)")"
Q="$(calls)"
B="$(answer "$(conn 102 "$H/Apps/Tool.AppImage" $MD5)")"
check A3 '[ "${A% *}" = "allow always" ] && grep -q -- "--yesnocancel Tool.AppImage wants to use the internet" <<< "$Q" && grep -q "(to reach updates.tool.org)" <<< "$Q" && grep -q -- "--yes-label Allow --no-label Block --cancel-label Other choices" <<< "$Q" && [ "${B% *}" = "allow always" ] && [ "$(calls | grep -c "^kdialog")" = 1 ] && [ "$(store "path:$H/Apps/Tool.AppImage" answer)" = allow ]'
# A4: Block = blocked for good; Just this once (Other choices) = allowed once, still asks next time
fresh; proc 103 -- "$H/Apps/Other"; echo 1 > "$WORK/say/codes"
A="$(answer "$(conn 103 "$H/Apps/Other" $MD5)")"
proc 104 -- "$H/Apps/Third"; printf '2\n0\n' > "$WORK/say/codes"; echo once > "$WORK/say/pick"
B="$(answer "$(conn 104 "$H/Apps/Third" $MD5)")"
check A4 '[ "${A% *}" = "deny always" ] && [ "$(store "path:$H/Apps/Other" answer)" = block ] && [ "$B" = "allow once forgeos-netask-once" ] && [ "$(store "path:$H/Apps/Third" answer)" = ask ] && calls | grep -q -- "--menu Third wants to use the internet. once Just this once what What is this"'
# A5: no answer (or the window closed) = blocked for now, written down, asked again next time
fresh; proc 105 -- "$H/Apps/Quiet"; echo 124 > "$WORK/say/codes"
A="$(answer "$(conn 105 "$H/Apps/Quiet" $MD5 quiet.example)")"
check A5 '[ "$A" = "deny once forgeos-netask-once" ] && [ "$(store "path:$H/Apps/Quiet" answer)" = ask ] && NA blocked 60 | grep -q "^BLOCKED${T}path:$H/Apps/Quiet${T}[0-9]*${T}Quiet${T}quiet.example${T}no answer$"'
# A6: Downloads / temp / hidden folder = red question every time; "Allow just this once" is never kept
fresh; mkdir -p "$H/Downloads" "$H/.cache/x"; proc 106 -- "$H/Downloads/invoice"; echo 1 > "$WORK/say/codes"
A="$(answer "$(conn 106 "$H/Downloads/invoice" $MD5)")"; Q="$(calls)"
echo 1 > "$WORK/say/codes"; B="$(answer "$(conn 106 "$H/Downloads/invoice" $MD5)")"
proc 107 -- "$H/.cache/x/upd"; echo 0 > "$WORK/say/codes"; C="$(answer "$(conn 107 "$H/.cache/x/upd" $MD5)")"
proc 108 -- /tmp/.x/run; echo 0 > "$WORK/say/codes"; D="$(calls | grep -c warningyesnocancel)"; E="$(answer "$(conn 108 /tmp/.x/run $MD5)")"
check A6 '[ "$A" = "allow once forgeos-netask-once" ] && grep -q -- "--warningyesnocancel Careful: a program in your Downloads folder wants the internet." <<< "$Q" && grep -q -- "--yes-label Block --no-label Allow just this once" <<< "$Q" && [ "$B" = "allow once forgeos-netask-once" ] && [ "$(store "path:$H/Downloads/invoice" answer)" = ask ] && [ "${C% *}" = "deny always" ] && calls | grep -q "a program in a hidden folder" && [ "${E% *}" = "deny always" ] && calls | grep -q "a program in a temporary folder"'
# A7: Flatpak apps are known by their app id: ForgeOS's apps never asked; others asked by their menu name
fresh; proc 109 flatpak:com.brave.Browser "$(flatpak_app com.brave.Browser brave/brave)" -- /app/brave/brave; app org.example.Chat "Example Chat" chat
A="$(answer "$(conn 109 /app/brave/brave $MD5)")"
proc 110 flatpak:org.example.Chat "$(flatpak_app org.example.Chat bin/chat)" -- /app/bin/chat; echo 0 > "$WORK/say/codes"
B="$(answer "$(conn 110 /app/bin/chat $MD5)")"
check A7 '[ "${A% *}" = "allow always" ] && [ "$(store flatpak:com.brave.Browser kind)" = flatpak ] && [ "${B% *}" = "allow always" ] && calls | grep -q -- "--yesnocancel Example Chat wants to use the internet" && [ "$(calls | grep -c "^kdialog")" = 1 ]'
# A8: a fake "firefox" in Downloads is NOT Firefox: red question, not trusted
fresh; proc 111 -- "$H/Downloads/firefox"; echo 0 > "$WORK/say/codes"
A="$(answer "$(conn 111 "$H/Downloads/firefox" $MD5)")"
check A8 '[ "${A% *}" = "deny always" ] && calls | grep -q -- "--warningyesnocancel Careful: a program in your Downloads folder"'

echo
if [ "$failures" -eq 0 ]; then echo "All Ask Before Connecting tests A passed."; else echo "$failures test(s) failed."; cat "$WORK/service.log"; fi
exit "$((failures > 0))"
